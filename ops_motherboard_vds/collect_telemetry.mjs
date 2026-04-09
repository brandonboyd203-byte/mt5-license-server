#!/usr/bin/env node
import fs from 'fs';
import fsp from 'fs/promises';
import path from 'path';
import readline from 'readline';

const MT5_ROOT = process.env.MT5_ROOT || 'C:\\MT5';
const REPORTS_ROOT = process.env.REPORTS_ROOT || 'C:\\GoldmineOps\\reports';
const ACCOUNTS_CSV = process.env.ACCOUNTS_CSV || 'C:\\GoldmineOps\\secure\\vds_accounts.csv';
const TELEMETRY_FILE = path.join(REPORTS_ROOT, 'mt5_telemetry.json');
const STATE_FILE = path.join(REPORTS_ROOT, 'mt5_telemetry_state.json');
const RUNTIME_INTEGRITY_FILE = path.join(REPORTS_ROOT, 'mt5_runtime_integrity.json');
const LIVE_PROBE_FILE = path.join(REPORTS_ROOT, 'mt5_live_probe.json');
const EMERGENCY_OVERRIDE_FILE = path.join(REPORTS_ROOT, 'vds_emergency_restore_from_screenshot.json');
const MAX_BACKFILL_BYTES = Number(process.env.TELEMETRY_MAX_BACKFILL_BYTES || 35 * 1024 * 1024);
const RECENT_EVENTS_MAX = 120;
const RECENT_HASHES_MAX = 400;
const DEFAULT_START_EQUITY = Number(process.env.DEFAULT_START_EQUITY || 5000);
const FORCE_DAY_BASELINE_RAW = process.env.FORCE_DAY_BASELINE;
const FORCE_DAY_BASELINE = (() => {
  if (FORCE_DAY_BASELINE_RAW == null || String(FORCE_DAY_BASELINE_RAW).trim() === '') return null;
  const n = Number(FORCE_DAY_BASELINE_RAW);
  return Number.isFinite(n) && n > 0 ? n : null;
})();
const PERTH_TIMEZONE = 'Australia/Perth';
const DAY_RESET_HOUR = Math.max(
  0,
  Math.min(
    23,
    Number(
      process.env.TELEMETRY_DAY_RESET_HOUR_PERTH
      ?? process.env.TELEMETRY_DAY_RESET_HOUR
      ?? 7,
    ),
  ),
);
const WEEK_DAYS = Math.max(2, Math.min(14, Number(process.env.TELEMETRY_WEEK_DAYS || 7)));
const MONTH_DAYS = Math.max(7, Math.min(60, Number(process.env.TELEMETRY_MONTH_DAYS || 30)));
const ALLOW_PREVIOUS_DAY_LOG_FALLBACK = String(process.env.ALLOW_PREVIOUS_DAY_LOG_FALLBACK || '').trim().toLowerCase() === '1';
const NEXUS_HEALTH_TAIL_BYTES = Number(process.env.NEXUS_HEALTH_TAIL_BYTES || 25 * 1024 * 1024);
const ENABLE_EMERGENCY_OVERRIDES = String(process.env.ENABLE_EMERGENCY_OVERRIDES || '0').trim() === '1';
const HIDDEN_PROFILES = new Set(['Lab']); // retired profile(s) not shown on motherboard
const PROFILE_RISK_HINTS = {
  Blueprint20_leverage500: 20,
  Blueprint20_leverage1000: 20,
  Blueprint20_leverage2000: 20,
};
const PROFILE_LEVERAGE_HINTS = {
  Blueprint20_leverage500: '1:500',
  Blueprint20_leverage1000: '1:1000',
  Blueprint20_leverage2000: '1:2000',
};
const LIVE_PRICE_FEEDS = {
  XAUUSD: 'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD',
  XAGUSD: 'https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAG/USD',
};

const CONTRACT_MULTIPLIER = { XAUUSD: 100, XAGUSD: 5000 };

const accountRe = /'(\d{6,})':/;
const tsRe = /(\d{2}:\d{2}:\d{2}\.\d{3})/;
const syncRe = /terminal synchronized .*: (\d+) positions, (\d+) orders,/i;
const closeReqRe = /(\d{2}:\d{2}:\d{2}\.\d{3}).*market (buy|sell) ([0-9.]+) ([A-Z0-9]+), close #(\d+) (buy|sell) ([0-9.]+) ([A-Z0-9]+) ([0-9.]+)/i;
const dealRe = /(\d{2}:\d{2}:\d{2}\.\d{3}).*deal #\d+ (buy|sell) ([0-9.]+) ([A-Z0-9]+) at ([0-9.]+) done \(based on order #(\d+)\)/i;
const startEqRe = /StartEquity\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)/i;
const riskRe = /Risk per trade:\s*([0-9]+(?:\.[0-9]+)?)%/i;
const activeCfgRiskRe = /ACTIVE_CONFIG .*?EffectiveRiskPerTrade=([0-9]+(?:\.[0-9]+)?)/i;
const equityRe = /\bEquity:\s*([0-9]+(?:\.[0-9]+)?)/i;
const snapshotRe = /ACCOUNT_SNAPSHOT\s+Balance=([0-9.-]+)\s+Equity=([0-9.-]+)\s+Profit=([0-9.-]+)\s+FreeMargin=([0-9.-]+)\s+Account=([0-9]+)/i;
const runningPosRe = /RUNNING\s*\|\s*BUY=(\d+)\s+SELL=(\d+)/i;
const autoCorrectTicketRe = /TYPE AUTO-CORRECT:\s*#(\d+)/i;
const positionTicketRe = /Position\s+#(\d+)/i;
const positionDetailRe = /Position\s+#(\d+)\s+\|\s+Type=(BUY|SELL)\s+\|\s+Open=([0-9.]+)\s+\|\s+Current=([0-9.]+)\s+\|\s+Profit=([0-9.+-]+)\s+pips/i;
const leverageLineRe = /(?:Account\s+Leverage|Leverage)\s*[:=]\s*([A-Z0-9:]+)/i;
const leverageLooseRe = /\bleverage\b[^0-9A-Z]*(UNLIMITED:1|\d+:\d+|\d+)/i;

function nowIso() {
  return new Date().toISOString();
}

function formatYyyymmdd(d = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: PERTH_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(d);
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]));
  return `${byType.year}${byType.month}${byType.day}`;
}

function applyDayResetHour(d = new Date(), resetHour = DAY_RESET_HOUR) {
  return new Date(d.getTime() - (resetHour * 60 * 60 * 1000));
}

function yyyymmdd(d = new Date()) {
  return formatYyyymmdd(applyDayResetHour(d));
}

function normalizeLeverageValue(raw) {
  if (!raw) return null;
  const s = String(raw).trim().toUpperCase();
  if (!s) return null;
  if (s.includes('UNLIMITED')) return 'UNLIMITED';
  const ratio = s.match(/(\d+)\s*:\s*(\d+)/);
  if (ratio) {
    const a = Number(ratio[1]);
    const b = Number(ratio[2]);
    if (a === 1 && b > 0) return `1:${b}`;
    if (b === 1 && a > 0) return `1:${a}`;
    return `${a}:${b}`;
  }
  const n = Number(s);
  if (Number.isFinite(n) && n > 0) return `1:${Math.round(n)}`;
  return null;
}

function estimateLeverageFromEquity(equityRaw) {
  const eq = Number(equityRaw);
  if (!Number.isFinite(eq) || eq <= 0) return null;
  if (eq < 5000) return 'UNLIMITED';
  if (eq <= 30000) return '1:2000';
  if (eq <= 100000) return '1:1000';
  return '1:500';
}

function daysBackList(n, from = new Date()) {
  const base = applyDayResetHour(from);
  const out = [];
  for (let i = 0; i < n; i++) {
    const d = new Date(base);
    d.setDate(d.getDate() - i);
    out.push(formatYyyymmdd(d));
  }
  return out;
}

async function resolveLogFile(profile, relParts, requestedDay) {
  const dir = path.join(MT5_ROOT, profile, ...relParts);
  const requestedPath = path.join(dir, `${requestedDay}.log`);

  try {
    await fsp.stat(requestedPath);
    return { path: requestedPath, day: requestedDay, fallback: false };
  } catch {
    // Optionally fall back to latest available day-log when terminal keeps writing into previous-day file.
    if (!ALLOW_PREVIOUS_DAY_LOG_FALLBACK) {
      return { path: requestedPath, day: requestedDay, fallback: false };
    }
  }

  try {
    const entries = await fsp.readdir(dir, { withFileTypes: true });
    const dayLogs = entries
      .filter((e) => e.isFile() && /^\d{8}\.log$/.test(e.name))
      .map((e) => e.name)
      .sort((a, b) => b.localeCompare(a));

    if (!dayLogs.length) return { path: requestedPath, day: requestedDay, fallback: false };

    const chosen = dayLogs.find((name) => name.slice(0, 8) <= requestedDay) || dayLogs[0];
    const chosenDay = chosen.slice(0, 8);
    return {
      path: path.join(dir, chosen),
      day: chosenDay,
      fallback: chosenDay !== requestedDay,
    };
  } catch {
    return { path: requestedPath, day: requestedDay, fallback: false };
  }
}

function safeJsonParse(txt, fallback) {
  try {
    const normalized = (typeof txt === 'string') ? txt.replace(/^\uFEFF/, '') : txt;
    return JSON.parse(normalized);
  } catch {
    return fallback;
  }
}

async function readAccountsCsvMap(filePath = ACCOUNTS_CSV) {
  try {
    const raw = await fsp.readFile(filePath, 'utf8');
    const lines = raw.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    if (lines.length < 2) return {};
    const cleanCsvCell = (value) => String(value || '').trim().replace(/^"|"$/g, '');
    const headers = lines[0].split(',').map((h) => cleanCsvCell(h).toLowerCase());
    const idx = (name) => headers.indexOf(name);
    const pIdx = idx('profile');
    if (pIdx < 0) return {};
    const out = {};
    for (let i = 1; i < lines.length; i += 1) {
      const cols = lines[i].split(',').map((c) => cleanCsvCell(c));
      const profile = cols[pIdx];
      if (!profile) continue;
      out[profile] = {
        profile,
        account: idx('account') >= 0 ? (cols[idx('account')] || null) : null,
        bot: idx('bot') >= 0 ? (cols[idx('bot')] || null) : null,
        symbols: idx('symbols') >= 0 ? (cols[idx('symbols')] || null) : null,
      };
    }
    return out;
  } catch {
    return {};
  }
}

async function readActiveProfiles(filePath = ACCOUNTS_CSV) {
  const map = await readAccountsCsvMap(filePath);
  return Object.keys(map)
    .filter((profile) => profile && !HIDDEN_PROFILES.has(profile))
    .sort((a, b) => a.localeCompare(b));
}

async function readJsonFile(filePath, fallback) {
  try {
    const raw = await fsp.readFile(filePath, 'utf8');
    return safeJsonParse(raw, fallback);
  } catch {
    return fallback;
  }
}

async function readLiveProbeMap(filePath = LIVE_PROBE_FILE) {
  const raw = await readJsonFile(filePath, null);
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
  return { byProfile, byAccount };
}

async function readEmergencyAccountOverrides(filePath = EMERGENCY_OVERRIDE_FILE) {
  const raw = await readJsonFile(filePath, null);
  const byAccount = raw && typeof raw.byAccount === 'object' ? raw.byAccount : {};
  const out = {};
  for (const [k, row] of Object.entries(byAccount)) {
    const account = String(k || '').trim();
    if (!account) continue;
    if (!row || typeof row !== 'object') continue;
    out[account] = row;
  }
  return out;
}

async function writeJsonFile(filePath, value) {
  await fsp.mkdir(path.dirname(filePath), { recursive: true });
  const tmp = `${filePath}.tmp`;
  await fsp.writeFile(tmp, JSON.stringify(value, null, 2), 'utf8');
  await fsp.rename(tmp, filePath);
}

function emptyMetrics() {
  return {
    closeRequests: 0,
    matchedCloses: 0,
    wins: 0,
    losses: 0,
    breakeven: 0,
    grossProfitUsd: 0,
    grossLossUsd: 0,
    netUsd: 0,
    closedVolume: 0,
    unmatchedDeals: 0,
    buyCloses: 0,
    sellCloses: 0,
    buyClosedVolume: 0,
    sellClosedVolume: 0,
  };
}

function makeDailyState(day) {
  return {
    day,
    firstSeenDay: day,
    firstSeenAccount: null,
    account: null,
    startEquity: null,
    dayOpeningEquity: null,
    dayOpeningBalance: null,
    dayOpeningAt: null,
    dayOpeningLocked: false,
    riskPct: null,
    leverage: null,
    leverageSource: null,
    leverageAt: null,
    equityHint: null,
    balanceSnapshot: null,
    equitySnapshot: null,
    profitSnapshot: null,
    freeMarginSnapshot: null,
    snapshotAt: null,
    mqlPath: null,
    mqlLogDay: null,
    mqlReadError: null,
    lastSyncAt: null,
    openPositions: 0,
    runningOpenPositions: null,
    runningSeenAt: null,
    openOrders: 0,
    terminalOffset: 0,
    terminalEncoding: null,
    terminalPath: null,
    terminalLogDay: null,
    terminalPartialBackfill: false,
    terminalReadError: null,
    positions: {},
    pendingCloseRequests: [],
    recentEvents: [],
    recentEventHashes: [],
    metrics: emptyMetrics(),
    lastActivityAt: null,
  };
}

