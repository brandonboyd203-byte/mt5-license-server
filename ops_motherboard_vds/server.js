#!/usr/bin/env node
import http from 'http';
import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';

const PORT = Number(process.env.PORT || 8788);
const ROOT = path.resolve(process.cwd());
const DISCORD_METRICS_URL = process.env.DISCORD_METRICS_URL || 'https://discord-gpt-bot-production-4cb9.up.railway.app/metrics';
const DISCORD_METRICS_FALLBACK_URL = process.env.DISCORD_METRICS_FALLBACK_URL || 'https://discord-gpt-bot-production.up.railway.app/metrics';
const TELEMETRY_PATH = process.env.MT5_TELEMETRY_PATH || 'C:/GoldmineOps/reports/mt5_telemetry.json';
const LIVE_PROBE_PATH = process.env.MT5_LIVE_PROBE_PATH || 'C:/GoldmineOps/reports/mt5_live_probe.json';
const ISSUE_AUDIT_PATH = process.env.MT5_ISSUE_AUDIT_PATH || 'C:/GoldmineOps/reports/vds_issue_audit_light.json';
const ACCOUNTS_CSV_PATH = process.env.MT5_ACCOUNTS_CSV_PATH || 'C:/GoldmineOps/secure/vds_accounts.csv';
const COPIER_ACCOUNTS_CSV_PATH = process.env.MT5_COPIER_ACCOUNTS_CSV_PATH || 'C:/GoldmineOps/secure/copier_accounts.csv';
const MT5_ROOT = process.env.MT5_ROOT || 'C:/MT5';
const SNAPSHOT_DIR = process.env.TERMINAL_SNAPSHOT_DIR || 'C:/GoldmineOps/ops_motherboard/snapshots';
const SNAPSHOT_INDEX_PATH = process.env.TERMINAL_SNAPSHOT_INDEX || `${SNAPSHOT_DIR}/index.json`;
const SNAPSHOT_TASK_NAME = process.env.TERMINAL_SNAPSHOT_TASK || 'Goldmine_MT5_Snapshot_Refresh';
const SNAPSHOT_TRIGGER_COOLDOWN_MS = Number(process.env.TERMINAL_SNAPSHOT_TRIGGER_COOLDOWN_MS || 8000);
const SNAPSHOT_TRIGGER_ON_REQUEST = String(process.env.TERMINAL_SNAPSHOT_TRIGGER_ON_REQUEST || 'false').toLowerCase() === 'true';
const SNAPSHOT_STALE_MS = Number(process.env.TERMINAL_SNAPSHOT_STALE_MS || 45000);
const CHART_POLL_MIN_MS = Number(process.env.CHART_POLL_MIN_MS || 3000);
const CHART_MAX_BARS = Number(process.env.CHART_MAX_BARS || 320);
const CHART_MIN_BARS = Number(process.env.CHART_MIN_BARS || 120);
const CHART_BOOTSTRAP_DAYS = Math.max(1, Math.min(10, Number(process.env.CHART_BOOTSTRAP_DAYS || 4)));
const CHART_BOOTSTRAP_COOLDOWN_MS = Number(process.env.CHART_BOOTSTRAP_COOLDOWN_MS || 90000);
const CHART_BACKFILL_MAX_FILES = Number(process.env.CHART_BACKFILL_MAX_FILES || 250);
const CHART_BACKFILL_MAX_LINES = Number(process.env.CHART_BACKFILL_MAX_LINES || 300000);
const OPENCLAW_CONFIG_PATH = process.env.OPENCLAW_CONFIG_PATH || 'C:/Users/Administrator/.openclaw/openclaw.json';
const TELEGRAM_CONTROL_ENABLED = String(process.env.TELEGRAM_CONTROL_ENABLED || 'true').toLowerCase() === 'true';
const TELEGRAM_CONTROL_STATE_PATH = process.env.TELEGRAM_CONTROL_STATE_PATH || 'C:/GoldmineOps/ops_motherboard/telegram_control_state.json';
const TELEGRAM_CONTROL_CHAT_IDS = new Set(
  String(process.env.TELEGRAM_CONTROL_CHAT_IDS || '2093349528')
    .split(',')
    .map((s) => String(s || '').trim())
    .filter(Boolean),
);
const TELEGRAM_CONTROL_POLL_MS = Math.max(2500, Number(process.env.TELEGRAM_CONTROL_POLL_MS || 4000));
const TELEGRAM_CONTROL_ALLOW_SHARED_BOT = String(process.env.TELEGRAM_CONTROL_ALLOW_SHARED_BOT || 'false').toLowerCase() === 'true';
const VDS_HIDE_NAME_PARTS = [
  'BASE',
  'PRESET',
  'LAB',
  'DOMINION',
  'EDGE',
  'SURGE',
  'FRESH',
  'BRAND_NEW',
  'COPIER_NEW',
  'COPIER_CLEAN',
  'TF_SETUP',
];

const LIVE_CHART_SOURCES = {
  XAUUSD: 'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD',
  XAGUSD: 'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAG/USD',
};

const liveChartState = new Map();
const liveChartBackfillMeta = new Map();
let lastSnapshotTriggerAt = 0;
let telegramControlBusy = false;

const NO_CACHE_HEADERS = {
  'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
  Pragma: 'no-cache',
  Expires: '0',
};

function j(res, code, obj){ res.writeHead(code, { 'Content-Type':'application/json', ...NO_CACHE_HEADERS }); res.end(JSON.stringify(obj,null,2)); }
function txt(res, code, t){ res.writeHead(code, { 'Content-Type':'text/plain', ...NO_CACHE_HEADERS }); res.end(t); }
function round2(v){ return Number(Number(v || 0).toFixed(2)); }

function serveFile(res, filePath){
  try {
    const ext = path.extname(filePath).toLowerCase();
    const type = ext === '.html' ? 'text/html; charset=utf-8'
      : ext === '.css' ? 'text/css; charset=utf-8'
      : ext === '.js' ? 'text/javascript; charset=utf-8'
      : ext === '.json' ? 'application/json; charset=utf-8'
      : ext === '.png' ? 'image/png'
      : ext === '.jpg' || ext === '.jpeg' ? 'image/jpeg'
      : 'text/plain; charset=utf-8';
    res.writeHead(200, {
      'Content-Type': type,
      'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
      Pragma: 'no-cache',
      Expires: '0',
    });
    res.end(fs.readFileSync(filePath));
  } catch {
    txt(res, 404, 'not found');
  }
}

function ps(cmd){
  return new Promise((resolve)=>{
    exec(`powershell -NoProfile -Command "${cmd}"`, { timeout: 12000, maxBuffer: 1024*1024 }, (err, stdout, stderr)=>{
      resolve({ ok: !err, stdout: stdout?.trim()||'', stderr: stderr?.trim()||'', error: err?.message||null });
    });
  });
}