function ensureProfileState(stateObj, day) {
  if (!stateObj || stateObj.day !== day) return makeDailyState(day);

  stateObj.firstSeenDay ??= day;
  stateObj.firstSeenAccount ??= null;
  stateObj.recentEvents ??= [];
  stateObj.recentEventHashes ??= [];
  stateObj.positions ??= {};
  stateObj.pendingCloseRequests ??= [];
  stateObj.metrics ??= emptyMetrics();
  stateObj.metrics.closeRequests ??= 0;
  stateObj.metrics.matchedCloses ??= 0;
  stateObj.metrics.wins ??= 0;
  stateObj.metrics.losses ??= 0;
  stateObj.metrics.breakeven ??= 0;
  stateObj.metrics.grossProfitUsd ??= 0;
  stateObj.metrics.grossLossUsd ??= 0;
  stateObj.metrics.netUsd ??= 0;
  stateObj.metrics.closedVolume ??= 0;
  stateObj.metrics.unmatchedDeals ??= 0;
  stateObj.metrics.buyCloses ??= 0;
  stateObj.metrics.sellCloses ??= 0;
  stateObj.metrics.buyClosedVolume ??= 0;
  stateObj.metrics.sellClosedVolume ??= 0;
  stateObj.dayOpeningEquity ??= null;
  stateObj.dayOpeningBalance ??= null;
  stateObj.dayOpeningAt ??= null;
  stateObj.dayOpeningLocked ??= false;
  stateObj.leverage ??= null;
  stateObj.leverageSource ??= null;
  stateObj.leverageAt ??= null;
  stateObj.balanceSnapshot ??= null;
  stateObj.equitySnapshot ??= null;
  stateObj.profitSnapshot ??= null;
  stateObj.freeMarginSnapshot ??= null;
  stateObj.snapshotAt ??= null;
  stateObj.mqlPath ??= null;
  stateObj.mqlLogDay ??= null;
  stateObj.mqlReadError ??= null;
  stateObj.runningOpenPositions ??= null;
  stateObj.runningSeenAt ??= null;
  stateObj.terminalLogDay ??= null;
  return stateObj;
}

function cloneMetrics(src) {
  return {
    closeRequests: Number(src.closeRequests || 0),
    matchedCloses: Number(src.matchedCloses || 0),
    wins: Number(src.wins || 0),
    losses: Number(src.losses || 0),
    breakeven: Number(src.breakeven || 0),
    grossProfitUsd: Number(src.grossProfitUsd || 0),
    grossLossUsd: Number(src.grossLossUsd || 0),
    netUsd: Number(src.netUsd || 0),
    closedVolume: Number(src.closedVolume || 0),
    unmatchedDeals: Number(src.unmatchedDeals || 0),
    buyCloses: Number(src.buyCloses || 0),
    sellCloses: Number(src.sellCloses || 0),
    buyClosedVolume: Number(src.buyClosedVolume || 0),
    sellClosedVolume: Number(src.sellClosedVolume || 0),
  };
}

function addMetrics(dst, src) {
  dst.closeRequests += Number(src.closeRequests || 0);
  dst.matchedCloses += Number(src.matchedCloses || 0);
  dst.wins += Number(src.wins || 0);
  dst.losses += Number(src.losses || 0);
  dst.breakeven += Number(src.breakeven || 0);
  dst.grossProfitUsd += Number(src.grossProfitUsd || 0);
  dst.grossLossUsd += Number(src.grossLossUsd || 0);
  dst.netUsd += Number(src.netUsd || 0);
  dst.closedVolume += Number(src.closedVolume || 0);
  dst.unmatchedDeals += Number(src.unmatchedDeals || 0);
  dst.buyCloses += Number(src.buyCloses || 0);
  dst.sellCloses += Number(src.sellCloses || 0);
  dst.buyClosedVolume += Number(src.buyClosedVolume || 0);
  dst.sellClosedVolume += Number(src.sellClosedVolume || 0);
}

function hhmmssToSec(ts) {
  const m = ts.match(/(\d{2}):(\d{2}):(\d{2})\.(\d{3})/);
  if (!m) return null;
  return Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000;
}

function eventEpoch(day, ts) {
  const m = ts.match(/(\d{2}):(\d{2}):(\d{2})\.(\d{3})/);
  if (!m) return Date.now();
  const yyyy = day.slice(0, 4);
  const mm = day.slice(4, 6);
  const dd = day.slice(6, 8);
  const d = new Date(`${yyyy}-${mm}-${dd}T${m[1]}:${m[2]}:${m[3]}.${m[4]}`);
  return Number.isNaN(d.getTime()) ? Date.now() : d.getTime();
}

function shortLine(line, max = 220) {
  const compact = line.replace(/\s+/g, ' ').trim();
  return compact.length > max ? `${compact.slice(0, max - 3)}...` : compact;
}

function hashLite(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h += (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24);
  }
  return (h >>> 0).toString(16);
}

function detectStrategyHint(events) {
  const counts = new Map();
  const re = /Goldmine([A-Za-z0-9]+?)(?:_(?:Gold|Silver))?_VPS/g;
  for (const ev of (events || [])) {
    const txt = String(ev?.text || '');
    let m;
    while ((m = re.exec(txt)) !== null) {
      const raw = String(m[1] || '').trim();
      if (!raw) continue;
      const key = raw;
      counts.set(key, (counts.get(key) || 0) + 1);
    }
  }
  let best = null;
  let bestCount = 0;
  for (const [k, c] of counts.entries()) {
    if (c > bestCount) {
      best = k;
      bestCount = c;
    }
  }
  return best;
}

function deriveProfileLabel(profile, strategyHint) {
  if (profile === 'Lab2') return 'Blueprint Original';
  if (profile === 'Lab') return 'Blueprint_20_Risk_LeverageTest';
  return profile;
}

function pickDisplayLabel(profile, accountMeta, probeRow, fallbackLabel) {
  const fallback = String(fallbackLabel || profile || '').trim() || String(profile || '').trim() || 'Unknown';
  const isCopier = String(accountMeta?.bot || '').trim().toLowerCase() === 'copier';
  if (!isCopier) return fallback;

  const liveName = String(probeRow?.accountName || '').trim();
  if (liveName) return liveName;

  const csvLabel = String(accountMeta?.label || '').trim();
  if (csvLabel) return csvLabel;

  return fallback;
}

function pushEvent(state, day, profile, source, kind, line, ts) {
  const epoch = ts ? eventEpoch(day, ts) : Date.now();
  const text = shortLine(line);
  const id = hashLite(`${profile}|${source}|${kind}|${text}|${ts || ''}`);
  if (state.recentEventHashes.includes(id)) return;

  state.recentEventHashes.push(id);
  if (state.recentEventHashes.length > RECENT_HASHES_MAX) {
    state.recentEventHashes = state.recentEventHashes.slice(-RECENT_HASHES_MAX);
  }

  state.recentEvents.push({ id, t: epoch, ts: ts || null, profile, source, kind, text });
  if (state.recentEvents.length > RECENT_EVENTS_MAX) {
    state.recentEvents = state.recentEvents.slice(-RECENT_EVENTS_MAX);
  }
  state.lastActivityAt = new Date(epoch).toISOString();
}

function maybePushEvent(state, day, profile, source, kind, line, ts, collectEvents) {
  if (!collectEvents) return;
  pushEvent(state, day, profile, source, kind, line, ts);
}

function maybeCaptureLeverage(state, line, day, ts, source) {
  if (!line) return;
  const m = line.match(leverageLineRe) || line.match(leverageLooseRe);
  if (!m) return;
  const normalized = normalizeLeverageValue(m[1]);
  if (!normalized) return;
  state.leverage = normalized;
  state.leverageSource = source;
  state.leverageAt = ts ? new Date(eventEpoch(day, ts)).toISOString() : nowIso();
}

function positionClosePnl(position, closePrice, closeVolume) {
  const mult = CONTRACT_MULTIPLIER[position.symbol] ?? 1;
  return position.side === 'buy'
    ? (closePrice - position.entry) * closeVolume * mult
    : (position.entry - closePrice) * closeVolume * mult;
}

function activePositions(state, maxAgeMs = 20 * 60 * 1000) {
  const nowMs = Date.now();
  return Object.values(state?.positions || {}).filter((p) => {
    const seenMs = Date.parse(p?.seenAt || '');
    return Number.isFinite(seenMs) && ((nowMs - seenMs) <= maxAgeMs);
  });
}

function activePositionEntries(state, maxAgeMs = 20 * 60 * 1000) {
  const nowMs = Date.now();
  return Object.entries(state?.positions || {}).filter(([, p]) => {
    const seenMs = Date.parse(p?.seenAt || '');
    return Number.isFinite(seenMs) && ((nowMs - seenMs) <= maxAgeMs);
  });
}

function extractLiveMidPrice(payload) {
  const data = String(payload || '').trim();
  if (!data) return null;
  const lines = data.split('\n').map((line) => line.trim()).filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i -= 1) {
    const row = lines[i];
    if (!row.startsWith('[') || !row.endsWith(']')) continue;
    try {
      const parsed = JSON.parse(row);
      const bid = Number(parsed?.spreadProfilePrices?.[0]?.bid);
      const ask = Number(parsed?.spreadProfilePrices?.[0]?.ask);
      if (Number.isFinite(bid) && Number.isFinite(ask) && bid > 0 && ask > 0) {
        return Number((((bid + ask) / 2)).toFixed(3));
      }
    } catch {
      // Ignore malformed JSON lines.
    }
  }
  return null;
}

async function fetchLivePriceMap(symbols = ['XAUUSD', 'XAGUSD']) {
  const unique = [...new Set((symbols || []).map((s) => String(s || '').toUpperCase()).filter(Boolean))];
  const out = {};
  for (const symbol of unique) {
    const url = LIVE_PRICE_FEEDS[symbol];
    if (!url) continue;
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 3500);
      const res = await fetch(url, {
        headers: {
          Accept: 'application/json,text/plain,*/*',
          'User-Agent': 'goldmine-ops-telemetry/1.0',
        },
        signal: ctrl.signal,
      });
      clearTimeout(timer);
      if (!res.ok) continue;
      const text = await res.text();
      const price = extractLiveMidPrice(text);
      if (Number.isFinite(price) && price > 0) out[symbol] = price;
    } catch {
      // Keep best-effort behavior.
    }
  }
  return out;
}

function estimateOpenProfitFromPositions(state, livePriceMap = {}) {
  const positions = activePositions(state);
  if (!positions.length) return null;
  let sum = 0;
  let seen = 0;
  for (const p of positions) {
    const symbol = String(p?.symbol || '').toUpperCase();
    const side = String(p?.side || '').toLowerCase();
    const entry = Number(p?.entry);
    const volume = Number(p?.volume);
    const price = Number(livePriceMap?.[symbol]);
    if (!Number.isFinite(entry) || !Number.isFinite(volume) || volume <= 0 || !Number.isFinite(price) || price <= 0) continue;
    if (side !== 'buy' && side !== 'sell') continue;
    sum += positionClosePnl({ symbol, side, entry }, price, volume);
    seen += 1;
  }
  if (seen <= 0) return null;
  return round2(sum);
}

function applyClose(state, ticket, symbol, closeVolume, closePrice) {
  const pos = state.positions[ticket];
  if (!pos || pos.symbol !== symbol) return null;

  const usedVolume = Math.min(closeVolume, pos.volume);
  if (!(usedVolume > 0)) return null;

  const pnl = positionClosePnl(pos, closePrice, usedVolume);
  const m = state.metrics;

  m.matchedCloses += 1;
  m.closedVolume += usedVolume;
  m.netUsd += pnl;
  if (pos.side === 'buy') {
    m.buyCloses += 1;
    m.buyClosedVolume += usedVolume;
  } else if (pos.side === 'sell') {
    m.sellCloses += 1;
    m.sellClosedVolume += usedVolume;
  }

  if (pnl > 0.000001) {
    m.wins += 1;
    m.grossProfitUsd += pnl;
  } else if (pnl < -0.000001) {
    m.losses += 1;
    m.grossLossUsd += Math.abs(pnl);
  } else {
    m.breakeven += 1;
  }

  pos.volume -= usedVolume;
  if (pos.volume <= 0.0000001) delete state.positions[ticket];
  else state.positions[ticket] = pos;

  return pnl;
}

function matchCloseRequest(state, deal) {
  let bestIdx = -1;
  let bestDt = Number.POSITIVE_INFINITY;

  for (let i = 0; i < state.pendingCloseRequests.length; i++) {
    const req = state.pendingCloseRequests[i];
    if (req.symbol !== deal.symbol || req.marketSide !== deal.side) continue;
    if (Math.abs(req.closeVolume - deal.volume) > 0.011) continue;

    const dt = deal.tsSec - req.tsSec;
    if (dt < 0 || dt > 12) continue;
    if (dt < bestDt) {
      bestDt = dt;
      bestIdx = i;
    }
  }

  if (bestIdx === -1) return null;
  return state.pendingCloseRequests.splice(bestIdx, 1)[0];
}

function parseTerminalLine(line, state, profile, day, opts = {}) {
  const collectEvents = opts.collectEvents !== false;
  const collectMetrics = opts.collectMetrics !== false;
  const tsMatch = line.match(tsRe);
  const ts = tsMatch ? tsMatch[1] : null;

  const accountMatch = line.match(accountRe);
  if (accountMatch) state.account = accountMatch[1];
  maybeCaptureLeverage(state, line, day, ts, 'terminal');

  const syncMatch = line.match(syncRe);
  if (syncMatch) {
    state.openPositions = Number(syncMatch[1]);
    state.openOrders = Number(syncMatch[2]);
    state.lastSyncAt = ts ? new Date(eventEpoch(day, ts)).toISOString() : nowIso();
    // Hard reset stale ticket cache when terminal reports no live exposure.
    if (state.openPositions <= 0) {
      state.positions = {};
      state.pendingCloseRequests = [];
    }
    maybePushEvent(state, day, profile, 'terminal', 'sync', line, ts, collectEvents);
    return;
  }

  const closeReqMatch = line.match(closeReqRe);
  if (closeReqMatch) {
    if (!collectMetrics) return;
    state.metrics.closeRequests += 1;
    const req = {
      ts: closeReqMatch[1],
      tsSec: hhmmssToSec(closeReqMatch[1]) ?? -1,
      marketSide: closeReqMatch[2].toLowerCase(),
      closeVolume: Number(closeReqMatch[3]),
      symbol: closeReqMatch[4],
      ticket: closeReqMatch[5],
      positionSide: closeReqMatch[6].toLowerCase(),
      positionEntry: Number(closeReqMatch[9]),
    };
    state.pendingCloseRequests.push(req);

    if (!state.positions[req.ticket]) {
      state.positions[req.ticket] = {
        symbol: req.symbol,
        side: req.positionSide,
        entry: req.positionEntry,
        volume: req.closeVolume,
        seenAt: ts ? new Date(eventEpoch(day, ts)).toISOString() : nowIso(),
      };
    }

    maybePushEvent(state, day, profile, 'terminal', 'close-request', line, req.ts, collectEvents);
    return;
  }

  const dealMatch = line.match(dealRe);
  if (dealMatch) {
    if (!collectMetrics) return;
    const deal = {
      ts: dealMatch[1],
      tsSec: hhmmssToSec(dealMatch[1]) ?? -1,
      side: dealMatch[2].toLowerCase(),
      volume: Number(dealMatch[3]),
      symbol: dealMatch[4],
      price: Number(dealMatch[5]),
      basedOrder: dealMatch[6],
    };

    const req = matchCloseRequest(state, deal);
    if (req) {
      if (!state.positions[req.ticket]) {
        state.positions[req.ticket] = {
          symbol: req.symbol,
          side: req.positionSide,
          entry: req.positionEntry,
          volume: req.closeVolume,
        };
      }
      applyClose(state, req.ticket, req.symbol, deal.volume, deal.price);
      maybePushEvent(state, day, profile, 'terminal', 'deal-close', line, deal.ts, collectEvents);
      return;
    }

    if (deal.basedOrder === '0') {
      state.metrics.unmatchedDeals += 1;
      maybePushEvent(state, day, profile, 'terminal', 'deal-order0', line, deal.ts, collectEvents);
      return;
    }

    const pos = state.positions[deal.basedOrder];
    if (!pos) {
      state.positions[deal.basedOrder] = {
        symbol: deal.symbol,
        side: deal.side,
        entry: deal.price,
        volume: deal.volume,
        seenAt: deal.ts ? new Date(eventEpoch(day, deal.ts)).toISOString() : nowIso(),
      };
    } else if (pos.symbol === deal.symbol && pos.side === deal.side) {
      const nextVol = pos.volume + deal.volume;
      pos.entry = ((pos.entry * pos.volume) + (deal.price * deal.volume)) / nextVol;
      pos.volume = nextVol;
      pos.seenAt = deal.ts ? new Date(eventEpoch(day, deal.ts)).toISOString() : nowIso();
      state.positions[deal.basedOrder] = pos;
    } else {
      state.metrics.unmatchedDeals += 1;
    }

    maybePushEvent(state, day, profile, 'terminal', 'deal-open', line, deal.ts, collectEvents);
    return;
  }

  if (/failed|stopped with|shutdown with/i.test(line)) {
    maybePushEvent(state, day, profile, 'terminal', 'error', line, ts, collectEvents);
  }
}

async function detectFileEncoding(filePath) {
  try {
    const chunks = [];
    const stream = fs.createReadStream(filePath, { start: 0, end: 4095 });
    for await (const chunk of stream) chunks.push(chunk);
    const probe = chunks.length ? Buffer.concat(chunks) : Buffer.alloc(0);
    if (probe.length >= 2 && probe[0] === 0xff && probe[1] === 0xfe) return 'utf16le';
    if (probe.length >= 2 && probe[0] === 0xfe && probe[1] === 0xff) return 'utf16le';
    if (probe.length >= 3 && probe[0] === 0xef && probe[1] === 0xbb && probe[2] === 0xbf) return 'utf8';

    const sample = Math.min(probe.length, 2048);
    let zeroes = 0;
    for (let i = 0; i < sample; i += 1) if (probe[i] === 0) zeroes += 1;
    if (sample > 0 && (zeroes / sample) > 0.2) return 'utf16le';
    return 'utf8';
  } catch {
    return 'utf8';
  }
}

async function processTerminalIncremental(profile, state, day) {
  const resolved = await resolveLogFile(profile, ['Logs'], day);
  const terminalPath = resolved.path;
  const activeDay = resolved.day;
  const staleFallback = resolved.fallback && activeDay !== day;
  const prevTerminalPath = state.terminalPath;
  state.terminalPath = terminalPath;
  state.terminalLogDay = activeDay;
  if (prevTerminalPath && prevTerminalPath !== terminalPath) {
    state.terminalOffset = 0;
    state.terminalEncoding = null;
    state.terminalPartialBackfill = false;
  }

  try {
    const st = await fsp.stat(terminalPath);
    let start = Number(state.terminalOffset || 0);

    if (!Number.isFinite(start) || start < 0) start = 0;
    if (st.size < start) start = 0;

    if (start === 0 && st.size > MAX_BACKFILL_BYTES) {
      start = st.size - MAX_BACKFILL_BYTES;
      state.terminalPartialBackfill = true;
    }

    const encoding = state.terminalEncoding || await detectFileEncoding(terminalPath);
    state.terminalEncoding = encoding;
    if (encoding === 'utf16le' && start % 2 === 1) start -= 1;

    if (start >= st.size) {
      state.terminalOffset = st.size;
      state.terminalReadError = null;
      return;
    }

    const stream = fs.createReadStream(terminalPath, { start, end: st.size - 1, encoding });
    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    const parseOpts = staleFallback
      ? { collectEvents: false, collectMetrics: false }
      : { collectEvents: true, collectMetrics: true };

    for await (const line of rl) {
      if (!line) continue;
      parseTerminalLine(line, state, profile, activeDay, parseOpts);
    }

    state.terminalOffset = st.size;
    state.terminalReadError = null;
  } catch (err) {
    state.terminalReadError = err?.message || String(err);
  }
}

function decodeTailBuffer(buf) {
  if (!buf || !buf.length) return '';
  let zeroes = 0;
  const sample = Math.min(buf.length, 1024 * 32);
  for (let i = 0; i < sample; i++) {
    if (buf[i] === 0) zeroes += 1;
  }
  return (zeroes / sample) > 0.2 ? buf.toString('utf16le') : buf.toString('utf8');
}

async function readTailText(filePath, maxBytes = 512 * 1024) {
  try {
    const st = await fsp.stat(filePath);
    const size = st.size;
    const start = Math.max(0, size - maxBytes);
    const fd = await fsp.open(filePath, 'r');
    try {
      const len = size - start;
      const buf = Buffer.alloc(len);
      await fd.read(buf, 0, len, start);
      let txt = decodeTailBuffer(buf);
      if (start > 0) {
        const n = txt.indexOf('\n');
        if (n >= 0) txt = txt.slice(n + 1);
      }
      return txt;
    } finally {
      await fd.close();
    }
  } catch {
    return '';
  }
}

async function scanMqlConfig(filePath, cached = {}) {
  const out = {
    startEquity: cached.startEquity ?? null,
    riskPct: cached.riskPct ?? null,
    equityHint: cached.equityHint ?? null,
  };

  const encoding = await detectFileEncoding(filePath);
  const stream = fs.createReadStream(filePath, { encoding });
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  for await (const line of rl) {
    if (!line) continue;
    const mStart = line.match(startEqRe);
    if (mStart) out.startEquity = Number(mStart[1]);

    const mRisk = line.match(riskRe);
    if (mRisk) out.riskPct = Number(mRisk[1]);
    const mCfgRisk = line.match(activeCfgRiskRe);
    if (mCfgRisk) out.riskPct = Number(mCfgRisk[1]);

    const mEq = line.match(equityRe);
    if (mEq) out.equityHint = Number(mEq[1]);
  }

  return out;
}

async function updateMqlHints(profile, state, day) {
  const resolved = await resolveLogFile(profile, ['MQL5', 'Logs'], day);
  const mqlPath = resolved.path;
  const activeDay = resolved.day;
  state.mqlPath = mqlPath;
  state.mqlLogDay = activeDay;

  let txt = '';
  try {
    await fsp.stat(mqlPath);
    txt = await readTailText(mqlPath, 900 * 1024);
    state.mqlReadError = null;
  } catch (err) {
    state.mqlReadError = err?.message || String(err);
    return;
  }

  const hintedOpenTickets = new Set();
  let runningSeen = false;

  if (txt) {
    for (const line of txt.split(/\r?\n/)) {
      if (!line) continue;
      const tsMatch = line.match(tsRe);
      const ts = tsMatch ? tsMatch[1] : null;
      maybeCaptureLeverage(state, line, activeDay, ts, 'mql');

      const mStart = line.match(startEqRe);
      if (mStart) {
        state.startEquity = Number(mStart[1]);
        pushEvent(state, activeDay, profile, 'mql', 'daily-reset', line, ts);
      }

      const mRisk = line.match(riskRe);
      if (mRisk) state.riskPct = Number(mRisk[1]);
      const mCfgRisk = line.match(activeCfgRiskRe);
      if (mCfgRisk) state.riskPct = Number(mCfgRisk[1]);

      const mEq = line.match(equityRe);
      if (mEq) state.equityHint = Number(mEq[1]);

      const mSnapshot = line.match(snapshotRe);
      if (mSnapshot) {
        state.balanceSnapshot = Number(mSnapshot[1]);
        state.equitySnapshot = Number(mSnapshot[2]);
        state.profitSnapshot = Number(mSnapshot[3]);
        state.freeMarginSnapshot = Number(mSnapshot[4]);
        if (!state.dayOpeningLocked && state.dayOpeningEquity == null) {
          const eq0 = Number(mSnapshot[2]);
          const bal0 = Number(mSnapshot[1]);
          if (Number.isFinite(eq0) && eq0 > 0) {
            state.dayOpeningEquity = eq0;
            state.dayOpeningBalance = Number.isFinite(bal0) ? bal0 : null;
            state.dayOpeningAt = ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : nowIso();
          } else if (Number.isFinite(bal0) && bal0 > 0) {
            state.dayOpeningEquity = bal0;
            state.dayOpeningBalance = bal0;
            state.dayOpeningAt = ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : nowIso();
          }
        }
        if (mSnapshot[5] && !state.account) state.account = mSnapshot[5];
        state.snapshotAt = ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : nowIso();
        pushEvent(state, activeDay, profile, 'mql', 'account-snapshot', line, ts);
      }

      const mRunning = line.match(runningPosRe);
      if (mRunning) {
        const buyCount = Number(mRunning[1] || 0);
        const sellCount = Number(mRunning[2] || 0);
        const totalRunning = Math.max(0, buyCount + sellCount);
        const runningAtIso = ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : nowIso();
        state.runningOpenPositions = totalRunning;
        state.runningSeenAt = runningAtIso;
        // Some bots log RUNNING counters as strategy counters rather than true open positions.
        // Ignore obviously inflated values to avoid stale false exposure on the motherboard.
        if (totalRunning <= 30) {
          state.openPositions = totalRunning;
          state.lastSyncAt = runningAtIso;
          runningSeen = true;
        }
      }

      const mAutoTicket = line.match(autoCorrectTicketRe);
      if (mAutoTicket) hintedOpenTickets.add(mAutoTicket[1]);
      const mPosDetail = line.match(positionDetailRe);
      if (mPosDetail) {
        const ticket = mPosDetail[1];
        const side = String(mPosDetail[2] || '').toLowerCase();
        const entry = Number(mPosDetail[3]);
        const current = Number(mPosDetail[4]);
        const symFromLine = (line.match(/\(([A-Z0-9]+),M\d+\)/i) || [])[1];
        const symbol = String(symFromLine || '').toUpperCase() || null;
        const existing = state.positions[ticket] || {};
        state.positions[ticket] = {
          symbol: symbol || existing.symbol || null,
          side: (side === 'buy' || side === 'sell') ? side : (existing.side || null),
          entry: Number.isFinite(entry) ? entry : (existing.entry || null),
          volume: Number.isFinite(existing.volume) && existing.volume > 0 ? existing.volume : 0,
          current: Number.isFinite(current) ? current : (existing.current || null),
          seenAt: ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : nowIso(),
        };
        hintedOpenTickets.add(ticket);
      }
      const mPosTicket = line.match(positionTicketRe);
      if (mPosTicket) hintedOpenTickets.add(mPosTicket[1]);

      if (/\*\*\* ENTRY:|STOP LOSS|TP1|TP2|TP3|TP4|Daily equity reset/i.test(line)) {
        pushEvent(state, activeDay, profile, 'mql', 'strategy', line, ts);
      }
    }
  }

  if (!runningSeen && state.openPositions <= 0 && hintedOpenTickets.size > 0) {
    // Fallback when terminal sync counters are unavailable: infer open count from active position-ticket traces.
    state.openPositions = hintedOpenTickets.size;
    if (!state.lastSyncAt) state.lastSyncAt = nowIso();
  }

  if (state.startEquity === null || state.riskPct === null) {
    try {
      const scanned = await scanMqlConfig(mqlPath, state);
      if (state.startEquity === null) state.startEquity = scanned.startEquity;
      if (state.riskPct === null) state.riskPct = scanned.riskPct;
      if (state.equityHint === null) state.equityHint = scanned.equityHint;
    } catch {
      // Best effort only.
    }
  }
}