function readJsonFile(filePath){
  try {
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function ensureParentDir(filePath) {
  try {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
  } catch {}
}

function writeJsonFile(filePath, value) {
  try {
    ensureParentDir(filePath);
    fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
    return true;
  } catch {
    return false;
  }
}

function resolveTelegramControlBotToken() {
  const envToken = String(process.env.TELEGRAM_CONTROL_BOT_TOKEN || '').trim();
  if (envToken) return envToken;
  if (!TELEGRAM_CONTROL_ALLOW_SHARED_BOT) return '';
  const cfg = readJsonFile(OPENCLAW_CONFIG_PATH);
  return String(cfg?.channels?.telegram?.botToken || '').trim();
}

const TELEGRAM_CONTROL_BOT_TOKEN = resolveTelegramControlBotToken();

function readTelegramControlState() {
  const state = readJsonFile(TELEGRAM_CONTROL_STATE_PATH);
  if (state && Number.isFinite(Number(state.offset))) return state;
  return { offset: 0, lastHandledAt: null };
}

function writeTelegramControlState(state) {
  return writeJsonFile(TELEGRAM_CONTROL_STATE_PATH, {
    offset: Number(state?.offset || 0),
    lastHandledAt: state?.lastHandledAt || null,
  });
}

function buildTelegramApiUrl(method) {
  return `https://api.telegram.org/bot${TELEGRAM_CONTROL_BOT_TOKEN}/${method}`;
}

async function telegramApi(method, payload) {
  if (!TELEGRAM_CONTROL_BOT_TOKEN) throw new Error('telegram bot token missing');
  const r = await fetch(buildTelegramApiUrl(method), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload || {}),
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || data?.ok !== true) {
    throw new Error(data?.description || `telegram ${method} failed`);
  }
  return data;
}

function normalizeControlAction(actionRaw) {
  const raw = String(actionRaw || '').trim().toLowerCase().replace(/^\/+/, '');
  if (!raw) return '';
  const compact = raw.replace(/@[\w_]+/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
  if (!compact) return '';
  if (compact === 'help' || compact === 'commands' || compact === 'menu') return 'help';
  if (compact === 'status' || compact === 'health') return 'status';
  if (compact === 'telemetry' || compact === 'telemetry refresh' || compact === 'refresh telemetry') return 'telemetry-refresh';
  if (compact === 'pause' || compact === 'pause algo' || compact === 'pause trading' || compact === 'algo off' || compact === 'disable algo') return 'pause';
  if (compact === 'resume' || compact === 'resume algo' || compact === 'resume trading' || compact === 'algo on' || compact === 'enable algo') return 'resume';
  if (compact === 'restart' || compact === 'restart terminals' || compact === 'restart terminal' || compact === 'restart mt5' || compact === 'restart eas') return 'restart';
  if (compact === 'reboot' || compact === 'reboot host' || compact === 'reboot server' || compact === 'reboot system' || compact === 'restart host') return 'reboot';
  if (compact.startsWith('vds ')) return normalizeControlAction(compact.slice(4));
  return '';
}

function controlHelpText() {
  return [
    'VDS control commands:',
    'pause algo',
    'resume algo',
    'restart terminals',
    'reboot system',
    'status',
    'telemetry refresh',
  ].join('\n');
}

function controlCommandForAction(action) {
  if (action === 'pause') return "& 'C:/GoldmineOps/scripts/pause_live.ps1'";
  if (action === 'resume') return "& 'C:/GoldmineOps/scripts/resume_live.ps1'";
  if (action === 'restart') return "$tasks=Get-ScheduledTask -TaskName 'MT5_*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -notlike '*_SYS' } | Select-Object -ExpandProperty TaskName; foreach($t in $tasks){ schtasks /Run /TN $t | Out-Host }";
  if (action === 'status') return "Write-Output '=== terminal64 ==='; Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object Id,StartTime,CPU,WS,Path; Write-Output '=== tasks ==='; Get-ScheduledTask -TaskName 'MT5_*' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -notlike '*_SYS' } | Select-Object TaskName,State";
  if (action === 'telemetry-refresh') return "schtasks /Run /TN Goldmine_MT5_Telemetry_24x7 | Out-Host; Start-Sleep -Seconds 2; if(Test-Path 'C:\\GoldmineOps\\reports\\mt5_telemetry.json'){ Get-Item 'C:\\GoldmineOps\\reports\\mt5_telemetry.json' | Select-Object FullName,LastWriteTime,Length }";
  if (action === 'reboot') return "shutdown /r /t 5 /f";
  return '';
}

async function runControlAction(action, source = 'api') {
  const normalized = normalizeControlAction(action);
  if (!normalized) return { ok: false, action: String(action || ''), source, error: 'invalid action', stdout: '', stderr: '' };
  if (normalized === 'help') return { ok: true, action: normalized, source, stdout: controlHelpText(), stderr: '', error: null };
  const cmd = controlCommandForAction(normalized);
  if (!cmd) return { ok: false, action: normalized, source, error: 'unsupported action', stdout: '', stderr: '' };
  const out = await ps(cmd);
  return { ...out, action: normalized, source };
}

function formatControlResult(result) {
  const bits = [
    `action: ${result?.action || 'unknown'}`,
    `ok: ${result?.ok === true ? 'yes' : 'no'}`,
  ];
  const stdout = String(result?.stdout || '').trim();
  const stderr = String(result?.stderr || result?.error || '').trim();
  if (stdout) bits.push(`stdout:\n${stdout.slice(0, 3000)}`);
  if (stderr) bits.push(`stderr:\n${stderr.slice(0, 3000)}`);
  return bits.join('\n\n');
}

async function handleTelegramControlMessage(msg) {
  const chatId = String(msg?.chat?.id || '').trim();
  const text = String(msg?.text || '').trim();
  if (!chatId || !text) return;
  if (!TELEGRAM_CONTROL_CHAT_IDS.has(chatId)) {
    try {
      await telegramApi('sendMessage', {
        chat_id: chatId,
        text: 'VDS control denied for this chat.',
      });
    } catch {}
    return;
  }
  const action = normalizeControlAction(text);
  if (!action) {
    await telegramApi('sendMessage', {
      chat_id: chatId,
      text: controlHelpText(),
    });
    return;
  }
  const result = await runControlAction(action, 'telegram');
  await telegramApi('sendMessage', {
    chat_id: chatId,
    text: formatControlResult(result),
  });
}

async function pollTelegramControl() {
  if (!TELEGRAM_CONTROL_ENABLED || !TELEGRAM_CONTROL_BOT_TOKEN || telegramControlBusy) return;
  telegramControlBusy = true;
  try {
    const state = readTelegramControlState();
    const payload = {
      offset: Number(state.offset || 0),
      limit: 15,
      timeout: 0,
      allowed_updates: ['message'],
    };
    const res = await telegramApi('getUpdates', payload);
    const updates = Array.isArray(res?.result) ? res.result : [];
    let nextOffset = Number(state.offset || 0);
    for (const update of updates) {
      nextOffset = Math.max(nextOffset, Number(update?.update_id || 0) + 1);
      if (update?.message?.text) {
        await handleTelegramControlMessage(update.message);
      }
    }
    if (nextOffset !== Number(state.offset || 0) || updates.length) {
      writeTelegramControlState({ offset: nextOffset, lastHandledAt: new Date().toISOString() });
    }
  } catch (err) {
    writeJsonFile('C:/GoldmineOps/reports/telegram-control-error.json', {
      at: new Date().toISOString(),
      error: String(err?.message || err || 'unknown error'),
    });
  } finally {
    telegramControlBusy = false;
  }
}

function shouldHideVdsProfileName(nameRaw) {
  const name = String(nameRaw || '').trim().toUpperCase();
  if (!name) return true;
  if (name.endsWith(':BASE') || name.endsWith(':PRESETS')) return true;
  return VDS_HIDE_NAME_PARTS.some((part) => name.includes(part));
}

function sanitizeVdsTelemetry(telemetryRaw) {
  if (!telemetryRaw || typeof telemetryRaw !== 'object') return telemetryRaw;
  const telemetry = JSON.parse(JSON.stringify(telemetryRaw));
  const allowedProfiles = new Set(
    (Array.isArray(telemetry.profiles) ? telemetry.profiles : [])
      .filter((p) => !shouldHideVdsProfileName(p?.profile || p?.profileLabel))
      .map((p) => String(p.profile || '').trim())
      .filter(Boolean),
  );
  telemetry.profiles = (Array.isArray(telemetry.profiles) ? telemetry.profiles : [])
    .filter((p) => {
      const key = String(p?.profile || '').trim();
      if (!key) return false;
      return allowedProfiles.has(key);
    });
  telemetry.accounts = (Array.isArray(telemetry.accounts) ? telemetry.accounts : [])
    .filter((a) => {
      const key = String(a?.profile || '').trim();
      if (!key) return false;
      return allowedProfiles.has(key);
    });
  telemetry.liveFeed = (Array.isArray(telemetry.liveFeed) ? telemetry.liveFeed : [])
    .filter((row) => !shouldHideVdsProfileName(row?.profile || row?.profileLabel));
  if (telemetry.summary && typeof telemetry.summary === 'object') {
    telemetry.summary.profilesTotal = telemetry.profiles.length;
  }
  return telemetry;
}

function readLiveProbeMap(filePath = LIVE_PROBE_PATH) {
  const raw = readJsonFile(filePath);
  const rows = Array.isArray(raw?.profiles) ? raw.profiles : [];
  const byProfile = {};
  const byAccount = {};
  for (const row of rows) {
    if (!row || row.ok !== true) continue;
    const p = String(row.profile || '').trim();
    const a = row.account == null ? '' : String(row.account).trim();
    if (p) byProfile[p] = row;
    if (a) byAccount[a] = row;
  }
  return { generatedAt: raw?.generatedAt || null, byProfile, byAccount };
}

function recomputeLiveDayMetrics(row) {
  const dayBaseline = Number(row?.dayStartEquity ?? row?.dayStartBalance ?? row?.metrics?.day?.equityBaseline);
  const equity = Number(row?.currentEquity);
  if (!Number.isFinite(dayBaseline) || dayBaseline <= 0 || !Number.isFinite(equity)) return null;
  const net = round2(equity - dayBaseline);
  const pct = Number(((100 * net) / dayBaseline).toFixed(2));
  return { dayBaseline: round2(dayBaseline), dayNetUsd: net, dayReturnPct: pct };
}

function applyLiveProbeOverlay(telemetry, probeMap) {
  if (!telemetry || !probeMap) return telemetry;
  const profiles = Array.isArray(telemetry.profiles) ? telemetry.profiles : [];
  const accounts = Array.isArray(telemetry.accounts) ? telemetry.accounts : [];
  const byProfile = probeMap.byProfile || {};
  const byAccount = probeMap.byAccount || {};
  let touched = 0;

  for (const p of profiles) {
    const profile = String(p?.profile || '').trim();
    const account = String(p?.account || p?.accountId || '').trim();
    const probe = byProfile[profile] || (account ? byAccount[account] : null);
    if (!probe) continue;
    touched += 1;
    const bal = Number(probe.balance);
    const eq = Number(probe.equity);
    const op = Number(probe.profit);
    const pos = Number(probe.openPositions);
    const dep = Number(probe.depositTotal);
    const wd = Number(probe.withdrawTotal);
    const accountStartEq = Number(probe.accountStartEquity ?? probe.startEquity);
    const dayStartEq = Number(probe.dayStartEquity ?? probe.startEquity);
    const grossClosed = Number(probe.grossPnlClosed);
    const grossWithOpen = Number(probe.grossPnlWithOpen);

    if (Number.isFinite(bal)) {
      p.currentBalance = round2(bal);
      p.currentBalanceEst = round2(bal);
    }
    if (Number.isFinite(eq)) p.currentEquity = round2(eq);
    if (Number.isFinite(op)) p.openProfit = round2(op);
    if (Number.isFinite(pos) && pos >= 0) p.openPositions = Math.round(pos);
    else if (Number.isFinite(op)) p.openPositions = Math.abs(op) >= 0.01 ? 1 : 0;
    if (Number.isFinite(p.currentBalance) && Number.isFinite(p.openProfit) && !Number.isFinite(eq)) {
      p.currentEquity = round2(Number(p.currentBalance) + Number(p.openProfit));
    }
    if (Number.isFinite(dep)) p.depositAmount = round2(dep);
    if (Number.isFinite(wd)) p.withdrawAmount = round2(wd);
    if (Number.isFinite(accountStartEq)) p.accountStartEquity = round2(accountStartEq);
    if (Number.isFinite(dayStartEq)) {
      p.dayStartEquity = round2(dayStartEq);
      p.dayStartBalance = round2(dayStartEq);
    }
    if (Number.isFinite(grossClosed)) p.currentPnlGross = round2(grossClosed);
    if (Number.isFinite(grossWithOpen)) p.currentPnlWithOpen = round2(grossWithOpen);
    p.balanceSource = 'mt5-probe-live';

    const day = p?.metrics?.day;
    if (day) {
      const live = recomputeLiveDayMetrics(p);
      if (live) {
        day.equityBaseline = live.dayBaseline;
        day.netUsdLive = live.dayNetUsd;
        day.returnPctLive = live.dayReturnPct;
        day.netUsd = live.dayNetUsd;
        day.returnPct = live.dayReturnPct;
        p.dayNetUsd = live.dayNetUsd;
        p.dayReturnPct = live.dayReturnPct;
      }
    }
    if (day && Number.isFinite(op)) {
      day.openProfitUsd = round2(op);
    }
  }

  for (const a of accounts) {
    const key = String(a?.account || '').trim();
    if (!key) continue;
    const probe = byAccount[key];
    if (!probe) continue;
    const bal = Number(probe.balance);
    const eq = Number(probe.equity);
    const op = Number(probe.profit);
    const pos = Number(probe.openPositions);
    const dep = Number(probe.depositTotal);
    const wd = Number(probe.withdrawTotal);
    const accountStartEq = Number(probe.accountStartEquity ?? probe.startEquity);
    const dayStartEq = Number(probe.dayStartEquity ?? probe.startEquity);
    const grossClosed = Number(probe.grossPnlClosed);
    const grossWithOpen = Number(probe.grossPnlWithOpen);
    if (Number.isFinite(bal)) {
      a.currentBalance = round2(bal);
      a.currentBalanceEst = round2(bal);
    }
    if (Number.isFinite(eq)) a.currentEquity = round2(eq);
    if (Number.isFinite(op)) a.openProfit = round2(op);
    if (Number.isFinite(pos) && pos >= 0) a.openPositions = Math.round(pos);
    else if (Number.isFinite(op)) a.openPositions = Math.abs(op) >= 0.01 ? 1 : 0;
    if (Number.isFinite(a.currentBalance) && Number.isFinite(a.openProfit) && !Number.isFinite(eq)) {
      a.currentEquity = round2(Number(a.currentBalance) + Number(a.openProfit));
    }
    if (Number.isFinite(dep)) a.depositAmount = round2(dep);
    if (Number.isFinite(wd)) a.withdrawAmount = round2(wd);
    if (Number.isFinite(accountStartEq)) a.accountStartEquity = round2(accountStartEq);
    if (Number.isFinite(dayStartEq)) {
      a.dayStartEquity = round2(dayStartEq);
      a.dayStartBalance = round2(dayStartEq);
    }
    if (Number.isFinite(grossClosed)) a.currentPnlGross = round2(grossClosed);
    if (Number.isFinite(grossWithOpen)) a.currentPnlWithOpen = round2(grossWithOpen);
    a.balanceSource = 'mt5-probe-live';
    const live = recomputeLiveDayMetrics(a);
    if (live) {
      a.dayNetLiveUsd = live.dayNetUsd;
      a.dayNetUsd = live.dayNetUsd;
      a.dayReturnPct = live.dayReturnPct;
      a.dayReturnPctRealized = live.dayReturnPct;
      a.dayBaseline = live.dayBaseline;
    }
  }

  if (touched > 0 && telemetry.summary) {
    const openFromProfiles = profiles.reduce((sum, p) => sum + Number(p?.openProfit || 0), 0);
    const balFromProfiles = profiles.reduce((sum, p) => sum + Number(p?.currentBalance || p?.currentBalanceEst || 0), 0);
    const eqFromProfiles = profiles.reduce((sum, p) => sum + Number(p?.currentEquity || p?.currentBalance || p?.currentBalanceEst || 0), 0);
    const posFromProfiles = profiles.reduce((sum, p) => sum + Number(p?.openPositions || 0), 0);
    const dayBaselineFromProfiles = profiles.reduce((sum, p) => sum + Number(p?.dayStartEquity || p?.dayStartBalance || p?.metrics?.day?.equityBaseline || 0), 0);
    const dayNetFromProfiles = profiles.reduce((sum, p) => {
      const rawDayNet = p?.metrics?.day?.netUsdLive ?? p?.metrics?.day?.netUsd ?? p?.dayNetUsd ?? 0;
      return sum + Number(rawDayNet);
    }, 0);
    telemetry.summary.totalOpenProfitUsd = round2(openFromProfiles);
    telemetry.summary.estimatedCurrentBalanceTotal = round2(balFromProfiles);
    telemetry.summary.estimatedCurrentEquityTotal = round2(eqFromProfiles);
    telemetry.summary.totalOpenPositions = Math.round(posFromProfiles);
    if (telemetry.summary.day && dayBaselineFromProfiles > 0) {
      telemetry.summary.day.baseline = round2(dayBaselineFromProfiles);
      telemetry.summary.day.netUsdLive = round2(dayNetFromProfiles);
      telemetry.summary.day.netUsd = round2(dayNetFromProfiles);
      telemetry.summary.day.returnPctLive = Number(((100 * dayNetFromProfiles) / dayBaselineFromProfiles).toFixed(2));
      telemetry.summary.day.returnPct = telemetry.summary.day.returnPctLive;
    }
  }

  telemetry.source = { ...(telemetry.source || {}), liveProbeFile: LIVE_PROBE_PATH, liveProbeGeneratedAt: probeMap.generatedAt };
  return telemetry;
}

function sanitizeSnapshotFile(name) {
  const base = path.basename(String(name || ''));
  if (!base || base.includes('..')) return null;
  if (!/^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(base)) return null;
  return base;
}

function maybeTriggerSnapshotRefresh() {
  const now = Date.now();
  if ((now - lastSnapshotTriggerAt) < SNAPSHOT_TRIGGER_COOLDOWN_MS) return Promise.resolve();
  lastSnapshotTriggerAt = now;
  return ps(`schtasks /Run /TN ${SNAPSHOT_TASK_NAME}`).catch(() => null);
}

function readAccountsCsv(filePath){
  try {
    if (!fs.existsSync(filePath)) return {};
    const raw = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
    const lines = raw.split(/\r?\n/).map((l)=>l.trim()).filter(Boolean);
    if (lines.length < 2) return {};
    const unquote = (v) => String(v || '').trim().replace(/^"(.*)"$/, '$1').trim();
    const head = lines[0].split(',').map((h)=>unquote(h).toLowerCase());
    const idx = (k)=>head.indexOf(k);
    const pIdx = idx('profile');
    if (pIdx < 0) return {};
    const out = {};
    for (const line of lines.slice(1)) {
      const cols = line.split(',').map((c)=>unquote(c));
      const profile = cols[pIdx];
      if (!profile) continue;
      out[profile] = {
        account: idx('account') >= 0 ? (cols[idx('account')] || null) : null,
        server: idx('server') >= 0 ? (cols[idx('server')] || null) : null,
        botName: idx('bot') >= 0 ? (cols[idx('bot')] || null) : null,
        symbols: idx('symbols') >= 0 ? (cols[idx('symbols')] || null) : null,
      };
    }
    return out;
  } catch {
    return {};
  }
}

function enrichTelemetryProfiles(telemetry, accountMap) {
  if (!telemetry || !Array.isArray(telemetry.profiles)) return telemetry;
  telemetry.profiles = telemetry.profiles.map((p) => {
    const m = accountMap?.[p?.profile] || {};
    return {
      ...p,
      account: p?.account || m.account || null,
      accountId: p?.accountId || p?.account || m.account || null,
      botName: p?.botName || m.botName || null,
      symbols: p?.symbols || m.symbols || null,
      brokerServer: p?.brokerServer || m.server || null,
    };
  });
  return telemetry;
}

function readIssueAuditMap(filePath = ISSUE_AUDIT_PATH) {
  const raw = readJsonFile(filePath);
  const rows = Array.isArray(raw?.rows) ? raw.rows : [];
  const byProfile = {};
  for (const row of rows) {
    const key = String(row?.profile || '').trim();
    if (!key) continue;
    byProfile[key] = row;
  }
  return {
    generatedAt: raw?.generatedAt || null,
    cutoff: raw?.cutoff || null,
    byProfile,
  };
}

function applyIssueAuditOverlay(telemetry, auditMap) {
  if (!telemetry || !Array.isArray(telemetry.profiles)) return telemetry;
  const byProfile = auditMap?.byProfile || {};
  telemetry.profiles = telemetry.profiles.map((p) => {
    const issue = byProfile[String(p?.profile || '').trim()];
    if (!issue) return p;
    const faults = [];
    if (Number(issue.tp1CloseFailed) > 0) faults.push(`TP1 close failed x${Number(issue.tp1CloseFailed)}`);
    if (Number(issue.closeVolumeLow) > 0) faults.push(`TP1 skip closeVol x${Number(issue.closeVolumeLow)}`);
    if (Number(issue.invalidStops) > 0) faults.push(`invalid stops x${Number(issue.invalidStops)}`);
    if (Number(issue.offQuotes) > 0) faults.push(`off quotes x${Number(issue.offQuotes)}`);
    if (Number(issue.tradeContextBusy) > 0) faults.push(`trade busy x${Number(issue.tradeContextBusy)}`);
    if (Number(issue.licenseOrAuth) > 0) faults.push(`auth/license x${Number(issue.licenseOrAuth)}`);
    if (Number(issue.orderSendFailed) > 0) faults.push(`order send fail x${Number(issue.orderSendFailed)}`);

    const status = p?.metrics?.status || {};
    const reasonBase = String(status.reason || '');
    const reasonAppend = faults.length ? `Faults: ${faults.slice(0, 3).join(' | ')}` : '';
    const mergedReason = [reasonBase, reasonAppend].filter(Boolean).join(' || ');

    return {
      ...p,
      issueAudit: {
        generatedAt: auditMap?.generatedAt || null,
        cutoff: auditMap?.cutoff || null,
        totalIssues: Number(issue.totalIssues || 0),
        tp1Tag: Number(issue.tp1Tag || 0),
        tp1CloseFailed: Number(issue.tp1CloseFailed || 0),
        closeVolumeLow: Number(issue.closeVolumeLow || 0),
        invalidStops: Number(issue.invalidStops || 0),
        modifyFailed: Number(issue.modifyFailed || 0),
        offQuotes: Number(issue.offQuotes || 0),
        tradeContextBusy: Number(issue.tradeContextBusy || 0),
        licenseOrAuth: Number(issue.licenseOrAuth || 0),
        orderSendFailed: Number(issue.orderSendFailed || 0),
        sampleTp1: issue.sample_tp1 || '',
        sampleCloseVol: issue.sample_cv || '',
        sampleStops: issue.sample_stops || '',
        sampleExec: issue.sample_exec || '',
      },
      metrics: {
        ...(p.metrics || {}),
        status: {
          ...(status || {}),
          reason: mergedReason || reasonBase || '',
        },
      },
    };
  });
  return telemetry;
}

function readCsvRows(filePath) {
  try {
    if (!fs.existsSync(filePath)) return [];
    const raw = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
    const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    if (lines.length < 2) return [];
    const unquote = (v) => String(v || '').trim().replace(/^"(.*)"$/, '$1').trim();
    const headers = lines[0].split(',').map((h) => unquote(h).toLowerCase());
    const rows = [];
    for (const line of lines.slice(1)) {
      const cols = line.split(',').map((c) => unquote(c));
      const row = {};
      headers.forEach((h, i) => { row[h] = cols[i] || ''; });
      rows.push(row);
    }
    return rows;
  } catch {
    return [];
  }
}

function inferRiskPct(v) {
  const direct = Number(v?.riskPct);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const p = String(v?.profile || '').toUpperCase();
  if (p.includes('SILVER20') || p.includes('RISK20')) return 20;
  if (p.includes('SILVER15') || p.includes('RISK15')) return 15;
  return 9;
}

function inferCashFlows(profileRow) {
  const dep = Number(profileRow?.depositAmount);
  const wd = Number(profileRow?.withdrawAmount);
  if (Number.isFinite(dep) || Number.isFinite(wd)) {
    return {
      deposit: Number.isFinite(dep) ? round2(dep) : 0,
      withdraw: Number.isFinite(wd) ? round2(wd) : 0,
    };
  }
  const start = Number(profileRow?.dayStartEquity ?? profileRow?.dayStartBalance);
  if (!Number.isFinite(start)) return { deposit: 0, withdraw: 0 };
  return {
    deposit: 0,
    withdraw: 0,
  };
}

function buildCopierFeed(telemetry, copierRows, probeMap = null) {
  const profiles = Array.isArray(telemetry?.profiles) ? telemetry.profiles : [];
  const configRows = Array.isArray(copierRows) ? copierRows : [];

  const configuredProfiles = new Set(
    configRows.map((r) => String(r.profile || '').trim()).filter(Boolean),
  );
  const configuredAccounts = new Set(
    configRows.map((r) => String(r.account || '').replace(/\D/g, '')).filter(Boolean),
  );

  const filtered = profiles.filter((p) => {
    const profile = String(p?.profile || '').trim();
    const account = String(p?.account || p?.accountId || '').replace(/\D/g, '');
    if (configuredProfiles.size || configuredAccounts.size) {
      return configuredProfiles.has(profile) || (account && configuredAccounts.has(account));
    }
    return /JORDAN|COPIER/i.test(profile);
  });

  const rows = filtered.map((p) => {
    const day = p?.metrics?.day || {};
    const week = p?.metrics?.week || {};
    const status = p?.metrics?.status || {};
    const account = String(p?.account || p?.accountId || '').replace(/\D/g, '');
    const cfg = configRows.find((r) => String(r.account || '').replace(/\D/g, '') === account)
      || configRows.find((r) => String(r.profile || '').trim() === String(p?.profile || '').trim())
      || null;
    const flows = inferCashFlows(p);
    const probe = probeMap?.byProfile?.[String(p?.profile || '').trim()]
      || probeMap?.byAccount?.[account]
      || null;
    const probeDeposit = Number(probe?.depositTotal);
    const probeWithdraw = Number(probe?.withdrawTotal);
    const probeAccountStartEq = Number(probe?.accountStartEquity ?? probe?.startEquity);
    const probeDayStartEq = Number(probe?.dayStartEquity ?? probe?.startEquity);
    const probeGrossClosed = Number(probe?.grossPnlClosed);
    const probeGrossWithOpen = Number(probe?.grossPnlWithOpen);
    const hasLiveProbe = String(p?.balanceSource || '').toLowerCase().includes('mt5-probe-live');
    const safeBalance = hasLiveProbe
      ? (Number.isFinite(Number(p?.currentBalance)) ? Number(p.currentBalance) : 0)
      : 5000;
    const safeEquity = hasLiveProbe
      ? (Number.isFinite(Number(p?.currentEquity)) ? Number(p.currentEquity) : safeBalance)
      : safeBalance;
    const safeOpen = hasLiveProbe
      ? (Number.isFinite(Number(p?.openProfit)) ? Number(p.openProfit) : 0)
      : 0;
    let safeDayNet = hasLiveProbe
      ? (Number.isFinite(Number(day?.netUsdLive ?? day?.netUsd)) ? Number(day.netUsdLive ?? day.netUsd) : 0)
      : 0;
    let safeDayPct = hasLiveProbe
      ? (Number.isFinite(Number(day?.returnPctLive ?? day?.returnPct)) ? Number(day.returnPctLive ?? day.returnPct) : null)
      : 0;
    const safeDayStartEq = Number.isFinite(probeDayStartEq)
      ? probeDayStartEq
      : (Number.isFinite(Number(p?.dayStartEquity ?? p?.dayStartBalance)) ? Number(p.dayStartEquity ?? p.dayStartBalance) : null);
    if (hasLiveProbe && Number.isFinite(safeEquity) && Number.isFinite(safeDayStartEq) && safeDayStartEq > 0) {
      const equityDelta = round2(safeEquity - safeDayStartEq);
      // Conservative withdrawal-aware correction:
      // if the day number is negative and close to total withdrawals, treat it as cashflow distortion.
      const wd = Number.isFinite(probeWithdraw)
        ? probeWithdraw
        : (Number.isFinite(Number(p?.withdrawAmount)) ? Number(p.withdrawAmount) : null);
      if (Number.isFinite(wd) && safeDayNet < 0 && Math.abs(safeDayNet) <= (wd + 75)) {
        safeDayNet = round2(equityDelta + wd);
      } else if (!Number.isFinite(Number(day?.netUsdLive ?? day?.netUsd))) {
        safeDayNet = equityDelta;
      }
      safeDayPct = Number(((100 * safeDayNet) / safeDayStartEq).toFixed(2));
    }
    return {
      profile: p?.profile || null,
      profileLabel: p?.profileLabel || p?.profile || null,
      account: account || null,
      client: cfg?.client || cfg?.name || null,
      brokerServer: cfg?.server || null,
      botName: cfg?.bot || p?.botName || null,
      riskPct: inferRiskPct(p),
      leverage: p?.leverage || null,
      depositAmount: Number.isFinite(probeDeposit) ? round2(probeDeposit) : flows.deposit,
      withdrawAmount: Number.isFinite(probeWithdraw) ? round2(probeWithdraw) : flows.withdraw,
      accountStartEquity: Number.isFinite(probeAccountStartEq)
        ? round2(probeAccountStartEq)
        : (Number.isFinite(Number(p?.accountStartEquity))
          ? round2(Number(p.accountStartEquity))
          : null),
      dayStartEquity: Number.isFinite(probeDayStartEq)
        ? round2(probeDayStartEq)
        : (Number.isFinite(Number(p?.dayStartEquity ?? p?.dayStartBalance))
          ? round2(Number(p.dayStartEquity ?? p.dayStartBalance))
          : null),
      balance: safeBalance,
      equity: safeEquity,
      openProfit: safeOpen,
      currentPnlGross: Number.isFinite(probeGrossClosed)
        ? round2(probeGrossClosed)
        : (Number.isFinite(Number(p?.currentPnlGross)) ? round2(Number(p.currentPnlGross)) : null),
      currentPnlWithOpen: Number.isFinite(probeGrossWithOpen)
        ? round2(probeGrossWithOpen)
        : (Number.isFinite(Number(p?.currentPnlWithOpen)) ? round2(Number(p.currentPnlWithOpen)) : null),
      dayNetUsd: safeDayNet,
      dayReturnPct: safeDayPct,
      weekNetUsd: Number.isFinite(Number(week?.netUsd)) ? Number(week.netUsd) : 0,
      weekReturnPct: Number.isFinite(Number(week?.returnPct)) ? Number(week.returnPct) : null,
      status: hasLiveProbe ? (status?.label || 'UNKNOWN') : 'WARMUP',
      statusReason: hasLiveProbe ? (status?.reason || '') : 'Awaiting first live MT5 probe snapshot',
      updatedAt: p?.lastActivityAt || p?.snapshotAt || p?.lastSyncAt || telemetry?.generatedAt || null,
    };
  }).sort((a, b) => Number(b.dayNetUsd || 0) - Number(a.dayNetUsd || 0));

  return {
    generatedAt: telemetry?.generatedAt || new Date().toISOString(),
    columns: [
      'profileLabel', 'account', 'client', 'botName', 'riskPct', 'leverage',
      'depositAmount', 'withdrawAmount', 'accountStartEquity', 'dayStartEquity', 'balance', 'equity',
      'openProfit', 'currentPnlGross', 'currentPnlWithOpen', 'dayNetUsd', 'dayReturnPct', 'weekNetUsd', 'weekReturnPct',
      'status', 'updatedAt',
    ],
    rows,
  };
}

function floorToM5(ms = Date.now()) {
  const bucket = 5 * 60 * 1000;
  return Math.floor(ms / bucket) * bucket;
}

function candleFromPrice(tsMs, price) {
  return {
    time: Math.floor(floorToM5(tsMs) / 1000),
    open: price,
    high: price,
    low: price,
    close: price,
  };
}

function appendCandle(symbol, tsMs, price) {
  if (!Number.isFinite(price) || price <= 0) return;
  const key = String(symbol || '').toUpperCase();
  if (!key) return;
  const state = liveChartState.get(key) || { bars: [], updatedAt: null, lastPrice: null, lastFetchAt: 0 };
  const barTime = Math.floor(floorToM5(tsMs) / 1000);
  const bars = state.bars;
  const prev = bars.length ? bars[bars.length - 1] : null;
  if (!prev || Number(prev.time) !== barTime) {
    bars.push(candleFromPrice(tsMs, price));
  } else {
    prev.high = Math.max(Number(prev.high), price);
    prev.low = Math.min(Number(prev.low), price);
    prev.close = price;
  }
  if (bars.length > CHART_MAX_BARS) bars.splice(0, bars.length - CHART_MAX_BARS);
  state.updatedAt = new Date(tsMs).toISOString();
  state.lastPrice = price;
  liveChartState.set(key, state);
}

function parseSwissquoteMid(raw) {
  const arr = Array.isArray(raw) ? raw : [];
  const first = arr[0] || {};
  const prices = Array.isArray(first.spreadProfilePrices) ? first.spreadProfilePrices : [];
  const pick = prices.find((p) => String(p?.spreadProfile || '').toLowerCase() === 'prime')
    || prices.find((p) => String(p?.spreadProfile || '').toLowerCase() === 'premium')
    || prices[0];
  if (!pick) return null;
  const bid = Number(pick.bid);
  const ask = Number(pick.ask);
  if (!Number.isFinite(bid) || !Number.isFinite(ask)) return null;
  return Number(((bid + ask) / 2).toFixed(3));
}

function backfillSymbolFromTelemetry(symbol) {
  const key = String(symbol || '').toUpperCase();
  if (!key || !fs.existsSync(TELEMETRY_PATH)) return;
  const telemetry = readJsonFile(TELEMETRY_PATH);
  const feed = Array.isArray(telemetry?.liveFeed) ? telemetry.liveFeed : [];
  if (!feed.length) return;
  const re = new RegExp(`\\b${key}\\b[^\\n]*?at\\s+([0-9]+(?:\\.[0-9]+)?)`, 'i');
  const parsed = [];
  for (const e of feed) {
    const text = String(e?.text || '');
    const m = text.match(re);
    if (!m) continue;
    const price = Number(m[1]);
    if (!Number.isFinite(price) || price <= 0) continue;
    const t = Number(e?.t || Date.parse(e?.ts || '') || Date.now());
    parsed.push({ t, price });
  }
  if (!parsed.length) return;
  parsed.sort((a, b) => a.t - b.t).forEach((p) => appendCandle(key, p.t, p.price));
}

function detectTextEncoding(filePath) {
  try {
    const fd = fs.openSync(filePath, 'r');
    const buf = Buffer.alloc(4096);
    const read = fs.readSync(fd, buf, 0, buf.length, 0);
    fs.closeSync(fd);
    const probe = buf.slice(0, read);
    if (probe.length >= 2 && probe[0] === 0xff && probe[1] === 0xfe) return 'utf16le';
    if (probe.length >= 2 && probe[0] === 0xfe && probe[1] === 0xff) return 'utf16le';
    if (probe.length >= 3 && probe[0] === 0xef && probe[1] === 0xbb && probe[2] === 0xbf) return 'utf8';
    const sample = Math.min(probe.length, 2048);
    let zeros = 0;
    for (let i = 0; i < sample; i += 1) if (probe[i] === 0) zeros += 1;
    return sample > 0 && (zeros / sample) > 0.2 ? 'utf16le' : 'utf8';
  } catch {
    return 'utf8';
  }
}

function parseLineDateTime(day, hhmmssMs) {
  const m = String(hhmmssMs || '').match(/^(\d{2}):(\d{2}):(\d{2})\.(\d{3})$/);
  if (!m || !/^\d{8}$/.test(day)) return null;
  const iso = `${day.slice(0, 4)}-${day.slice(4, 6)}-${day.slice(6, 8)}T${m[1]}:${m[2]}:${m[3]}.${m[4]}`;
  const ts = Date.parse(iso);
  return Number.isFinite(ts) ? ts : null;
}

function readLatestLogFiles() {
  const out = [];
  try {
    const profileDirs = fs.readdirSync(MT5_ROOT, { withFileTypes: true }).filter((d) => d.isDirectory());
    for (const profile of profileDirs) {
      const logsDir = path.join(MT5_ROOT, profile.name, 'Logs');
      if (!fs.existsSync(logsDir)) continue;
      const files = fs.readdirSync(logsDir)
        .filter((n) => /^\d{8}\.log$/i.test(n))
        .sort((a, b) => b.localeCompare(a))
        .slice(0, CHART_BOOTSTRAP_DAYS);
      for (const name of files) out.push(path.join(logsDir, name));
      if (out.length >= CHART_BACKFILL_MAX_FILES) break;
    }
  } catch {}
  return out.slice(0, CHART_BACKFILL_MAX_FILES);
}

function extractSymbolTicksFromLog(filePath, symbol) {
  const key = String(symbol || '').toUpperCase();
  const name = path.basename(filePath);
  const day = name.replace(/\.log$/i, '');
  if (!/^\d{8}$/.test(day)) return [];
  const reDeal = new RegExp(`(\\d{2}:\\d{2}:\\d{2}\\.\\d{3}).*?\\bdeal\\s+#\\d+\\s+(?:buy|sell)\\s+[0-9.]+\\s+${key}\\s+at\\s+([0-9]+(?:\\.[0-9]+)?)`, 'i');
  const reOrder = new RegExp(`(\\d{2}:\\d{2}:\\d{2}\\.\\d{3}).*?\\border\\s+#\\d+\\s+(?:buy|sell).*?\\s+${key}\\s+at\\s+([0-9]+(?:\\.[0-9]+)?)`, 'i');
  try {
    const enc = detectTextEncoding(filePath);
    const text = fs.readFileSync(filePath, enc);
    const lines = String(text || '').split(/\r?\n/);
    const ticks = [];
    for (const line of lines) {
      if (!line || !line.includes(key) || !line.includes(' at ')) continue;
      const match = line.match(reDeal) || line.match(reOrder);
      if (!match) continue;
      const ts = parseLineDateTime(day, match[1]);
      const price = Number(match[2]);
      if (!Number.isFinite(ts) || !Number.isFinite(price) || price <= 0) continue;
      ticks.push({ t: ts, price });
      if (ticks.length >= CHART_BACKFILL_MAX_LINES) break;
    }
    return ticks;
  } catch {
    return [];
  }
}

function densifyCandles(candles, limit, nowMs = Date.now()) {
  const bars = Array.isArray(candles)
    ? candles
      .map((c) => ({
        time: Number(c?.time),
        open: Number(c?.open),
        high: Number(c?.high),
        low: Number(c?.low),
        close: Number(c?.close),
      }))
      .filter((c) => Number.isFinite(c.time) && Number.isFinite(c.open) && Number.isFinite(c.high) && Number.isFinite(c.low) && Number.isFinite(c.close))
      .sort((a, b) => a.time - b.time)
    : [];
  if (!bars.length) return [];
  const bucketSec = 300;
  const byTime = new Map();
  bars.forEach((b) => byTime.set(Number(b.time), b));
  const last = bars[bars.length - 1];
  const nowBucketSec = Math.floor(floorToM5(nowMs) / 1000);
  const endSec = Math.max(Number(last.time), nowBucketSec);
  const maxBars = Math.max(30, Math.min(CHART_MAX_BARS, Number(limit || CHART_MAX_BARS)));
  const startSec = endSec - ((maxBars - 1) * bucketSec);
  const dense = [];
  let prevClose = bars[0].close;
  for (let t = startSec; t <= endSec; t += bucketSec) {
    const row = byTime.get(t);
    if (row) {
      dense.push(row);
      prevClose = row.close;
      continue;
    }
    dense.push({ time: t, open: prevClose, high: prevClose, low: prevClose, close: prevClose });
  }
  return dense.slice(-maxBars);
}

function shouldBootstrapLogs(symbol) {
  const key = String(symbol || '').toUpperCase();
  const meta = liveChartBackfillMeta.get(key) || { lastAttemptAt: 0, inFlight: false };
  if (meta.inFlight) return false;
  const state = liveChartState.get(key);
  const bars = Array.isArray(state?.bars) ? state.bars.length : 0;
  if (bars >= CHART_MIN_BARS) return false;
  return (Date.now() - Number(meta.lastAttemptAt || 0)) > CHART_BOOTSTRAP_COOLDOWN_MS;
}

async function bootstrapSymbolFromTerminalLogs(symbol) {
  const key = String(symbol || '').toUpperCase();
  if (!key) return;
  const currentMeta = liveChartBackfillMeta.get(key) || { lastAttemptAt: 0, inFlight: false };
  if (currentMeta.inFlight) return;
  liveChartBackfillMeta.set(key, { ...currentMeta, inFlight: true, lastAttemptAt: Date.now() });
  try {
    const files = readLatestLogFiles();
    if (!files.length) return;
    const merged = [];
    for (const filePath of files) {
      const ticks = extractSymbolTicksFromLog(filePath, key);
      if (ticks.length) merged.push(...ticks);
      if (merged.length >= CHART_BACKFILL_MAX_LINES) break;
    }
    if (!merged.length) return;
    merged
      .sort((a, b) => a.t - b.t)
      .slice(-CHART_BACKFILL_MAX_LINES)
      .forEach((row) => appendCandle(key, row.t, row.price));
  } catch {
    // Best effort backfill.
  } finally {
    const nextMeta = liveChartBackfillMeta.get(key) || {};
    liveChartBackfillMeta.set(key, { ...nextMeta, inFlight: false, lastAttemptAt: Date.now() });
  }
}

async function fetchLiveQuote(symbol) {
  const key = String(symbol || '').toUpperCase();
  const url = LIVE_CHART_SOURCES[key];
  if (!url) return null;
  const state = liveChartState.get(key) || { bars: [], updatedAt: null, lastPrice: null, lastFetchAt: 0 };
  const now = Date.now();
  if ((now - Number(state.lastFetchAt || 0)) < CHART_POLL_MIN_MS) return state;
  state.lastFetchAt = now;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2200);
    const r = await fetch(url, { signal: ctrl.signal });
    clearTimeout(t);
    if (!r.ok) return state;
    const raw = await r.json();
    const mid = parseSwissquoteMid(raw);
    if (Number.isFinite(mid)) appendCandle(key, now, mid);
  } catch {}
  return liveChartState.get(key) || state;
}