async function lockDayAnchorsFromMql(profile, state, day) {
  if (state.dayOpeningLocked && state.dayOpeningEquity != null && state.leverage != null) return;

  const resolved = await resolveLogFile(profile, ['MQL5', 'Logs'], day);
  const mqlPath = resolved.path;
  const activeDay = resolved.day;
  let st;
  try {
    st = await fsp.stat(mqlPath);
  } catch {
    return;
  }

  // Full-file scan is done once per day (or when anchors are still missing) to avoid
  // drift from late restarts or partial tail reads.
  const enc = await detectFileEncoding(mqlPath);
  const stream = fs.createReadStream(mqlPath, { encoding: enc });
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  let firstStartEq = null;
  let firstStartEqAt = null;
  let firstSnapshot = null;
  let firstSnapshotAt = null;
  let latestLeverage = null;
  let latestLeverageAt = null;
  let firstAccount = null;

  for await (const line of rl) {
    if (!line) continue;
    const tsMatch = line.match(tsRe);
    const ts = tsMatch ? tsMatch[1] : null;
    const isoTs = ts ? new Date(eventEpoch(activeDay, ts)).toISOString() : null;

    const mAcct = line.match(accountRe);
    if (mAcct && !firstAccount) firstAccount = mAcct[1];

    const mStart = line.match(startEqRe);
    if (mStart && firstStartEq == null) {
      const n = Number(mStart[1]);
      if (Number.isFinite(n) && n > 0) {
        firstStartEq = n;
        firstStartEqAt = isoTs;
      }
    }

    const mSnap = line.match(snapshotRe);
    if (mSnap && firstSnapshot == null) {
      const bal = Number(mSnap[1]);
      const eq = Number(mSnap[2]);
      if (Number.isFinite(eq) && eq > 0) {
        firstSnapshot = { equity: eq, balance: Number.isFinite(bal) ? bal : null };
        firstSnapshotAt = isoTs;
      } else if (Number.isFinite(bal) && bal > 0) {
        firstSnapshot = { equity: bal, balance: bal };
        firstSnapshotAt = isoTs;
      }
      if (mSnap[5] && !firstAccount) firstAccount = mSnap[5];
    }

    const mLev = line.match(leverageLineRe) || line.match(leverageLooseRe);
    if (mLev) {
      const normalized = normalizeLeverageValue(mLev[1]);
      if (normalized) {
        latestLeverage = normalized;
        latestLeverageAt = isoTs;
      }
    }
  }

  if (!state.account && firstAccount) state.account = firstAccount;
  if (state.startEquity == null && firstStartEq != null) state.startEquity = firstStartEq;

  if (!state.dayOpeningLocked) {
    if (firstSnapshot) {
      state.dayOpeningEquity = firstSnapshot.equity;
      state.dayOpeningBalance = firstSnapshot.balance;
      state.dayOpeningAt = firstSnapshotAt || state.dayOpeningAt || nowIso();
      state.dayOpeningLocked = true;
    } else if (firstStartEq != null) {
      const snapEq = Number(state.equitySnapshot);
      const snapBal = Number(state.balanceSnapshot);
      const snapshotAnchor = Number.isFinite(snapEq) && snapEq > 0
        ? snapEq
        : (Number.isFinite(snapBal) && snapBal > 0 ? snapBal : null);
      const useSnapshotAnchor = snapshotAnchor != null && snapshotAnchor >= (firstStartEq * 3);
      const fallbackBaseline = useSnapshotAnchor ? snapshotAnchor : firstStartEq;
      state.dayOpeningEquity = fallbackBaseline;
      state.dayOpeningBalance = useSnapshotAnchor ? snapshotAnchor : firstStartEq;
      state.dayOpeningAt = (useSnapshotAnchor ? state.snapshotAt : firstStartEqAt) || state.dayOpeningAt || nowIso();
      state.dayOpeningLocked = true;
    }
  }

  if (latestLeverage) {
    state.leverage = latestLeverage;
    state.leverageSource = 'mql-scan';
    state.leverageAt = latestLeverageAt || nowIso();
  }

  if (!state.leverage && PROFILE_LEVERAGE_HINTS[profile]) {
    state.leverage = PROFILE_LEVERAGE_HINTS[profile];
    state.leverageSource = 'profile-hint';
    if (!state.leverageAt) state.leverageAt = nowIso();
  }
}

async function analyzeHistoricalDay(profile, day, existingEntry) {
  const terminalPath = path.join(MT5_ROOT, profile, 'Logs', `${day}.log`);
  const mqlPath = path.join(MT5_ROOT, profile, 'MQL5', 'Logs', `${day}.log`);

  let terminalStat;
  try {
    terminalStat = await fsp.stat(terminalPath);
  } catch {
    return null;
  }

  let mqlStat = null;
  try {
    mqlStat = await fsp.stat(mqlPath);
  } catch {
    // Optional.
  }

  const terminalFingerprint = `${terminalStat.size}:${terminalStat.mtimeMs}`;
  const mqlFingerprint = mqlStat ? `${mqlStat.size}:${mqlStat.mtimeMs}` : 'none';

  if (
    existingEntry &&
    existingEntry.terminalFingerprint === terminalFingerprint &&
    existingEntry.mqlFingerprint === mqlFingerprint
  ) {
    return existingEntry;
  }

  const tmpState = makeDailyState(day);
  tmpState.recentEvents = [];
  tmpState.recentEventHashes = [];

  const enc = await detectFileEncoding(terminalPath);
  const stream = fs.createReadStream(terminalPath, { encoding: enc });
  const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });

  for await (const line of rl) {
    if (!line) continue;
    parseTerminalLine(line, tmpState, profile, day, { collectEvents: false, collectMetrics: true });
  }

  let cfg = { startEquity: null, riskPct: null, equityHint: null };
  if (mqlStat) {
    try {
      cfg = await scanMqlConfig(mqlPath, cfg);
    } catch {
      // keep defaults
    }
  }

  return {
    profile,
    day,
    updatedAt: nowIso(),
    terminalFingerprint,
    mqlFingerprint,
    account: tmpState.account,
    startEquity: cfg.startEquity,
    riskPct: cfg.riskPct,
    equityHint: cfg.equityHint,
    metrics: cloneMetrics(tmpState.metrics),
  };
}

function classifyMetrics(metrics) {
  const matched = metrics.matchedCloses || 0;
  const net = metrics.netUsd || 0;
  const pf = metrics.profitFactor ?? null;
  const winRate = metrics.winRatePct ?? null;

  if (matched < 20) return { label: 'WARMUP', reason: 'Low sample size' };
  if (net > 0 && (pf === null || pf >= 1.2) && (winRate === null || winRate >= 45)) {
    return { label: 'WORKING', reason: 'Profitable with acceptable efficiency' };
  }
  if (matched > 120 && net <= 0) return { label: 'OVERTRADING', reason: 'High trade count without profits' };
  if (net < 0) return { label: 'FAILING', reason: 'Negative net performance' };
  return { label: 'WATCH', reason: 'Mixed performance; monitor closely' };
}

function classifyProfile(dayMetrics, weekMetrics) {
  const dayMatched = dayMetrics.matchedCloses || 0;
  if (dayMatched >= 20) return classifyMetrics(dayMetrics);

  const weekMatched = weekMetrics?.matchedCloses || 0;
  if (weekMatched >= 60) {
    const weekClass = classifyMetrics(weekMetrics);
    if (weekClass.label === 'WARMUP') return { label: 'WATCH', reason: 'Day sample is low; using week baseline' };
    return { label: weekClass.label, reason: `Day sample is low; week baseline: ${weekClass.reason}` };
  }

  return { label: 'WARMUP', reason: 'Low day sample size' };
}

function rollingCacheKey(profile, day, account) {
  const acc = String(account || '').trim() || 'unknown';
  return `${profile}:${acc}:${day}`;
}

function resolveBaselineFromState(state) {
  if (FORCE_DAY_BASELINE != null) return FORCE_DAY_BASELINE;
  const candidates = [
    state?.startEquity,
    state?.dayOpeningEquity,
    state?.dayOpeningBalance,
  ];
  for (const c of candidates) {
    const n = Number(c);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return DEFAULT_START_EQUITY;
}

function buildRollingMetrics(profile, currentDayState, weeklyCache, recentDays, today, maxDays, minDay = null) {
  const span = {
    metrics: cloneMetrics(currentDayState.metrics),
    baseline: resolveBaselineFromState(currentDayState),
    daysCovered: 1,
  };
  let used = 1;
  const currentAccount = String(currentDayState?.account || '').trim();

  for (const day of recentDays) {
    if (day === today || used >= maxDays) continue;
    if (minDay && day < minDay) continue;
    let entry = weeklyCache[rollingCacheKey(profile, day, currentAccount)];
    if (!entry && currentAccount) {
      const legacy = weeklyCache[`${profile}:${day}`];
      if (legacy && String(legacy.account || '').trim() === currentAccount) entry = legacy;
    }
    if (!entry || !entry.metrics) continue;
    addMetrics(span.metrics, entry.metrics);
    span.baseline += resolveBaselineFromState(entry);
    span.daysCovered += 1;
    used += 1;
  }

  return span;
}

function round2(v) {
  return Number(v.toFixed(2));
}

function metricsView(rawMetrics, baseline) {
  const m = cloneMetrics(rawMetrics);
  const matched = m.matchedCloses;
  const winRate = matched > 0 ? Number(((100 * m.wins) / matched).toFixed(2)) : null;
  const matchRate = m.closeRequests > 0 ? Number(((100 * matched) / m.closeRequests).toFixed(2)) : null;
  const profitFactor = m.grossLossUsd > 0 ? Number((m.grossProfitUsd / m.grossLossUsd).toFixed(3)) : null;
  const returnPct = baseline > 0 ? Number(((100 * m.netUsd) / baseline).toFixed(2)) : null;
  const expectancyUsd = matched > 0 ? Number((m.netUsd / matched).toFixed(2)) : null;
  const buySellTotal = m.buyCloses + m.sellCloses;
  const buyPct = buySellTotal > 0 ? Number(((100 * m.buyCloses) / buySellTotal).toFixed(2)) : null;
  const sellPct = buySellTotal > 0 ? Number(((100 * m.sellCloses) / buySellTotal).toFixed(2)) : null;
  const wlRatio = m.losses > 0 ? Number((m.wins / m.losses).toFixed(2)) : null;

  return {
    closeRequests: m.closeRequests,
    matchedCloses: matched,
    unmatchedCloseRequests: Math.max(0, m.closeRequests - matched),
    matchRatePct: matchRate,
    wins: m.wins,
    losses: m.losses,
    breakeven: m.breakeven,
    winRatePct: winRate,
    grossProfitUsd: round2(m.grossProfitUsd),
    grossLossUsd: round2(m.grossLossUsd),
    netUsd: round2(m.netUsd),
    returnPct,
    equityBaseline: baseline,
    profitFactor,
    expectancyUsd,
    closedVolume: round2(m.closedVolume),
    unmatchedDeals: m.unmatchedDeals,
    buyCloses: m.buyCloses,
    sellCloses: m.sellCloses,
    buyClosedVolume: round2(m.buyClosedVolume),
    sellClosedVolume: round2(m.sellClosedVolume),
    buyPct,
    sellPct,
    wlRatio,
  };
}

async function buildNexusSellHealth(profile, day) {
  const mqlPath = path.join(MT5_ROOT, profile, 'MQL5', 'Logs', `${day}.log`);

  const makeAcc = () => ({
    sellTickets: new Set(),
    beTriggeredTickets: new Set(),
    beSetEvents: 0,
    tpHitEvents: 0,
    tpFailEvents: 0,
    frozenEvents: 0,
    autoCorrectHits: 0,
    sellTpCalcEvents: 0,
    lastEventAt: null,
  });

  const ingestLine = (line, acc) => {
    if (!line) return;
    const tsMatch = line.match(tsRe);
    const ts = tsMatch ? tsMatch[1] : null;

    const posSellTicket = line.match(/Position\s+#(\d+)\s+\|\s+Type=SELL/i);
    if (posSellTicket) acc.sellTickets.add(posSellTicket[1]);

    if (line.includes('SELL BE FLAG')) {
      const m = line.match(/Ticket #(\d+)/i);
      if (m) {
        acc.beTriggeredTickets.add(m[1]);
        acc.sellTickets.add(m[1]);
      }
    }

    if (line.includes('SELL BE SET') || line.includes('SELL BE ALREADY SET')) acc.beSetEvents += 1;
    if (line.includes('SELL TP1 CLOSE CALCULATION')) acc.sellTpCalcEvents += 1;
    if (line.includes('TP1 HIT:') || line.includes('TP2 HIT:') || line.includes('TP3 HIT:')) acc.tpHitEvents += 1;
    if (line.includes('ERROR: TP1 failed') || line.includes('ERROR: TP2 failed') || line.includes('ERROR: TP3 failed')) acc.tpFailEvents += 1;
    if (line.includes('[frozen]') || line.includes('Position frozen - will retry next tick') || line.includes('TP2: Position frozen')) acc.frozenEvents += 1;
    if (line.includes('TYPE AUTO-CORRECT')) acc.autoCorrectHits += 1;

    if (
      posSellTicket || line.includes('SELL BE FLAG') || line.includes('SELL BE SET')
      || line.includes('TP1 HIT:') || line.includes('ERROR: TP1 failed') || line.includes('[frozen]')
    ) {
      acc.lastEventAt = ts ? new Date(eventEpoch(day, ts)).toISOString() : nowIso();
    }
  };

  const toOut = (acc, meta = {}) => {
    const out = {
      profile,
      day,
      windowBytes: Number(meta.windowBytes || 0),
      scanMode: meta.scanMode || 'tail',
      sellTradesSeen: acc.sellTickets.size,
      sellBeTriggered: acc.beTriggeredTickets.size,
      sellBeSet: acc.beSetEvents,
      sellTpCalcEvents: acc.sellTpCalcEvents,
      tpHits: acc.tpHitEvents,
      tpFails: acc.tpFailEvents,
      frozenEvents: acc.frozenEvents,
      autoCorrectHits: acc.autoCorrectHits,
      beTriggeredPct: null,
      beSetPct: null,
      tp1HitPct: null,
      tpFailRatePct: null,
      frozenRatePct: null,
      lastEventAt: acc.lastEventAt,
    };
    out.beTriggeredPct = out.sellTradesSeen > 0 ? Number(((100 * out.sellBeTriggered) / out.sellTradesSeen).toFixed(2)) : null;
    out.beSetPct = out.sellBeTriggered > 0 ? Number(((100 * out.sellBeSet) / out.sellBeTriggered).toFixed(2)) : null;
    out.tp1HitPct = out.sellBeTriggered > 0 ? Number(((100 * out.tpHits) / out.sellBeTriggered).toFixed(2)) : null;
    out.tpFailRatePct = (out.tpHits + out.tpFails) > 0 ? Number(((100 * out.tpFails) / (out.tpHits + out.tpFails)).toFixed(2)) : null;
    out.frozenRatePct = (out.tpHits + out.tpFails + out.frozenEvents) > 0
      ? Number(((100 * out.frozenEvents) / (out.tpHits + out.tpFails + out.frozenEvents)).toFixed(2))
      : null;
    return out;
  };

  const tailAcc = makeAcc();
  const txt = await readTailText(mqlPath, NEXUS_HEALTH_TAIL_BYTES);
  if (txt) {
    for (const line of txt.split(/\r?\n/)) ingestLine(line, tailAcc);
  }
  const tailOut = toOut(tailAcc, { scanMode: 'tail', windowBytes: NEXUS_HEALTH_TAIL_BYTES });

  const lowSignal =
    tailOut.sellTradesSeen < 2 &&
    tailOut.sellBeTriggered < 1 &&
    tailOut.tpHits < 1 &&
    tailOut.tpFails < 1 &&
    tailOut.frozenEvents < 1;
  if (!lowSignal) return tailOut;

  let mqlStat;
  try {
    mqlStat = await fsp.stat(mqlPath);
  } catch {
    return tailOut;
  }
  if (!mqlStat || mqlStat.size <= NEXUS_HEALTH_TAIL_BYTES) return tailOut;

  const fullAcc = makeAcc();
  try {
    const enc = await detectFileEncoding(mqlPath);
    const stream = fs.createReadStream(mqlPath, { encoding: enc });
    const rl = readline.createInterface({ input: stream, crlfDelay: Infinity });
    for await (const line of rl) ingestLine(line, fullAcc);
    return toOut(fullAcc, { scanMode: 'full', windowBytes: mqlStat.size });
  } catch {
    return tailOut;
  }
}

function profileSnapshot(profile, state, week, month, runtimeState = null, accountMeta = null, livePriceMap = null, liveProbe = null) {
  const forced = Number.isFinite(FORCE_DAY_BASELINE) && FORCE_DAY_BASELINE > 0 ? FORCE_DAY_BASELINE : null;
  let dayBaseline = forced ?? (state.dayOpeningEquity && state.dayOpeningEquity > 0
    ? state.dayOpeningEquity
    : (state.startEquity && state.startEquity > 0 ? state.startEquity : DEFAULT_START_EQUITY));
  const dayMetrics = metricsView(state.metrics, dayBaseline);
  const weekMetrics = metricsView(week.metrics, week.baseline);
  const monthMetrics = metricsView(month.metrics, month.baseline);

  const derivedBalance = dayBaseline > 0
    ? round2(dayBaseline + dayMetrics.netUsd)
    : (state.equityHint && state.equityHint > 0 ? round2(state.equityHint) : round2(DEFAULT_START_EQUITY + dayMetrics.netUsd));
  const hasSnapshot = Number.isFinite(Number(state.balanceSnapshot)) && Number(state.balanceSnapshot) > 0;
  const hasEquitySnapshot = Number.isFinite(Number(state.equitySnapshot)) && Number(state.equitySnapshot) > 0;
  let currentBalance = hasSnapshot ? round2(Number(state.balanceSnapshot)) : derivedBalance;
  const hintedEquity = Number.isFinite(Number(state.equityHint)) && Number(state.equityHint) > 0
    ? round2(Number(state.equityHint))
    : null;
  const positionsFromMap = activePositions(state).length;
  let openPositions = Number(state.openPositions || 0);
  const runningOpen = Number(state.runningOpenPositions);
  const nowMs = Date.now();
  const lastSyncMs = Date.parse(state.lastSyncAt || '');
  const snapshotMs = Date.parse(state.snapshotAt || '');
  const runningSeenMs = Date.parse(state.runningSeenAt || '');
  const syncIsFresh = Number.isFinite(lastSyncMs) && ((nowMs - lastSyncMs) <= (12 * 60 * 1000));
  const snapshotIsFresh = Number.isFinite(snapshotMs) && ((nowMs - snapshotMs) <= (12 * 60 * 1000));
  const runningIsFresh = Number.isFinite(runningSeenMs) && ((nowMs - runningSeenMs) <= (12 * 60 * 1000));
  if (runningIsFresh && Number.isFinite(runningOpen) && runningOpen >= 0) {
    openPositions = runningOpen;
  }
  if (!syncIsFresh && !snapshotIsFresh && !runningIsFresh) {
    openPositions = 0;
  }
  const canUseHintedEquity = hintedEquity != null && (openPositions > 0 || positionsFromMap > 0);
  let currentEquity = hasEquitySnapshot ? round2(Number(state.equitySnapshot)) : (canUseHintedEquity ? hintedEquity : currentBalance);
  const eqMinusBal = round2(currentEquity - currentBalance);
  const snapshotProfitRaw = Number(state.profitSnapshot);
  const hasSnapshotProfit = Number.isFinite(snapshotProfitRaw);
  const positionsPnlEstimate = estimateOpenProfitFromPositions(state, livePriceMap || {});
  const hasPositionsEstimate = Number.isFinite(positionsPnlEstimate);
  let openProfit = hasSnapshotProfit
    ? round2(snapshotProfitRaw)
    : eqMinusBal;
  const hasOpenExposure = openPositions > 0 || positionsFromMap > 0;
  if (!hasOpenExposure) {
    openProfit = 0;
  }
  if (hasOpenExposure && hasPositionsEstimate) {
    const snapshotMissingOrZero = !hasSnapshotProfit || Math.abs(openProfit) < 0.01;
    const snapshotDrift = Math.abs(openProfit - positionsPnlEstimate) >= 25;
    if (snapshotMissingOrZero || snapshotDrift) {
      openProfit = round2(positionsPnlEstimate);
    }
  }
  if (hasOpenExposure && Number.isFinite(eqMinusBal)) {
    const snapshotIsZeroish = !hasSnapshotProfit || Math.abs(openProfit) < 0.01;
    const oppositeSign =
      Math.abs(openProfit) > 0.01 &&
      Math.abs(eqMinusBal) > 0.01 &&
      Math.sign(openProfit) !== Math.sign(eqMinusBal);
    const largeDrift = Math.abs(openProfit - eqMinusBal) >= 25;
    if (snapshotIsZeroish || (oppositeSign && largeDrift)) {
      openProfit = eqMinusBal;
    }
  }
  // Normalize stale open-position counters against fresh account snapshots.
  if (hasSnapshotProfit) {
    if (Math.abs(openProfit) >= 0.01 && openPositions <= 0) openPositions = 1;
    if (Math.abs(openProfit) < 0.01 && positionsFromMap === 0 && openPositions > 0) openPositions = 0;
  }
  if (snapshotIsFresh && hasSnapshotProfit) {
    if (Math.abs(openProfit) < 0.01) openPositions = 0;
    if (Math.abs(openProfit) >= 0.01 && openPositions <= 0) openPositions = 1;
  }
  if (runningIsFresh && Number.isFinite(runningOpen) && runningOpen === 0) {
    openPositions = 0;
    openProfit = 0;
  } else if (openPositions <= 0 && positionsFromMap > 0) {
    openPositions = positionsFromMap;
  }
  if (openPositions > 0 && !hasSnapshotProfit && !hasPositionsEstimate && !Number.isFinite(eqMinusBal)) {
    openProfit = null;
  }
  if (!hasEquitySnapshot && Number.isFinite(currentBalance) && Number.isFinite(openProfit)) {
    currentEquity = round2(currentBalance + openProfit);
  }
  let balanceSource = hasSnapshot ? 'snapshot' : 'derived';
  const probeByProfile = liveProbe?.byProfile || {};
  const probeByAccount = liveProbe?.byAccount || {};
  const probeRow = probeByProfile[profile]
    || probeByAccount[String(state.account || accountMeta?.account || '').trim()]
    || null;
  if (probeRow) {
    const probeBalance = Number(probeRow.balance);
    const probeEquity = Number(probeRow.equity);
    const probeProfit = Number(probeRow.profit);
    const probeOpenPositions = Number(probeRow.openPositions);
    const probeDayStartEq = Number(probeRow.dayStartEquity ?? probeRow.startEquity);
    if (Number.isFinite(probeBalance) && probeBalance > 0) currentBalance = round2(probeBalance);
    if (Number.isFinite(probeEquity) && probeEquity > 0) currentEquity = round2(probeEquity);
    if (Number.isFinite(probeProfit)) openProfit = round2(probeProfit);
    if (Number.isFinite(probeOpenPositions) && probeOpenPositions >= 0) openPositions = Math.round(probeOpenPositions);
    if (Number.isFinite(probeDayStartEq) && probeDayStartEq > 0) {
      // Guard against probe-side baseline drift:
      // once this day's baseline is locked, do not keep replacing it from probe snapshots.
      // Replacing it every cycle can pin Day P/L near zero for active accounts (e.g., copier rows).
      const hasLockedDayBaseline = Boolean(state.dayOpeningLocked)
        && Number.isFinite(Number(state.dayOpeningEquity))
        && Number(state.dayOpeningEquity) > 0;
      if (!hasLockedDayBaseline) {
        dayBaseline = round2(probeDayStartEq);
        state.dayOpeningEquity = dayBaseline;
        state.dayOpeningBalance = dayBaseline;
        if (!state.dayOpeningAt) state.dayOpeningAt = nowIso();
        state.dayOpeningLocked = true;
      } else {
        dayBaseline = round2(Number(state.dayOpeningEquity));
      }
    }
    balanceSource = 'mt5-probe';
  }
  // Keep week/month profile metrics sane for UI tables when parsed trade totals drift.
  const saneWeekNet = Number.isFinite(week.baseline) ? round2(currentEquity - week.baseline) : round2(openProfit);
  const saneMonthNet = Number.isFinite(month.baseline) ? round2(currentEquity - month.baseline) : round2(openProfit);
  if (Math.abs(Number(weekMetrics.netUsd || 0)) > Math.max(10000, Math.abs(currentBalance) * 4)) {
    weekMetrics.netUsd = saneWeekNet;
    weekMetrics.returnPct = week.baseline > 0 ? Number(((100 * saneWeekNet) / week.baseline).toFixed(2)) : null;
  }
  if (Math.abs(Number(monthMetrics.netUsd || 0)) > Math.max(10000, Math.abs(currentBalance) * 4)) {
    monthMetrics.netUsd = saneMonthNet;
    monthMetrics.returnPct = month.baseline > 0 ? Number(((100 * saneMonthNet) / month.baseline).toFixed(2)) : null;
  }
  // Day P/L must reset daily from the day baseline (07:00 Perth alignment via day key/reset hour).
  const dayNetLiveUsd = dayBaseline > 0
    ? round2(currentEquity - dayBaseline)
    : round2(dayMetrics.netUsd + openProfit);
  const dayReturnLivePct = dayBaseline > 0 ? Number(((100 * dayNetLiveUsd) / dayBaseline).toFixed(2)) : null;
  const probeAccountStartEq = Number(probeRow?.accountStartEquity ?? probeRow?.startEquity);
  const totalBaseline = Number.isFinite(probeAccountStartEq) && probeAccountStartEq > 0
    ? round2(probeAccountStartEq)
    : (Number.isFinite(Number(state.startEquity)) && Number(state.startEquity) > 0
      ? round2(Number(state.startEquity))
      : round2(dayBaseline || DEFAULT_START_EQUITY));
  const totalNetUsd = totalBaseline > 0 ? round2(currentEquity - totalBaseline) : null;
  const totalReturnPct = (totalBaseline > 0 && Number.isFinite(totalNetUsd))
    ? Number(((100 * totalNetUsd) / totalBaseline).toFixed(2))
    : null;

  const openPositionRows = activePositionEntries(state)
    .map(([ticket, p]) => ({
      ticket,
      symbol: p.symbol,
      side: p.side,
      volume: Number(p.volume.toFixed(2)),
      entry: Number(p.entry.toFixed(3)),
    }))
    .sort((a, b) => b.volume - a.volume)
    .slice(0, 10);

  const status = classifyProfile(dayMetrics, weekMetrics);
  const strategyHint = detectStrategyHint(state.recentEvents);
  const profileLabelBase = deriveProfileLabel(profile, strategyHint);
  const leverageEstimated = estimateLeverageFromEquity(currentEquity || currentBalance || dayBaseline);
  const leverage = state.leverage || PROFILE_LEVERAGE_HINTS[profile] || leverageEstimated || null;
  const leverageSource = state.leverageSource
    || (PROFILE_LEVERAGE_HINTS[profile] ? 'profile-hint' : null)
    || (leverageEstimated ? 'equity-tier-estimate' : null);
  const runtime = runtimeState && typeof runtimeState === 'object' ? runtimeState : {};
  const runtimeDrift = Boolean(runtime.runtimeDrift);
  const runtimeDriftReasons = Array.isArray(runtime.runtimeDriftReasons) ? runtime.runtimeDriftReasons : [];
  const taskConfigMode = runtime.taskConfigMode || null;
  const profileLast = runtime.profileLast || null;
  const chartCount = Number.isFinite(Number(runtime.chartCount)) ? Number(runtime.chartCount) : null;
  const chartFiles = Number.isFinite(Number(runtime.chartFiles)) ? Number(runtime.chartFiles) : null;
  const expectedExpertsLoaded = typeof runtime.expectedExpertsLoaded === 'boolean' ? runtime.expectedExpertsLoaded : null;
  const tfPendingLive = /^BLUEPRINT_TF_/.test(String(profile || '')) && balanceSource === 'derived';
  const displayBalance = tfPendingLive ? null : currentBalance;
  const displayEquity = tfPendingLive ? null : currentEquity;
  const displayOpenProfit = tfPendingLive ? null : openProfit;
  const displayDayNetLiveUsd = tfPendingLive ? null : dayNetLiveUsd;
  const displayDayReturnLivePct = tfPendingLive ? null : dayReturnLivePct;
  const displayBalanceSource = tfPendingLive ? 'pending-live-probe' : balanceSource;
  const profileLabel = pickDisplayLabel(profile, accountMeta, probeRow, profileLabelBase);

  return {
    profile,
    profileLabel,
    strategyHint,
    account: state.account || accountMeta?.account || null,
    accountId: state.account || accountMeta?.account || null,
    accountName: String(probeRow?.accountName || '').trim() || null,
    botName: accountMeta?.bot || null,
    symbols: accountMeta?.symbols || null,
    onlineHint: Boolean(state.lastSyncAt),
    lastSyncAt: state.lastSyncAt,
    lastActivityAt: state.lastActivityAt,
    openPositions,
    openOrders: state.openOrders,
    startEquity: state.startEquity,
    dayOpeningEquity: state.dayOpeningEquity,
    dayStartEquity: dayBaseline,
    dayOpeningBalance: state.dayOpeningBalance,
    dayStartBalance: state.dayOpeningBalance,
    dayStartAt: state.dayOpeningAt,
    dayStartLocked: Boolean(state.dayOpeningLocked),
    accountStartEquity: totalBaseline,
    equityHint: state.equityHint,
    currentBalance: displayBalance,
    currentBalanceEst: displayBalance,
    currentEquity: displayEquity,
    openProfit: displayOpenProfit,
    totalNetUsd,
    totalReturnPct,
    freeMargin: Number.isFinite(Number(state.freeMarginSnapshot)) ? round2(Number(state.freeMarginSnapshot)) : null,
    balanceSource: displayBalanceSource,
    snapshotAt: state.snapshotAt,
    riskPct: (PROFILE_RISK_HINTS[profile] ?? state.riskPct),
    leverage,
    leverageSource,
    leverageAt: state.leverageAt || null,
    taskConfigMode,
    profileLast,
    chartCount,
    chartFiles,
    expectedExpertsLoaded,
    runtimeDrift,
    runtimeDriftReasons,
    metrics: {
      day: {
        ...dayMetrics,
        equityBaseline: dayBaseline,
        netUsdRealized: dayMetrics.netUsd,
        returnPctRealized: dayMetrics.returnPct,
        netUsdLive: displayDayNetLiveUsd,
        returnPctLive: displayDayReturnLivePct,
        openProfitUsd: openProfit,
      },
      week: { ...weekMetrics, daysCovered: week.daysCovered },
      month: { ...monthMetrics, daysCovered: month.daysCovered },
      total: {
        baseline: totalBaseline,
        netUsd: totalNetUsd,
        returnPct: totalReturnPct,
      },
      status,
    },
    estimatedOpenPositions: openPositionRows,
    recentEvents: state.recentEvents.slice(-30),
    dataQuality: {
      partialBackfill: Boolean(state.terminalPartialBackfill),
      terminalReadError: state.terminalReadError,
      terminalLogDay: state.terminalLogDay || null,
      mqlReadError: state.mqlReadError,
      mqlLogDay: state.mqlLogDay || null,
      note: balanceSource === 'snapshot'
        ? 'Balance/equity are from EA account snapshots in MQL logs; trade metrics are still log-derived estimates.'
        : 'Balance/equity are derived from logs; broker statement is source of truth.',
    },
  };
}

async function listProfiles(activeProfiles = null) {
  if (Array.isArray(activeProfiles) && activeProfiles.length) {
    return activeProfiles;
  }
  try {
    const dirs = await fsp.readdir(MT5_ROOT, { withFileTypes: true });
    return dirs
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .filter((name) => !HIDDEN_PROFILES.has(name))
      .sort((a, b) => a.localeCompare(b));
  } catch {
    return [];
  }
}

async function getRuntimeFallback(profile) {
  const out = {
    chartCount: null,
    chartFiles: null,
    expectedExpertsLoaded: null,
  };
  try {
    const chartsDir = path.join(MT5_ROOT, profile, 'MQL5', 'Profiles', 'Charts', 'Default');
    const chartEntries = await fsp.readdir(chartsDir, { withFileTypes: true });
    const files = chartEntries.filter((e) => e.isFile()).map((e) => e.name);
    out.chartFiles = files.length;
    out.chartCount = files.filter((n) => /^chart\d+\.chr$/i.test(n)).length;
  } catch {
    // best-effort only
  }
  try {
    const expertsDir = path.join(MT5_ROOT, profile, 'MQL5', 'Experts');
    const expertEntries = await fsp.readdir(expertsDir, { withFileTypes: true });
    const gm = expertEntries
      .filter((e) => e.isFile())
      .map((e) => e.name)
      .filter((n) => /^Goldmine.*\.(mq5|ex5)$/i.test(n));
    out.expectedExpertsLoaded = gm.length > 0;
  } catch {
    // best-effort only
  }
  return out;
}

function aggregateAccounts(profileSnapshots) {
  const map = new Map();
  for (const p of profileSnapshots) {
    const key = p.account || `unknown:${p.profile}`;
    if (!map.has(key)) {
      map.set(key, {
        account: key,
        profiles: [],
        openPositions: 0,
        openOrders: 0,
        dayBaseline: 0,
        weekBaseline: 0,
        monthBaseline: 0,
      dayNetUsd: 0,
      dayNetLiveUsd: 0,
      weekNetUsd: 0,
      monthNetUsd: 0,
        dayGrossProfitUsd: 0,
        dayGrossLossUsd: 0,
        weekGrossProfitUsd: 0,
        weekGrossLossUsd: 0,
        monthGrossProfitUsd: 0,
        monthGrossLossUsd: 0,
        dayWins: 0,
        dayLosses: 0,
        weekWins: 0,
        weekLosses: 0,
        monthWins: 0,
        monthLosses: 0,
        dayMatchedCloses: 0,
        weekMatchedCloses: 0,
        monthMatchedCloses: 0,
        dayBuyCloses: 0,
        daySellCloses: 0,
        currentBalance: 0,
        currentEquity: 0,
        openProfit: 0,
        snapshotProfiles: 0,
        riskPctSum: 0,
        riskPctCount: 0,
      });
    }
    const a = map.get(key);
    a.profiles.push(p.profile);
    a.openPositions += Number(p.openPositions || 0);
    a.openOrders += Number(p.openOrders || 0);
    a.dayNetUsd += Number(p.metrics?.day?.netUsd || 0);
    a.dayNetLiveUsd += Number(p.metrics?.day?.netUsdLive ?? ((p.metrics?.day?.netUsd || 0) + (p.openProfit || 0)));
    a.weekNetUsd += Number(p.metrics?.week?.netUsd || 0);
    a.monthNetUsd += Number(p.metrics?.month?.netUsd || 0);
    a.dayGrossProfitUsd += Number(p.metrics?.day?.grossProfitUsd || 0);
    a.dayGrossLossUsd += Number(p.metrics?.day?.grossLossUsd || 0);
    a.weekGrossProfitUsd += Number(p.metrics?.week?.grossProfitUsd || 0);
    a.weekGrossLossUsd += Number(p.metrics?.week?.grossLossUsd || 0);
    a.monthGrossProfitUsd += Number(p.metrics?.month?.grossProfitUsd || 0);
    a.monthGrossLossUsd += Number(p.metrics?.month?.grossLossUsd || 0);
    a.dayBaseline += Number(p.metrics?.day?.equityBaseline || 0);
    a.weekBaseline += Number(p.metrics?.week?.equityBaseline || 0);
    a.monthBaseline += Number(p.metrics?.month?.equityBaseline || 0);
    a.dayWins += Number(p.metrics?.day?.wins || 0);
    a.dayLosses += Number(p.metrics?.day?.losses || 0);
    a.weekWins += Number(p.metrics?.week?.wins || 0);
    a.weekLosses += Number(p.metrics?.week?.losses || 0);
    a.monthWins += Number(p.metrics?.month?.wins || 0);
    a.monthLosses += Number(p.metrics?.month?.losses || 0);
    a.dayMatchedCloses += Number(p.metrics?.day?.matchedCloses || 0);
    a.weekMatchedCloses += Number(p.metrics?.week?.matchedCloses || 0);
    a.monthMatchedCloses += Number(p.metrics?.month?.matchedCloses || 0);
    a.dayBuyCloses += Number(p.metrics?.day?.buyCloses || 0);
    a.daySellCloses += Number(p.metrics?.day?.sellCloses || 0);
    a.currentBalance += Number(p.currentBalance || p.currentBalanceEst || 0);
    a.currentEquity += Number(p.currentEquity || p.currentBalance || p.currentBalanceEst || 0);
    a.openProfit += Number(p.openProfit || 0);
    if (Number.isFinite(Number(p.riskPct))) {
      a.riskPctSum += Number(p.riskPct);
      a.riskPctCount += 1;
    }
    if (p.balanceSource === 'snapshot') a.snapshotProfiles += 1;
  }

  return Array.from(map.values())
    .map((a) => {
      const dayBaseline = round2(a.dayBaseline);
      const weekBaseline = round2(a.weekBaseline);
      const monthBaseline = round2(a.monthBaseline);
      const currentBalance = round2(a.currentBalance);
      const currentEquity = round2(a.currentEquity);
      const openProfit = round2(a.openProfit);

      // Guard against runaway parsed trade totals: fall back to equity/baseline deltas.
      const inferredDayNet = Number.isFinite(dayBaseline) ? round2(currentEquity - dayBaseline) : round2(openProfit);
      const inferredWeekNet = Number.isFinite(weekBaseline) ? round2(currentEquity - weekBaseline) : inferredDayNet;
      const inferredMonthNet = Number.isFinite(monthBaseline) ? round2(currentEquity - monthBaseline) : inferredDayNet;
      const dayNetParsed = round2(a.dayNetUsd);
      const dayNetLiveParsed = round2(a.dayNetLiveUsd);
      const weekNetParsed = round2(a.weekNetUsd);
      const monthNetParsed = round2(a.monthNetUsd);

      const dayNetUsd = Math.abs(dayNetParsed) > Math.max(5000, Math.abs(currentBalance) * 3) ? inferredDayNet : dayNetParsed;
      const dayNetLiveUsd = Math.abs(dayNetLiveParsed) > Math.max(5000, Math.abs(currentBalance) * 3) ? inferredDayNet : dayNetLiveParsed;
      const weekNetUsd = Math.abs(weekNetParsed) > Math.max(10000, Math.abs(currentBalance) * 4) ? inferredWeekNet : weekNetParsed;
      const monthNetUsd = Math.abs(monthNetParsed) > Math.max(10000, Math.abs(currentBalance) * 4) ? inferredMonthNet : monthNetParsed;

      return {
      ...a,
      dayNetUsd,
      dayNetLiveUsd,
      weekNetUsd,
      monthNetUsd,
      dayGrossProfitUsd: round2(a.dayGrossProfitUsd),
      dayGrossLossUsd: round2(a.dayGrossLossUsd),
      weekGrossProfitUsd: round2(a.weekGrossProfitUsd),
      weekGrossLossUsd: round2(a.weekGrossLossUsd),
      monthGrossProfitUsd: round2(a.monthGrossProfitUsd),
      monthGrossLossUsd: round2(a.monthGrossLossUsd),
      dayBaseline,
      weekBaseline,
      monthBaseline,
      dayWins: a.dayWins,
      dayLosses: a.dayLosses,
      weekWins: a.weekWins,
      weekLosses: a.weekLosses,
      monthWins: a.monthWins,
      monthLosses: a.monthLosses,
      dayMatchedCloses: a.dayMatchedCloses,
      weekMatchedCloses: a.weekMatchedCloses,
      monthMatchedCloses: a.monthMatchedCloses,
      dayBuyCloses: a.dayBuyCloses,
      daySellCloses: a.daySellCloses,
      currentBalance,
      currentBalanceEst: currentBalance,
      currentEquity,
      openProfit,
      snapshotProfiles: a.snapshotProfiles,
      avgRiskPct: a.riskPctCount > 0 ? Number((a.riskPctSum / a.riskPctCount).toFixed(2)) : null,
      dayReturnPct: dayBaseline > 0 ? Number(((100 * dayNetLiveUsd) / dayBaseline).toFixed(2)) : null,
      dayReturnPctRealized: dayBaseline > 0 ? Number(((100 * dayNetUsd) / dayBaseline).toFixed(2)) : null,
      weekReturnPct: weekBaseline > 0 ? Number(((100 * weekNetUsd) / weekBaseline).toFixed(2)) : null,
      monthReturnPct: monthBaseline > 0 ? Number(((100 * monthNetUsd) / monthBaseline).toFixed(2)) : null,
      dayProfitFactor: a.dayGrossLossUsd > 0 ? Number((a.dayGrossProfitUsd / a.dayGrossLossUsd).toFixed(3)) : null,
      weekProfitFactor: a.weekGrossLossUsd > 0 ? Number((a.weekGrossProfitUsd / a.weekGrossLossUsd).toFixed(3)) : null,
      monthProfitFactor: a.monthGrossLossUsd > 0 ? Number((a.monthGrossProfitUsd / a.monthGrossLossUsd).toFixed(3)) : null,
      buyPct: (a.dayBuyCloses + a.daySellCloses) > 0 ? Number(((100 * a.dayBuyCloses) / (a.dayBuyCloses + a.daySellCloses)).toFixed(2)) : null,
      sellPct: (a.dayBuyCloses + a.daySellCloses) > 0 ? Number(((100 * a.daySellCloses) / (a.dayBuyCloses + a.daySellCloses)).toFixed(2)) : null,
    };
    })
    .sort((a, b) => b.weekNetUsd - a.weekNetUsd);
}

function buildOverview(profileSnapshots) {
  const sortedWeek = [...profileSnapshots].sort((a, b) => (b.metrics.week.returnPct || -9999) - (a.metrics.week.returnPct || -9999));
  const sortedDay = [...profileSnapshots].sort((a, b) => ((b.metrics.day.returnPctLive ?? b.metrics.day.returnPct) || -9999) - ((a.metrics.day.returnPctLive ?? a.metrics.day.returnPct) || -9999));

  const topWorking = sortedWeek
    .filter((p) => p.metrics.status.label === 'WORKING')
    .slice(0, 5)
    .map((p) => ({
      profile: p.profile,
      profileLabel: p.profileLabel || p.profile,
      dayRetPct: p.metrics.day.returnPctLive ?? p.metrics.day.returnPct,
      weekRetPct: p.metrics.week.returnPct,
      dayNetUsd: p.metrics.day.netUsdLive ?? p.metrics.day.netUsd,
    }));

  const needsAttention = sortedDay
    .filter((p) => p.metrics.status.label === 'OVERTRADING' || p.metrics.status.label === 'FAILING')
    .slice(0, 6)
    .map((p) => ({
      profile: p.profile,
      profileLabel: p.profileLabel || p.profile,
      status: p.metrics.status.label,
      reason: p.metrics.status.reason,
      matchedCloses: p.metrics.day.matchedCloses,
      dayNetUsd: p.metrics.day.netUsdLive ?? p.metrics.day.netUsd,
      dayRetPct: p.metrics.day.returnPctLive ?? p.metrics.day.returnPct,
      profitFactor: p.metrics.day.profitFactor,
    }));

  return {
    topWorking,
    needsAttention,
    leadersToday: sortedDay.slice(0, 3).map((p) => ({
      profile: p.profile,
      profileLabel: p.profileLabel || p.profile,
      retPct: p.metrics.day.returnPctLive ?? p.metrics.day.returnPct,
      netUsd: p.metrics.day.netUsdLive ?? p.metrics.day.netUsd,
    })),
    leadersWeek: sortedWeek.slice(0, 3).map((p) => ({ profile: p.profile, profileLabel: p.profileLabel || p.profile, retPct: p.metrics.week.returnPct, netUsd: p.metrics.week.netUsd })),
  };
}

function applyEmergencyAccountOverrides(output, overridesByAccount) {
  if (!overridesByAccount || Object.keys(overridesByAccount).length === 0) return 0;
  const n = (v, d = 0) => (Number.isFinite(Number(v)) ? Number(v) : d);
  let changed = 0;

  const applyToRow = (row, account) => {
    const key = String(account || '').trim();
    const o = overridesByAccount[key];
    if (!o) return false;
    const weekBaseline = n(row?.metrics?.week?.equityBaseline ?? row?.weekBaseline, 15000);
    const monthBaseline = n(row?.metrics?.month?.equityBaseline ?? row?.monthBaseline, weekBaseline || 15000);
    const dayPL = n(o.dayPL, 0);
    const dayPct = Number.isFinite(Number(o.dayPct))
      ? Number(o.dayPct)
      : (n(row?.metrics?.day?.equityBaseline ?? row?.dayBaseline, 5000) > 0
        ? Number(((100 * dayPL) / n(row?.metrics?.day?.equityBaseline ?? row?.dayBaseline, 5000)).toFixed(2))
        : 0);
    const weekPL = n(o.weekPL, 0);
    const monthPL = Number.isFinite(Number(o.monthPL)) ? Number(o.monthPL) : weekPL;
    const openPnl = n(o.openPnl, 0);
    const balance = n(o.balance, n(row?.currentBalance, 0));
    const equity = n(o.equity, balance);

    row.currentBalance = round2(balance);
    row.currentBalanceEst = round2(balance);
    row.currentEquity = round2(equity);
    row.openProfit = round2(openPnl);
    row.openPositions = Math.abs(openPnl) > 0.01 ? 1 : 0;
    row.balanceSource = 'restored-screenshot';

    if (row.metrics?.day) {
      row.metrics.day.netUsdLive = round2(dayPL);
      row.metrics.day.netUsd = round2(dayPL);
      row.metrics.day.returnPctLive = Number(dayPct.toFixed(2));
      row.metrics.day.returnPct = Number(dayPct.toFixed(2));
      row.metrics.day.openProfitUsd = round2(openPnl);
    }
    if ('dayNetLiveUsd' in row) row.dayNetLiveUsd = round2(dayPL);
    if ('dayNetUsd' in row) row.dayNetUsd = round2(dayPL);
    if ('dayReturnPct' in row) row.dayReturnPct = Number(dayPct.toFixed(2));
    if ('dayReturnPctRealized' in row) row.dayReturnPctRealized = Number(dayPct.toFixed(2));
    if (row.metrics?.week) {
      row.metrics.week.netUsd = round2(weekPL);
      row.metrics.week.returnPct = weekBaseline > 0 ? Number(((100 * weekPL) / weekBaseline).toFixed(2)) : null;
    }
    if ('weekNetUsd' in row) row.weekNetUsd = round2(weekPL);
    if ('weekReturnPct' in row) row.weekReturnPct = weekBaseline > 0 ? Number(((100 * weekPL) / weekBaseline).toFixed(2)) : null;
    if (row.metrics?.month) {
      row.metrics.month.netUsd = round2(monthPL);
      row.metrics.month.returnPct = monthBaseline > 0 ? Number(((100 * monthPL) / monthBaseline).toFixed(2)) : null;
    }
    if ('monthNetUsd' in row) row.monthNetUsd = round2(monthPL);
    if ('monthReturnPct' in row) row.monthReturnPct = monthBaseline > 0 ? Number(((100 * monthPL) / monthBaseline).toFixed(2)) : null;
    if ('weekBaseline' in row) row.weekBaseline = round2(weekBaseline);
    if ('monthBaseline' in row) row.monthBaseline = round2(monthBaseline);
    if ('dayBaseline' in row) row.dayBaseline = round2(n(row?.dayBaseline, n(row?.metrics?.day?.equityBaseline, 5000)));
    return true;
  };

  for (const p of (output.profiles || [])) {
    if (applyToRow(p, p.account)) changed += 1;
  }
  for (const a of (output.accounts || [])) {
    if (applyToRow(a, a.account)) changed += 1;
  }

  if (changed > 0) {
    const accounts = Array.isArray(output.accounts) ? output.accounts : [];
    const sum = (key) => accounts.reduce((acc, row) => acc + n(row?.[key], 0), 0);
    if (output.summary?.day) {
      output.summary.day.netUsdLive = round2(sum('dayNetLiveUsd'));
      output.summary.day.netUsd = round2(sum('dayNetUsd'));
      output.summary.day.returnPctLive = output.summary.day.baseline > 0
        ? Number(((100 * output.summary.day.netUsdLive) / Number(output.summary.day.baseline)).toFixed(2))
        : null;
      output.summary.day.returnPct = output.summary.day.baseline > 0
        ? Number(((100 * output.summary.day.netUsd) / Number(output.summary.day.baseline)).toFixed(2))
        : null;
    }
    if (output.summary?.week) {
      output.summary.week.netUsd = round2(sum('weekNetUsd'));
      output.summary.week.returnPct = output.summary.week.baseline > 0
        ? Number(((100 * output.summary.week.netUsd) / Number(output.summary.week.baseline)).toFixed(2))
        : null;
    }
    if (output.summary?.month) {
      output.summary.month.netUsd = round2(sum('monthNetUsd'));
      output.summary.month.returnPct = output.summary.month.baseline > 0
        ? Number(((100 * output.summary.month.netUsd) / Number(output.summary.month.baseline)).toFixed(2))
        : null;
    }
    if (output.summary) {
      output.summary.totalOpenProfitUsd = round2(sum('openProfit'));
      output.summary.totalOpenPositions = Math.round(sum('openPositions'));
      output.summary.estimatedCurrentBalanceTotal = round2(sum('currentBalance'));
      output.summary.estimatedCurrentEquityTotal = round2(sum('currentEquity'));
    }
  }

  return changed;
}

async function main() {
  const today = yyyymmdd();
  const cacheDays = Math.max(WEEK_DAYS, MONTH_DAYS);
  const recentDays = daysBackList(cacheDays);
  const accountMetaByProfile = await readAccountsCsvMap(ACCOUNTS_CSV);
  const activeProfiles = await readActiveProfiles(ACCOUNTS_CSV);
  const profiles = await listProfiles(activeProfiles);
  const liveProbe = await readLiveProbeMap();
  const emergencyOverrides = ENABLE_EMERGENCY_OVERRIDES
    ? await readEmergencyAccountOverrides()
    : {};
  const runtimeIntegrity = await readJsonFile(RUNTIME_INTEGRITY_FILE, null);
  const runtimeByProfile = {};
  for (const row of (Array.isArray(runtimeIntegrity?.profiles) ? runtimeIntegrity.profiles : [])) {
    if (row?.profile) runtimeByProfile[row.profile] = row;
  }

  const prev = await readJsonFile(STATE_FILE, {});
  const next = {
    day: today,
    profiles: prev.profiles || {},
    weeklyCache: prev.weeklyCache || {},
  };

  const profileSnapshots = [];
  const livePriceMap = await fetchLivePriceMap(['XAUUSD', 'XAGUSD']);

  for (const profile of profiles) {
    const currentState = ensureProfileState(next.profiles[profile], today);
    // Rebuild open exposure from fresh log lines each cycle.
    currentState.openPositions = 0;
    currentState.openOrders = 0;
    currentState.positions = {};
    currentState.pendingCloseRequests = [];
    currentState.terminalOffset = 0;
    currentState.terminalPartialBackfill = false;
    await processTerminalIncremental(profile, currentState, today);
    await updateMqlHints(profile, currentState, today);
    await lockDayAnchorsFromMql(profile, currentState, today);
    const currentAccount = String(currentState.account || '').trim();
    const firstSeenAccount = String(currentState.firstSeenAccount || '').trim();
    if (!currentState.firstSeenDay) currentState.firstSeenDay = today;
    if (currentAccount && !firstSeenAccount) {
      currentState.firstSeenAccount = currentAccount;
      currentState.firstSeenDay = today;
    } else if (currentAccount && firstSeenAccount && currentAccount !== firstSeenAccount) {
      currentState.firstSeenAccount = currentAccount;
      currentState.firstSeenDay = today;
      for (const wk of Object.keys(next.weeklyCache)) {
        if (wk.startsWith(`${profile}:`)) delete next.weeklyCache[wk];
      }
    }
    next.profiles[profile] = currentState;

    for (const day of recentDays) {
      if (day === today) continue;
      const key = rollingCacheKey(profile, day, currentAccount);
      const cached = next.weeklyCache[key] || null;
      const analyzed = await analyzeHistoricalDay(profile, day, cached);
      if (analyzed) {
        const analyzedAccount = String(analyzed.account || currentAccount || '').trim();
        const finalKey = rollingCacheKey(profile, day, analyzedAccount);
        next.weeklyCache[finalKey] = analyzed;
        if (finalKey !== key) delete next.weeklyCache[key];
      } else {
        delete next.weeklyCache[key];
      }
      // Always clear legacy profile:day cache keys to prevent account cross-contamination.
      delete next.weeklyCache[`${profile}:${day}`];
    }

    const weekly = buildRollingMetrics(profile, currentState, next.weeklyCache, recentDays, today, WEEK_DAYS, currentState.firstSeenDay || null);
    const monthly = buildRollingMetrics(profile, currentState, next.weeklyCache, recentDays, today, MONTH_DAYS, currentState.firstSeenDay || null);
    const runtimeFallback = await getRuntimeFallback(profile);
    const runtimeRow = { ...(runtimeByProfile[profile] || {}) };
    if (!Number.isFinite(Number(runtimeRow.chartCount)) && Number.isFinite(Number(runtimeFallback.chartCount))) runtimeRow.chartCount = runtimeFallback.chartCount;
    if (!Number.isFinite(Number(runtimeRow.chartFiles)) && Number.isFinite(Number(runtimeFallback.chartFiles))) runtimeRow.chartFiles = runtimeFallback.chartFiles;
    if (typeof runtimeRow.expectedExpertsLoaded !== 'boolean' && typeof runtimeFallback.expectedExpertsLoaded === 'boolean') {
      runtimeRow.expectedExpertsLoaded = runtimeFallback.expectedExpertsLoaded;
    }
    profileSnapshots.push(profileSnapshot(
      profile,
      currentState,
      weekly,
      monthly,
      runtimeRow,
      accountMetaByProfile[profile] || null,
      livePriceMap,
      liveProbe,
    ));
  }

  const keepDays = new Set(recentDays);
  for (const key of Object.keys(next.weeklyCache)) {
    const profile = key.split(':', 1)[0];
    const day = key.slice(key.lastIndexOf(':') + 1);
    if (!profiles.includes(profile) || !keepDays.has(day)) delete next.weeklyCache[key];
  }

  const liveFeed = profileSnapshots
    .flatMap((p) => p.recentEvents.map((e) => ({ ...e, profile: p.profile })))
    .sort((a, b) => b.t - a.t)
    .slice(0, 300);

  const nexusSellHealth = [];
  for (const p of profileSnapshots) {
    if (!p.profile || !p.profile.startsWith('Nexus')) continue;
    const health = await buildNexusSellHealth(p.profile, today);
    nexusSellHealth.push({
      ...health,
      account: p.account || null,
      riskPct: p.riskPct ?? null,
    });
  }

  const dayTotals = profileSnapshots.reduce((acc, p) => {
    acc.grossProfit += Number(p.metrics.day.grossProfitUsd || 0);
    acc.grossLoss += Number(p.metrics.day.grossLossUsd || 0);
    acc.net += Number(p.metrics.day.netUsd || 0);
    acc.netLive += Number(p.metrics.day.netUsdLive ?? ((p.metrics.day.netUsd || 0) + (p.openProfit || 0)));
    acc.baseline += Number(p.metrics.day.equityBaseline || 0);
    acc.wins += Number(p.metrics.day.wins || 0);
    acc.losses += Number(p.metrics.day.losses || 0);
    acc.breakeven += Number(p.metrics.day.breakeven || 0);
    acc.matched += Number(p.metrics.day.matchedCloses || 0);
    acc.closeReq += Number(p.metrics.day.closeRequests || 0);
    acc.openPos += Number(p.openPositions || 0);
    acc.openOrders += Number(p.openOrders || 0);
    acc.balance += Number(p.currentBalance || p.currentBalanceEst || 0);
    acc.equity += Number(p.currentEquity || p.currentBalance || p.currentBalanceEst || 0);
    acc.openProfit += Number(p.openProfit || 0);
    if (p.balanceSource === 'snapshot') acc.snapshotProfiles += 1;
    return acc;
  }, { grossProfit: 0, grossLoss: 0, net: 0, netLive: 0, baseline: 0, wins: 0, losses: 0, breakeven: 0, matched: 0, closeReq: 0, openPos: 0, openOrders: 0, balance: 0, equity: 0, openProfit: 0, snapshotProfiles: 0 });

  const weekTotals = profileSnapshots.reduce((acc, p) => {
    acc.grossProfit += Number(p.metrics.week.grossProfitUsd || 0);
    acc.grossLoss += Number(p.metrics.week.grossLossUsd || 0);
    acc.net += Number(p.metrics.week.netUsd || 0);
    acc.baseline += Number(p.metrics.week.equityBaseline || 0);
    acc.wins += Number(p.metrics.week.wins || 0);
    acc.losses += Number(p.metrics.week.losses || 0);
    acc.breakeven += Number(p.metrics.week.breakeven || 0);
    acc.matched += Number(p.metrics.week.matchedCloses || 0);
    return acc;
  }, { grossProfit: 0, grossLoss: 0, net: 0, baseline: 0, wins: 0, losses: 0, breakeven: 0, matched: 0 });
  const monthTotals = profileSnapshots.reduce((acc, p) => {
    acc.grossProfit += Number(p.metrics.month?.grossProfitUsd || 0);
    acc.grossLoss += Number(p.metrics.month?.grossLossUsd || 0);
    acc.net += Number(p.metrics.month?.netUsd || 0);
    acc.baseline += Number(p.metrics.month?.equityBaseline || 0);
    acc.wins += Number(p.metrics.month?.wins || 0);
    acc.losses += Number(p.metrics.month?.losses || 0);
    acc.breakeven += Number(p.metrics.month?.breakeven || 0);
    acc.matched += Number(p.metrics.month?.matchedCloses || 0);
    return acc;
  }, { grossProfit: 0, grossLoss: 0, net: 0, baseline: 0, wins: 0, losses: 0, breakeven: 0, matched: 0 });

  const statusCounts = profileSnapshots.reduce((acc, p) => {
    const label = p.metrics?.status?.label || 'UNKNOWN';
    acc[label] = (acc[label] || 0) + 1;
    return acc;
  }, {});

  const summary = {
    profilesTotal: profileSnapshots.length,
    profilesWithSync: profileSnapshots.filter((p) => p.lastSyncAt).length,
    totalOpenPositions: dayTotals.openPos,
    totalOpenOrders: dayTotals.openOrders,
    day: {
      grossProfitUsd: round2(dayTotals.grossProfit),
      grossLossUsd: round2(dayTotals.grossLoss),
      netUsd: round2(dayTotals.net),
      netUsdLive: round2(dayTotals.netLive),
      baseline: round2(dayTotals.baseline),
      returnPct: dayTotals.baseline > 0 ? Number(((100 * dayTotals.net) / dayTotals.baseline).toFixed(2)) : null,
      returnPctLive: dayTotals.baseline > 0 ? Number(((100 * dayTotals.netLive) / dayTotals.baseline).toFixed(2)) : null,
      wins: dayTotals.wins,
      losses: dayTotals.losses,
      breakeven: dayTotals.breakeven,
      matchedCloses: dayTotals.matched,
      closeRequests: dayTotals.closeReq,
      matchRatePct: dayTotals.closeReq > 0 ? Number(((100 * dayTotals.matched) / dayTotals.closeReq).toFixed(2)) : null,
      winRatePct: dayTotals.matched > 0 ? Number(((100 * dayTotals.wins) / dayTotals.matched).toFixed(2)) : null,
      profitFactor: dayTotals.grossLoss > 0 ? Number((dayTotals.grossProfit / dayTotals.grossLoss).toFixed(3)) : null,
    },
    week: {
      grossProfitUsd: round2(weekTotals.grossProfit),
      grossLossUsd: round2(weekTotals.grossLoss),
      netUsd: round2(weekTotals.net),
      wins: weekTotals.wins,
      losses: weekTotals.losses,
      breakeven: weekTotals.breakeven,
      matchedCloses: weekTotals.matched,
      baseline: round2(weekTotals.baseline),
      returnPct: weekTotals.baseline > 0 ? Number(((100 * weekTotals.net) / weekTotals.baseline).toFixed(2)) : null,
      winRatePct: weekTotals.matched > 0 ? Number(((100 * weekTotals.wins) / weekTotals.matched).toFixed(2)) : null,
      profitFactor: weekTotals.grossLoss > 0 ? Number((weekTotals.grossProfit / weekTotals.grossLoss).toFixed(3)) : null,
      daysCovered: WEEK_DAYS,
    },
    month: {
      grossProfitUsd: round2(monthTotals.grossProfit),
      grossLossUsd: round2(monthTotals.grossLoss),
      netUsd: round2(monthTotals.net),
      wins: monthTotals.wins,
      losses: monthTotals.losses,
      breakeven: monthTotals.breakeven,
      matchedCloses: monthTotals.matched,
      baseline: round2(monthTotals.baseline),
      returnPct: monthTotals.baseline > 0 ? Number(((100 * monthTotals.net) / monthTotals.baseline).toFixed(2)) : null,
      winRatePct: monthTotals.matched > 0 ? Number(((100 * monthTotals.wins) / monthTotals.matched).toFixed(2)) : null,
      profitFactor: monthTotals.grossLoss > 0 ? Number((monthTotals.grossProfit / monthTotals.grossLoss).toFixed(3)) : null,
      daysCovered: MONTH_DAYS,
    },
    estimatedCurrentBalanceTotal: round2(dayTotals.balance),
    estimatedCurrentEquityTotal: round2(dayTotals.equity),
    totalOpenProfitUsd: round2(dayTotals.openProfit),
    balanceExactProfiles: dayTotals.snapshotProfiles,
    balanceCoveragePct: profileSnapshots.length > 0 ? Number(((100 * dayTotals.snapshotProfiles) / profileSnapshots.length).toFixed(2)) : null,
    runtimeDriftProfiles: profileSnapshots.filter((p) => p.runtimeDrift).length,
    statusCounts,
  };

  const output = {
    generatedAt: nowIso(),
    day: today,
    source: {
      mt5Root: MT5_ROOT,
      reportsRoot: REPORTS_ROOT,
      telemetryVersion: 2,
      runtimeIntegrityFile: RUNTIME_INTEGRITY_FILE,
      timezone: PERTH_TIMEZONE,
      dayResetHour: DAY_RESET_HOUR,
      forcedDayBaseline: Number.isFinite(FORCE_DAY_BASELINE) && FORCE_DAY_BASELINE > 0 ? FORCE_DAY_BASELINE : null,
      weekDays: WEEK_DAYS,
      monthDays: MONTH_DAYS,
      defaultStartEquity: DEFAULT_START_EQUITY,
    },
    summary,
    overview: buildOverview(profileSnapshots),
    accounts: aggregateAccounts(profileSnapshots),
    nexusSellHealth,
    profiles: profileSnapshots,
    liveFeed,
  };

  const emergencyRowsOverridden = ENABLE_EMERGENCY_OVERRIDES
    ? applyEmergencyAccountOverrides(output, emergencyOverrides)
    : 0;
  output.source.emergencyOverrideFile = EMERGENCY_OVERRIDE_FILE;
  output.source.emergencyOverridesEnabled = ENABLE_EMERGENCY_OVERRIDES;
  output.source.emergencyOverrideRows = emergencyRowsOverridden;

  await writeJsonFile(TELEMETRY_FILE, output);
  await writeJsonFile(STATE_FILE, next);

  process.stdout.write(`telemetry ok ${output.generatedAt} profiles=${summary.profilesTotal} openPos=${summary.totalOpenPositions} dayNet=${summary.day.netUsd} weekNet=${summary.week.netUsd}\n`);
}

main().catch((err) => {
  process.stderr.write(`telemetry error: ${err?.stack || err}\n`);
  process.exit(1);
});