async function ensureLiveChart(symbol) {
  const key = String(symbol || '').toUpperCase();
  if (!LIVE_CHART_SOURCES[key]) return { symbol: key, candles: [], updatedAt: null, lastPrice: null };
  const current = liveChartState.get(key);
  if (!current || !Array.isArray(current.bars) || !current.bars.length) backfillSymbolFromTelemetry(key);
  if (shouldBootstrapLogs(key)) await bootstrapSymbolFromTerminalLogs(key);
  const state = await fetchLiveQuote(key);
  return {
    symbol: key,
    candles: Array.isArray(state?.bars) ? state.bars : [],
    updatedAt: state?.updatedAt || null,
    lastPrice: Number.isFinite(Number(state?.lastPrice)) ? Number(state.lastPrice) : null,
  };
}

async function fetchJson(url){
  try {
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 2200);
    const r = await fetch(url,{signal:ctrl.signal});
    clearTimeout(t);
    if(!r.ok) return null;
    try { return await r.json(); } catch { return { ok:true, nonJson:true }; }
  } catch { return null; }
}

async function fetchOk(url){
  try {
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 2200);
    const r = await fetch(url,{signal:ctrl.signal});
    clearTimeout(t);
    return r.ok;
  } catch { return false; }
}

function metricsRoot(url){
  return url.replace(/\/metrics\/?$/, '/');
}

const server = http.createServer(async (req,res)=>{
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/health') return txt(res,200,'OK');

  if (url.pathname === '/') return serveFile(res, path.join(ROOT, 'index.html'));
  if (url.pathname === '/app.js') return serveFile(res, path.join(ROOT, 'app.js'));
  if (url.pathname === '/styles.css') return serveFile(res, path.join(ROOT, 'styles.css'));
  if (url.pathname.startsWith('/snapshots/')) {
    const file = sanitizeSnapshotFile(url.pathname.slice('/snapshots/'.length));
    if (!file) return txt(res, 404, 'not found');
    return serveFile(res, path.join(SNAPSHOT_DIR, file));
  }

  if (url.pathname === '/api/status' || url.pathname === '/api/fast-status') {
    const fast = url.pathname === '/api/fast-status';
    const telemetryRaw = readJsonFile(TELEMETRY_PATH);
    const liveProbe = readLiveProbeMap(LIVE_PROBE_PATH);
    const telemetry = sanitizeVdsTelemetry(applyLiveProbeOverlay(telemetryRaw, liveProbe));
    const copierFeed = buildCopierFeed(telemetry, readCsvRows(COPIER_ACCOUNTS_CSV_PATH), liveProbe);
    const accountMap = readAccountsCsv(ACCOUNTS_CSV_PATH);
    enrichTelemetryProfiles(telemetry, accountMap);
    applyIssueAuditOverlay(telemetry, readIssueAuditMap(ISSUE_AUDIT_PATH));

    const p1 = ps("(Get-Process terminal64 -ErrorAction SilentlyContinue | Measure-Object).Count");
    const p2 = ps("(Get-Process metaeditor64 -ErrorAction SilentlyContinue | Measure-Object).Count");
    const latest = fast
      ? Promise.resolve({ ok:true, stdout:'[]', stderr:'', error:null })
      : ps("if(Test-Path 'C:/GoldmineOps/reports/raw'){ Get-ChildItem 'C:/GoldmineOps/reports/raw' -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 6 FullName,LastWriteTime | ConvertTo-Json -Depth 4 }");
    const liveLog = fast
      ? Promise.resolve({ ok:true, stdout:'', stderr:'', error:null })
      : ps("if(Test-Path 'C:/GoldmineOps/reports/live-window.log'){ Get-Content 'C:/GoldmineOps/reports/live-window.log' -Tail 20 }");

    const metricsCandidates = [DISCORD_METRICS_URL, DISCORD_METRICS_FALLBACK_URL].filter(Boolean);
    let discordMetrics = null;
    let discordHealth = fast ? { connected:false, source:'skipped' } : { connected:false, source:'none' };
    if (!fast) {
      for (const metricsUrl of metricsCandidates) {
        const candidate = await fetchJson(metricsUrl);
        if (candidate) {
          discordMetrics = candidate;
          discordHealth = { connected:true, source:'metrics', url:metricsUrl };
          break;
        }
      }
      if (!discordHealth.connected) {
        for (const metricsUrl of metricsCandidates) {
          const rootUrl = metricsRoot(metricsUrl);
          const ok = await fetchOk(rootUrl);
          if (ok) {
            discordHealth = { connected:true, source:'root-health', url:rootUrl };
            break;
          }
        }
      }
    }

    const [p1r, p2r, latestr, liveLogr] = await Promise.all([p1, p2, latest, liveLog]);

    let latestReports = [];
    try { latestReports = JSON.parse(latestr.stdout || '[]'); if(!Array.isArray(latestReports)) latestReports=[latestReports]; } catch {}

    const telemetryProfiles = Array.isArray(telemetry?.profiles) ? telemetry.profiles : [];
    const telemetryRuntimeHits = telemetryProfiles.reduce((sum, p) => sum + Number(p?.metrics?.day?.unmatchedDeals || 0), 0);

    const profilesSummary = telemetryProfiles.map((p) => {
      const hasRuntimeData = Boolean(p?.lastSyncAt || p?.lastActivityAt || p?.snapshotAt);
      const readErrText = String(p?.dataQuality?.terminalReadError || '');
      const missingLog = /ENOENT|no such file/i.test(readErrText);
      const hasReadError = readErrText.length > 0 && !missingLog;
      const status = hasReadError ? 'fail' : (hasRuntimeData ? 'ok' : 'unknown');
      return {
        profile: p.profile,
        profileLabel: p.profileLabel || p.profile,
        compile: {
          status,
          errors: hasReadError ? 1 : 0,
          warnings: 0,
          target: hasRuntimeData ? 'active-profile' : '-',
        },
        runtime_critical_hits: Number(p?.metrics?.day?.unmatchedDeals || 0),
      };
    });
    const compileBadProfiles = profilesSummary.filter((p) => p.compile.status === 'fail').length;
    const compileUnknownProfiles = profilesSummary.filter((p) => p.compile.status === 'unknown').length;

    const summary = {
      verdict: telemetry ? 'LIVE' : 'WATCH',
      branch: 'vds',
      bot: 'auto',
      compile_bad_profiles: compileBadProfiles,
      compile_unknown_profiles: compileUnknownProfiles,
      runtime_critical_hits: telemetryRuntimeHits,
      profiles: profilesSummary,
    };

    const vps = {
      terminal64_count: Number(p1r.stdout||0),
      metaeditor64_count: Number(p2r.stdout||0),
      latest_reports: latestReports,
      live_window_log_tail: liveLogr.stdout ? liveLogr.stdout.split(/\r?\n/) : [],
      telemetry_file: TELEMETRY_PATH
    };

    const fixTracker = {
      targetIssue: 'SELL BE/TP reliability',
      profilesTotal: profilesSummary.length,
      compileOk: profilesSummary.filter((p) => p.compile.status === 'ok').length,
      compileFail: compileBadProfiles,
      compileUnknown: compileUnknownProfiles,
      runtimeCriticalHits: telemetryRuntimeHits,
    };

    return j(res,200,{
      generatedAt: new Date().toISOString(),
      summary,
      vps,
      runContext: 'VDS live feed',
      discordHealth,
      discordMetrics: fast ? null : discordMetrics,
      fixTracker,
      telemetry,
      copierFeed,
      liveFeed: Array.isArray(telemetry?.liveFeed) ? telemetry.liveFeed.slice(0, 180) : [],
    });
  }

  if (url.pathname === '/api/telemetry') {
    const telemetryRaw = readJsonFile(TELEMETRY_PATH);
    const liveProbe = readLiveProbeMap(LIVE_PROBE_PATH);
    const telemetry = sanitizeVdsTelemetry(applyLiveProbeOverlay(telemetryRaw, liveProbe));
    if (!telemetry) return j(res, 404, { ok: false, error: `No telemetry file at ${TELEMETRY_PATH}` });
    const accountMap = readAccountsCsv(ACCOUNTS_CSV_PATH);
    enrichTelemetryProfiles(telemetry, accountMap);
    applyIssueAuditOverlay(telemetry, readIssueAuditMap(ISSUE_AUDIT_PATH));
    const copierFeed = buildCopierFeed(telemetry, readCsvRows(COPIER_ACCOUNTS_CSV_PATH), liveProbe);
    return j(res, 200, { ok: true, telemetry, copierFeed });
  }

  if (url.pathname === '/api/feed') {
    const telemetry = readJsonFile(TELEMETRY_PATH);
    const limit = Math.max(10, Math.min(500, Number(url.searchParams.get('limit') || 150)));
    const feed = Array.isArray(telemetry?.liveFeed) ? telemetry.liveFeed.slice(0, limit) : [];
    return j(res, 200, { ok: true, generatedAt: telemetry?.generatedAt || null, count: feed.length, feed });
  }

  if (url.pathname === '/api/charts/live') {
    const rawSymbols = String(url.searchParams.get('symbols') || 'XAUUSD,XAGUSD');
    const limit = Math.max(30, Math.min(320, Number(url.searchParams.get('limit') || 160)));
    const symbols = [...new Set(
      rawSymbols
        .split(',')
        .map((s) => String(s || '').trim().toUpperCase())
        .filter((s) => LIVE_CHART_SOURCES[s])
    )];
    const wanted = symbols.length ? symbols : ['XAUUSD', 'XAGUSD'];
    const out = [];
    for (const sym of wanted) {
      const row = await ensureLiveChart(sym);
      const dense = densifyCandles(row.candles, limit);
      out.push({
        symbol: row.symbol,
        updatedAt: row.updatedAt,
        lastPrice: row.lastPrice,
        count: Array.isArray(dense) ? dense.length : 0,
        candles: Array.isArray(dense) ? dense : [],
      });
    }
    return j(res, 200, { ok: true, generatedAt: new Date().toISOString(), source: 'swissquote+mt5-log-backfill+dense', charts: out });
  }

  if (url.pathname === '/api/snapshots/terminal') {
    const idxPeek = readJsonFile(SNAPSHOT_INDEX_PATH) || {};
    const idxTs = Date.parse(idxPeek?.generatedAt || '');
    const stale = !Number.isFinite(idxTs) || (Date.now() - idxTs) > SNAPSHOT_STALE_MS;
    if (SNAPSHOT_TRIGGER_ON_REQUEST && stale) {
      // Keep API fast; refresh runs in the background.
      void maybeTriggerSnapshotRefresh();
    }
    const rawAccounts = String(url.searchParams.get('accounts') || '');
    const requested = new Set(
      rawAccounts
        .split(',')
        .map((s) => String(s || '').replace(/\D/g, ''))
        .filter((s) => s.length >= 6)
    );
    const idx = idxPeek;
    const items = Array.isArray(idx?.items) ? idx.items : [];
    const rows = items
      .filter((r) => {
        const acct = String(r?.account || '').replace(/\D/g, '');
        if (!acct) return false;
        return requested.size ? requested.has(acct) : true;
      })
      .map((r) => {
        const file = sanitizeSnapshotFile(r?.file || '');
        if (!file) return null;
        const acct = String(r?.account || '').replace(/\D/g, '');
        const updatedAt = r?.updatedAt || null;
        const stamp = Number.isFinite(Date.parse(updatedAt || '')) ? Date.parse(updatedAt) : Date.now();
        return {
          account: acct,
          title: r?.title || null,
          updatedAt,
          size: Number(r?.size || 0),
          url: `/snapshots/${file}?t=${stamp}`,
        };
      })
      .filter(Boolean);
    return j(res, 200, {
      ok: true,
      generatedAt: new Date().toISOString(),
      source: 'mt5-terminal-window-capture',
      count: rows.length,
      snapshots: rows,
    });
  }

  if (req.method === 'POST' && url.pathname.startsWith('/api/control/')) {
    const action = url.pathname.split('/').pop();
    const result = await runControlAction(action, 'api');
    const code = result.ok || result.action === 'help' ? 200 : 400;
    return j(res, code, result);
  }

  j(res,404,{error:'not found'});
});

if (TELEGRAM_CONTROL_ENABLED && TELEGRAM_CONTROL_BOT_TOKEN) {
  setInterval(() => {
    void pollTelegramControl();
  }, TELEGRAM_CONTROL_POLL_MS);
  setTimeout(() => {
    void pollTelegramControl();
  }, 1500);
}

server.listen(PORT, '0.0.0.0', ()=> console.log(`Ops Motherboard VDS on :${PORT}`));
