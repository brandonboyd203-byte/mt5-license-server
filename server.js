//+------------------------------------------------------------------+
//| Remote License Server for MT5 EAs                                |
//| Validates licenses for BigBeluga and Advanced Scalper EAs         |
//+------------------------------------------------------------------+

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs').promises;
const https = require('https');
const nodemailer = require('nodemailer');
const path = require('path');
const cron = require('node-cron');

const app = express();
// Railway sets PORT automatically - use it or default to 3001
const PORT = process.env.PORT || 3001;
// License/copier paths: env first, then /data if volume is mounted (Railway), else app dir
const fsSync = require('fs');
const DATA_DIR = '/data';
const useDataDir = !process.env.LICENSE_FILE && fsSync.existsSync(DATA_DIR);
const LICENSE_FILE = process.env.LICENSE_FILE || (useDataDir ? path.join(DATA_DIR, 'licenses.json') : path.join(__dirname, 'licenses.json'));
const COPIER_SUBSCRIBERS_FILE = process.env.COPIER_SUBSCRIBERS_FILE || (useDataDir ? path.join(DATA_DIR, 'copier_subscribers.json') : path.join(__dirname, 'copier_subscribers.json'));
const CHECKOUT_ORDERS_FILE = process.env.CHECKOUT_ORDERS_FILE || (useDataDir ? path.join(DATA_DIR, 'checkout_orders.json') : path.join(__dirname, 'checkout_orders.json'));
const SECRET_KEY = process.env.SECRET_KEY || 'your-secret-key-change-this';
const COINBASE_COMMERCE_API_KEY = process.env.COINBASE_COMMERCE_API_KEY || '';
const COINBASE_WEBHOOK_SHARED_SECRET = process.env.COINBASE_WEBHOOK_SHARED_SECRET || '';
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL ? String(process.env.PUBLIC_BASE_URL).replace(/\/+$/, '') : '';
// Support/contact email shown on site and in checkout error messages (e.g. support@yourdomain.com)
const SUPPORT_EMAIL = process.env.SUPPORT_EMAIL || process.env.CONTACT_EMAIL || '';
// Invoice sending: Resend (preferred) or SMTP (any provider – Gmail, Mailgun, SendGrid, Outlook, etc.)
const RESEND_API_KEY = process.env.RESEND_API_KEY || '';
const RESEND_FROM_EMAIL = process.env.RESEND_FROM_EMAIL || SUPPORT_EMAIL || 'GOLDMINE <onboarding@resend.dev>';
const SMTP_HOST = process.env.SMTP_HOST || 'smtp.gmail.com';
const SMTP_PORT = Number(process.env.SMTP_PORT || 465);
const SMTP_SECURE = process.env.SMTP_SECURE ? process.env.SMTP_SECURE === 'true' : SMTP_PORT === 465;
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || SMTP_USER;
const SMTP_FROM_NAME = process.env.SMTP_FROM_NAME || 'GOLDMINE';
const INVOICE_CRON = process.env.INVOICE_CRON || '0 9 1 * *';
const INVOICE_TIMEZONE = process.env.INVOICE_TIMEZONE || 'UTC';
const DEFAULT_IONOS_LAB_TELEMETRY_URL = 'http://93.90.193.150/api/telemetry';
const DEFAULT_IONOS_PROD_TELEMETRY_URL = 'http://212.227.201.75/api/telemetry';
const MOTHERBOARD_VDS_TELEMETRY_URL = process.env.MOTHERBOARD_VDS_TELEMETRY_URL || DEFAULT_IONOS_LAB_TELEMETRY_URL;
const MOTHERBOARD_VDS_TELEMETRY_URLS = String(
    process.env.MOTHERBOARD_VDS_TELEMETRY_URLS
    || `${DEFAULT_IONOS_LAB_TELEMETRY_URL},${DEFAULT_IONOS_PROD_TELEMETRY_URL}`
).split(',').map((url) => url.trim()).filter(Boolean);
const MOTHERBOARD_VDS_DASHBOARD_URL = process.env.MOTHERBOARD_VDS_DASHBOARD_URL || 'http://93.90.193.150/';
const MOTHERBOARD_VDS_CHARTS_URL = process.env.MOTHERBOARD_VDS_CHARTS_URL || MOTHERBOARD_VDS_TELEMETRY_URL.replace(/\/api\/telemetry$/i, '/api/charts/live');
const BOT_LAB_API_URL = process.env.BOT_LAB_API_URL || 'http://93.90.193.150/api/bot-lab/latest';
const BOT_LAB_HISTORY_URL = process.env.BOT_LAB_HISTORY_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/history');
const BOT_LAB_ANALYSIS_URL = process.env.BOT_LAB_ANALYSIS_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/analysis');
const BOT_LAB_CATALOG_URL = process.env.BOT_LAB_CATALOG_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/catalog');
const BOT_LAB_PROGRESS_URL = process.env.BOT_LAB_PROGRESS_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/progress');
const BOT_LAB_DISCORD_SUMMARY_URL = process.env.BOT_LAB_DISCORD_SUMMARY_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/discord-summary');
const BOT_LAB_RECOMMENDATIONS_URL = process.env.BOT_LAB_RECOMMENDATIONS_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/recommendations');
const BOT_LAB_SCHEDULE_URL = process.env.BOT_LAB_SCHEDULE_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/schedule');
const BOT_LAB_SWEEP_STATUS_URL = process.env.BOT_LAB_SWEEP_STATUS_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/param-sweep/status');
const MOTHERBOARD_TELEMETRY_MAX_AGE_MS = Math.max(
    60_000,
    Number(process.env.MOTHERBOARD_TELEMETRY_MAX_AGE_MS || (15 * 60 * 1000))
);
const BOT_LAB_CACHE_DIR = path.join(__dirname, 'data', 'bot-lab-cache');
const BOT_LAB_LATEST_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'latest.json');
const BOT_LAB_HISTORY_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'history.json');
const BOT_LAB_PROGRESS_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'progress.json');
const BOT_LAB_RECOMMENDATIONS_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'recommendations.json');
const BOT_LAB_CATALOG_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'catalog.json');
const BOT_LAB_ANALYSIS_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'analysis.json');
const BOT_LAB_DISCORD_SUMMARY_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'discord-summary.json');
const BOT_LAB_SCHEDULE_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'schedule.json');
const BOT_LAB_SWEEP_STATUS_CACHE_FILE = path.join(BOT_LAB_CACHE_DIR, 'param-sweep-status.json');
const BOT_LAB_CACHE_REFRESH_MS = Math.max(60_000, Number(process.env.BOT_LAB_CACHE_REFRESH_MS || 300_000));
const VDS_CASHFLOW_LEDGER_FILE = process.env.VDS_CASHFLOW_LEDGER_FILE || (useDataDir ? path.join(DATA_DIR, 'vds_cashflows.csv') : path.resolve(__dirname, '../secure/vds_cashflows.csv'));
const BUNDLED_VDS_CASHFLOW_SEED_FILE = path.join(__dirname, 'data', 'vds_cashflows.seed.csv');

// One license in a group = valid for any EA name in that group (dash/hyphen normalized in code)
// Include both ASCII hyphen (-) and en-dash (–) so EAs work regardless of encoding
const EA_NAME_GROUPS = [
    ['Goldmine Blueprint - Gold', 'Goldmine Blueprint - Silver', 'Goldmine Blueprint – Gold', 'Goldmine Blueprint – Silver', 'FXGOLDTRADERPLUGSMC', 'FXGOLDTRADERSMC', 'BigBeluga'],
    ['Goldmine Nexus - Gold', 'Goldmine Nexus - Silver', 'Goldmine Nexus – Gold', 'Goldmine Nexus – Silver', 'FXGOLDTRADERPLUG'],
    ['Goldmine Edge - Gold', 'Goldmine Edge – Gold', 'AdvancedScalper', 'Advanced Scalper', 'Advanced Scalper 1', 'Advanced Scalper 1.0', 'Advanced_Scalper'],
    [
        'Goldmine Surge - Gold',
        'Goldmine Surge – Gold',
        'AdvancedScalper2',
        'AdvancedScalper2.0',
        'Advanced Scalper 2',
        'Advanced Scalper 2.0',
        'Advanced_Scalper_2',
        'Gold Scalper',
        'GoldScalper',
        'Gold_Scalper'
    ],
    ['Goldmine Dominion'],
    ['Goldmine Fresh - Gold', 'Goldmine Fresh – Gold']
];

function normalizeEaName(value) {
    return String(value || '')
        .trim()
        .toLowerCase()
        .replace(/\s+/g, '')
        .replace(/[\-_–—\u00AD]/g, '');  // strip hyphens/dashes so "Goldmine Nexus - Silver" matches "Goldmine Nexus – Gold"
}

function normalizeBaseUrl(value) {
    if (!value) return '';
    const trimmed = String(value).trim();
    if (!trimmed) return '';
    const withProtocol = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
    return withProtocol.replace(/\/+$/, '');
}

function readJsonCache(filePath) {
    try {
        if (!fsSync.existsSync(filePath)) return null;
        return JSON.parse(fsSync.readFileSync(filePath, 'utf8'));
    } catch {
        return null;
    }
}

function parseCsvLine(line) {
    const out = [];
    let current = '';
    let inQuotes = false;
    for (let i = 0; i < line.length; i += 1) {
        const ch = line[i];
        if (ch === '"') {
            if (inQuotes && line[i + 1] === '"') {
                current += '"';
                i += 1;
            } else {
                inQuotes = !inQuotes;
            }
            continue;
        }
        if (ch === ',' && !inQuotes) {
            out.push(current);
            current = '';
            continue;
        }
        current += ch;
    }
    out.push(current);
    return out;
}

function toCsvCell(value) {
    const text = String(value ?? '');
    if (!/[",\n]/.test(text)) return text;
    return `"${text.replace(/"/g, '""')}"`;
}

async function loadVdsCashflowLedger() {
    const seedIntoLedger = async () => {
        const seedRaw = await fs.readFile(BUNDLED_VDS_CASHFLOW_SEED_FILE, 'utf8');
        await fs.mkdir(path.dirname(VDS_CASHFLOW_LEDGER_FILE), { recursive: true });
        await fs.writeFile(VDS_CASHFLOW_LEDGER_FILE, seedRaw, 'utf8');
    };
    try {
        const raw = await fs.readFile(VDS_CASHFLOW_LEDGER_FILE, 'utf8');
        const lines = raw.split(/\r?\n/).filter(Boolean);
        if (!lines.length) {
            try {
                await seedIntoLedger();
                return loadVdsCashflowLedger();
            } catch {
                return { header: ['profile', 'account', 'deposit_usd', 'withdraw_usd', 'source', 'note'], rows: [] };
            }
        }
        const header = parseCsvLine(lines[0]).map((x) => String(x || '').trim());
        const rows = lines.slice(1).map((line) => {
            const values = parseCsvLine(line);
            const row = {};
            header.forEach((key, idx) => {
                row[key] = values[idx] ?? '';
            });
            return {
                profile: String(row.profile || '').trim(),
                account: String(row.account || '').trim(),
                depositUsd: Number.isFinite(Number(row.deposit_usd)) ? Number(row.deposit_usd) : null,
                withdrawUsd: Number.isFinite(Number(row.withdraw_usd)) ? Number(row.withdraw_usd) : null,
                source: String(row.source || '').trim() || 'ledger',
                note: String(row.note || '').trim(),
            };
        }).filter((row) => row.profile);
        if (!rows.length) {
            try {
                await seedIntoLedger();
                return loadVdsCashflowLedger();
            } catch {}
        }
        return { header, rows };
    } catch (error) {
        if (error && error.code === 'ENOENT') {
            try {
                await seedIntoLedger();
                return loadVdsCashflowLedger();
            } catch {
                return { header: ['profile', 'account', 'deposit_usd', 'withdraw_usd', 'source', 'note'], rows: [] };
            }
        }
        throw error;
    }
}

async function saveVdsCashflowLedger(payload) {
    const header = Array.isArray(payload?.header) && payload.header.length
        ? payload.header
        : ['profile', 'account', 'deposit_usd', 'withdraw_usd', 'source', 'note'];
    const rows = Array.isArray(payload?.rows) ? payload.rows : [];
    const lines = [
        header.join(','),
        ...rows.map((row) => [
            toCsvCell(row.profile || ''),
            toCsvCell(row.account || ''),
            toCsvCell(Number.isFinite(Number(row.depositUsd)) ? Number(row.depositUsd).toFixed(2) : ''),
            toCsvCell(Number.isFinite(Number(row.withdrawUsd)) ? Number(row.withdrawUsd).toFixed(2) : ''),
            toCsvCell(row.source || 'ledger'),
            toCsvCell(row.note || ''),
        ].join(',')),
    ];
    await fs.writeFile(VDS_CASHFLOW_LEDGER_FILE, `${lines.join('\n')}\n`, 'utf8');
}

async function upsertVdsCashflowLedgerEntry(input) {
    const profile = String(input?.profile || '').trim();
    if (!profile) throw new Error('profile is required');
    const account = String(input?.account || '').trim();
    const source = String(input?.source || 'ledger').trim() || 'ledger';
    const note = String(input?.note || '').trim();
    const depositUsd = Number.isFinite(Number(input?.depositUsd)) ? Number(input.depositUsd) : null;
    const withdrawUsd = Number.isFinite(Number(input?.withdrawUsd)) ? Number(input.withdrawUsd) : null;
    const payload = await loadVdsCashflowLedger();
    const idx = payload.rows.findIndex((row) => String(row.profile || '').trim() === profile);
    const next = { profile, account, depositUsd, withdrawUsd, source, note };
    if (idx >= 0) payload.rows[idx] = next;
    else payload.rows.push(next);
    payload.rows.sort((a, b) => String(a.profile).localeCompare(String(b.profile)));
    await saveVdsCashflowLedger(payload);
    return next;
}

function writeJsonCache(filePath, value) {
    try {
        fsSync.mkdirSync(path.dirname(filePath), { recursive: true });
        fsSync.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
        return true;
    } catch (error) {
        console.error(`Failed to write bot-lab cache ${filePath}:`, error.message);
        return false;
    }
}

function botLabRowsFromPayload(payload) {
    if (!payload || typeof payload !== 'object') return [];
    if (Array.isArray(payload.results)) return payload.results;
    if (Array.isArray(payload.rows)) return payload.rows;
    if (Array.isArray(payload.runs)) return payload.runs;
    return [];
}

function hasUsableBotLabRows(payload) {
    return botLabRowsFromPayload(payload).length > 0;
}

function readBotLabAnalysisCache() {
    return readJsonCache(BOT_LAB_ANALYSIS_CACHE_FILE);
}

function readBotLabProgressCache() {
    return readJsonCache(BOT_LAB_PROGRESS_CACHE_FILE);
}

function deriveBotLabLatestFallback() {
    const analysis = readBotLabAnalysisCache();
    const progress = readBotLabProgressCache();
    const bestRows = Array.isArray(analysis?.best_by_bot) ? analysis.best_by_bot : [];
    const progressRows = Array.isArray(progress?.bots) ? progress.bots : [];
    const derivedRows = bestRows
        .filter((row) => row && (Number.isFinite(Number(row?.ret_pct)) || Number.isFinite(Number(row?.trades)) || Number.isFinite(Number(row?.final_balance))))
        .map((row) => ({
            bot: row.bot || '-',
            category: row.category || row.catalog?.category || 'Unassigned',
            variant: row.strategy_family || row.family || '-',
            case_id: row.strategy_family || row.family || row.bot || '-',
            status: row.status || 'PASS',
            pnl: Number.isFinite(Number(row?.final_balance)) && Number.isFinite(Number(row?.deposit ?? row?.startingBalance ?? row?.start_balance))
                ? Number((Number(row.final_balance) - Number(row.deposit ?? row.startingBalance ?? row.start_balance)).toFixed(2))
                : null,
            ret_pct: Number.isFinite(Number(row?.ret_pct)) ? Number(row.ret_pct) : null,
            trades: Number.isFinite(Number(row?.trades)) ? Number(row.trades) : null,
            win_rate_pct: Number.isFinite(Number(row?.win_rate_pct)) ? Number(row.win_rate_pct) : null,
            pf: Number.isFinite(Number(row?.pf)) ? Number(row.pf) : null,
            drawdown_pct: Number.isFinite(Number(row?.drawdown_pct)) ? Number(row.drawdown_pct) : null,
            window: row?.from_date && row?.to_date ? `${row.from_date} -> ${row.to_date}` : (row?.range || '-'),
            from_date: row?.from_date || '',
            to_date: row?.to_date || '',
            deposit: Number.isFinite(Number(row?.deposit ?? row?.startingBalance ?? row?.start_balance)) ? Number(row.deposit ?? row.startingBalance ?? row.start_balance) : null,
            final_balance: Number.isFinite(Number(row?.final_balance ?? row?.finalBalance)) ? Number(row.final_balance ?? row.finalBalance) : null,
            params: row?.params || null,
            sl_pips: row?.sl_pips ?? null,
            tp1_pips: row?.tp1_pips ?? null,
            tp2_pips: row?.tp2_pips ?? null,
            tp3_pips: row?.tp3_pips ?? null,
            trail_start_pips: row?.trail_start_pips ?? null,
            trail_distance_pips: row?.trail_distance_pips ?? null,
            updated_at: row?.updated_at || analysis?.updatedAt || progress?.updatedAt || null,
            completed_at: row?.completed_at || row?.updated_at || analysis?.updatedAt || progress?.updatedAt || null
        }))
        .sort((a, b) => (Number(b?.ret_pct || -Infinity) - Number(a?.ret_pct || -Infinity)))
        .slice(0, 20);

    if (!derivedRows.length) return null;
    return {
        ok: true,
        updatedAt: analysis?.updatedAt || progress?.updatedAt || new Date().toISOString(),
        results: derivedRows
    };
}

function deriveBotLabHistoryFallback(limit = 20) {
    const latest = deriveBotLabLatestFallback();
    if (!latest) return null;
    return {
        ok: true,
        updatedAt: latest.updatedAt,
        results: botLabRowsFromPayload(latest).slice(0, Math.max(1, Math.min(50, Number(limit) || 20)))
    };
}

function deriveBotLabDiscordSummaryFallback() {
    const progress = readBotLabProgressCache();
    const analysis = readBotLabAnalysisCache();
    if (!progress && !analysis) return null;
    const progressSummary = progress?.summary || {};
    const analysisSummary = analysis?.summary || {};
    const bestRows = Array.isArray(analysis?.best_by_bot) ? analysis.best_by_bot : [];
    const progressRows = Array.isArray(progress?.bots) ? progress.bots : [];
    const top = bestRows
        .filter((row) => Number.isFinite(Number(row?.ret_pct)))
        .sort((a, b) => Number(b?.ret_pct || -Infinity) - Number(a?.ret_pct || -Infinity))[0] || null;
    const availableBalances = Array.from(new Set(
        bestRows
            .map((row) => row?.aggregate?.balance_values || [])
            .flat()
            .concat(
                bestRows
                    .map((row) => Number(row?.deposit ?? row?.startingBalance ?? row?.start_balance))
                    .filter((value) => Number.isFinite(value)),
            )
    )).sort((a, b) => a - b);
    const validationCoveredBots = Number(analysisSummary?.validation_covered_bots)
        || bestRows.filter((row) => Number(row?.aggregate?.validation_windows || 0) > 0).length;
    const multiBalanceBots = Number(analysisSummary?.multi_balance_bots)
        || bestRows.filter((row) => Number(row?.aggregate?.tested_balances || 0) >= 2).length;
    const trackedBots = Number(progressSummary?.tracked_bots)
        || Number(analysisSummary?.bots_tracked)
        || progressRows.length
        || bestRows.length;
    const testedBots = Number(progressSummary?.tested_bots)
        || Number(analysisSummary?.tested_bots)
        || bestRows.length;
    const pendingBots = Number(progressSummary?.pending_bots)
        || Math.max(0, trackedBots - testedBots);
    return {
        ok: true,
        updatedAt: progress?.updatedAt || analysis?.updatedAt || new Date().toISOString(),
        status: {
            tracked_bots: trackedBots,
            tested_bots: testedBots,
            pending_bots: pendingBots,
            promotion_ready: Number(progressSummary?.promotion_ready || analysisSummary?.promotion_ready || 0),
            validation_covered_bots: validationCoveredBots,
            multi_balance_bots: multiBalanceBots,
            available_balances: Array.isArray(progressSummary?.available_balances) && progressSummary.available_balances.length ? progressSummary.available_balances : availableBalances,
            top_bot: top?.bot || null,
            top_return_pct: Number.isFinite(Number(top?.ret_pct)) ? Number(top.ret_pct) : null
        },
        summary: 'Bot Lab derived cache fallback active.'
    };
}

function resolveBotLabCachedPayload(kind, options = {}) {
    const limit = options.limit || 20;
    if (kind === 'latest') {
        const cached = readJsonCache(BOT_LAB_LATEST_CACHE_FILE);
        if (hasUsableBotLabRows(cached)) return cached;
        return deriveBotLabLatestFallback();
    }
    if (kind === 'history') {
        const cached = readJsonCache(BOT_LAB_HISTORY_CACHE_FILE);
        if (hasUsableBotLabRows(cached)) return cached;
        return deriveBotLabHistoryFallback(limit);
    }
    if (kind === 'discord-summary') {
        const cached = readJsonCache(BOT_LAB_DISCORD_SUMMARY_CACHE_FILE);
        if (cached && typeof cached === 'object' && cached.status) return cached;
        return deriveBotLabDiscordSummaryFallback();
    }
    return null;
}

function getEaNameCandidates(eaName) {
    const candidates = new Set();
    if (!eaName) return [];
    const normalized = normalizeEaName(eaName);
    EA_NAME_GROUPS.forEach((group) => {
        const hasMatch = group.some((name) => normalizeEaName(name) === normalized);
        if (hasMatch) {
            group.forEach((name) => candidates.add(name));
        }
    });
    candidates.add(eaName);
    return Array.from(candidates);
}

// Logo: serve before static; use LOGO_PATH env (e.g. /data/LOGO.png on volume) or look in assets
function getLogoPath() {
    if (process.env.LOGO_PATH && require('fs').existsSync(process.env.LOGO_PATH)) return process.env.LOGO_PATH;
    const names = ['LOGO.png', 'logo.png', 'GOLDMINE LOGO.png', 'logo.svg'];
    const dirs = [path.join(__dirname, 'assets'), __dirname];
    for (const dir of dirs) {
        for (const name of names) {
            const p = path.join(dir, name);
            try { if (require('fs').existsSync(p)) return p; } catch (_) {}
        }
    }
    return null;
}
app.get('/logo', (req, res) => {
    const logoPath = getLogoPath();
    if (!logoPath) return res.status(404).end();
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.sendFile(logoPath);
});
// Serve logo from assets with no-cache so updates show immediately after deploy
app.get('/assets/logo.png', (req, res) => {
    const p = path.join(__dirname, 'assets', 'logo.png');
    if (!fsSync.existsSync(p)) return res.status(404).end();
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.sendFile(p);
});

function sendGoldmineBotsManifest(res) {
    res.setHeader('Content-Type', 'application/manifest+json; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=300');
    res.send(JSON.stringify({
        name: 'Goldmine Bots',
        short_name: 'Goldmine',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: '#08101f',
        theme_color: '#08101f',
        description: 'Goldmine trading infrastructure with bots, live feed, pricing, and checkout.',
        icons: [
            { src: '/app-icon.svg', sizes: '1024x1024', type: 'image/svg+xml', purpose: 'any maskable' }
        ]
    }));
}

app.get('/app-icon-v2.png', (req, res) => {
    const p = path.join(__dirname, 'assets', 'app-icon-v2.png');
    if (!fsSync.existsSync(p)) return res.status(404).end();
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.sendFile(p);
});

app.get('/app-icon.svg', async (req, res) => {
    const p = path.join(__dirname, 'assets', 'app-icon-v2.png');
    if (!fsSync.existsSync(p)) return res.status(404).end();
    const raw = await fs.readFile(p);
    const base64 = raw.toString('base64');
    const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" fill="#000000"/>
  <image href="data:image/png;base64,${base64}" x="0" y="0" width="1024" height="1024" preserveAspectRatio="xMidYMid meet"/>
</svg>`;
    res.setHeader('Content-Type', 'image/svg+xml; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(svg);
});

app.get('/manifest-goldmine-bots.webmanifest', (req, res) => {
    sendGoldmineBotsManifest(res);
});

app.get('/manifest.webmanifest', (req, res) => {
    sendGoldmineBotsManifest(res);
});

app.get('/sw.js', (req, res) => {
    const swPath = path.join(__dirname, 'public', 'sw.js');
    if (!fsSync.existsSync(swPath)) return res.status(404).end();
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.sendFile(swPath);
});

// Middleware
app.use(cors());
app.use('/assets', express.static(path.join(__dirname, 'assets')));
app.use('/site', express.static(path.join(__dirname, 'public')));
app.use('/site/bot-lab-cache', express.static(BOT_LAB_CACHE_DIR));

let botFeedCache = { bySource: new Map() };
let botChartCache = { bySourceKey: new Map() };

async function fetchJsonWithTimeout(url, timeoutMs = 4000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetch(url, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            signal: controller.signal
        });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return await response.json();
    } finally {
        clearTimeout(timer);
    }
}

function withCacheBust(url) {
    try {
        const u = new URL(url);
        u.searchParams.set('_t', String(Date.now()));
        return u.toString();
    } catch {
        const sep = String(url).includes('?') ? '&' : '?';
        return `${url}${sep}_t=${Date.now()}`;
    }
}

function normalizeBotLabPayload(payload) {
    if (!payload || typeof payload !== 'object') return payload;
    const next = { ...payload };
    if (!Array.isArray(next.results) && Array.isArray(next.rows)) next.results = next.rows;
    if (!Array.isArray(next.rows) && Array.isArray(next.results)) next.rows = next.results;
    return next;
}

const BOT_LAB_CACHE_TARGETS = [
    { name: 'latest', url: BOT_LAB_API_URL, file: BOT_LAB_LATEST_CACHE_FILE, normalize: normalizeBotLabPayload, timeoutMs: 15000 },
    { name: 'history', url: `${BOT_LAB_HISTORY_URL}${BOT_LAB_HISTORY_URL.includes('?') ? '&' : '?'}limit=20`, file: BOT_LAB_HISTORY_CACHE_FILE, normalize: normalizeBotLabPayload, timeoutMs: 20000 },
    { name: 'analysis', url: BOT_LAB_ANALYSIS_URL, file: BOT_LAB_ANALYSIS_CACHE_FILE, timeoutMs: 20000 },
    { name: 'catalog', url: BOT_LAB_CATALOG_URL, file: BOT_LAB_CATALOG_CACHE_FILE, timeoutMs: 15000 },
    { name: 'progress', url: BOT_LAB_PROGRESS_URL, file: BOT_LAB_PROGRESS_CACHE_FILE, timeoutMs: 20000 },
    { name: 'discord-summary', url: BOT_LAB_DISCORD_SUMMARY_URL, file: BOT_LAB_DISCORD_SUMMARY_CACHE_FILE, timeoutMs: 20000 },
    { name: 'recommendations', url: BOT_LAB_RECOMMENDATIONS_URL, file: BOT_LAB_RECOMMENDATIONS_CACHE_FILE, timeoutMs: 20000 },
    { name: 'schedule', url: BOT_LAB_SCHEDULE_URL, file: BOT_LAB_SCHEDULE_CACHE_FILE, timeoutMs: 20000 },
    { name: 'param-sweep-status', url: BOT_LAB_SWEEP_STATUS_URL, file: BOT_LAB_SWEEP_STATUS_CACHE_FILE, timeoutMs: 20000 }
];

let botLabCacheRefreshInFlight = null;
async function refreshBotLabCaches(force = false) {
    if (botLabCacheRefreshInFlight && !force) return botLabCacheRefreshInFlight;
    botLabCacheRefreshInFlight = (async () => {
        const results = [];
        for (const target of BOT_LAB_CACHE_TARGETS) {
            try {
                let payload = await fetchJsonWithTimeout(withCacheBust(target.url), target.timeoutMs || 15000);
                if (typeof target.normalize === 'function') payload = target.normalize(payload);
                let payloadToWrite = payload;
                if (target.name === 'latest' && !hasUsableBotLabRows(payloadToWrite)) {
                    payloadToWrite = resolveBotLabCachedPayload('latest') || payloadToWrite;
                } else if (target.name === 'history' && !hasUsableBotLabRows(payloadToWrite)) {
                    payloadToWrite = resolveBotLabCachedPayload('history', { limit: 20 }) || payloadToWrite;
                } else if (target.name === 'discord-summary' && (!payloadToWrite || typeof payloadToWrite !== 'object' || !payloadToWrite.status)) {
                    payloadToWrite = resolveBotLabCachedPayload('discord-summary') || payloadToWrite;
                }
                writeJsonCache(target.file, payloadToWrite);
                results.push({ name: target.name, ok: true });
            } catch (error) {
                results.push({ name: target.name, ok: false, error: error.message || 'unavailable' });
            }
        }
        return results;
    })();
    try {
        return await botLabCacheRefreshInFlight;
    } finally {
        botLabCacheRefreshInFlight = null;
    }
}

function n(v, fallback = 0) {
    const x = Number(v);
    return Number.isFinite(x) ? x : fallback;
}

function parseIsoMs(value) {
    if (!value) return null;
    const ms = Date.parse(String(value));
    return Number.isFinite(ms) ? ms : null;
}

function telemetryAgeMs(iso) {
    const ts = parseIsoMs(iso);
    if (!Number.isFinite(ts)) return null;
    return Math.max(0, Date.now() - ts);
}

function resolveOpenProfitValue(profile, balance, equity) {
    const reportedOpen = Number(profile?.openProfit);
    const openPositions = n(profile?.openPositions, 0);
    const eqDiff = (Number.isFinite(balance) && Number.isFinite(equity))
        ? Number((equity - balance).toFixed(2))
        : null;
    if (openPositions <= 0) return 0;
    if (!Number.isFinite(eqDiff)) {
        return Number.isFinite(reportedOpen) ? reportedOpen : 0;
    }
    if (!Number.isFinite(reportedOpen)) return eqDiff;
    if (Math.abs(reportedOpen) < 0.01 && Math.abs(eqDiff) >= 0.01) return eqDiff;
    if (Math.abs(reportedOpen - eqDiff) > 50) return eqDiff;
    return reportedOpen;
}

function recoverSnapshotFunds(profile) {
    const events = Array.isArray(profile?.recentEvents) ? profile.recentEvents : [];
    for (let i = events.length - 1; i >= 0; i -= 1) {
        const text = String(events[i]?.text || '');
        if (!text.includes('ACCOUNT_SNAPSHOT')) continue;
        const balanceMatch = text.match(/Balance=([0-9.+-]+)/i);
        const equityMatch = text.match(/Equity=([0-9.+-]+)/i);
        const profitMatch = text.match(/Profit=([0-9.+-]+)/i);
        const balance = balanceMatch ? Number(balanceMatch[1]) : null;
        const equity = equityMatch ? Number(equityMatch[1]) : null;
        const profit = profitMatch ? Number(profitMatch[1]) : null;
        return {
            balance: Number.isFinite(balance) ? balance : null,
            equity: Number.isFinite(equity) ? equity : null,
            profit: Number.isFinite(profit) ? profit : null
        };
    }
    return { balance: null, equity: null, profit: null };
}

function isTrustedLiveBalanceSource(value) {
    const source = String(value || '').trim();
    return source === 'mt5-probe-live' || source === 'mt5-probe-standby-zero';
}

function getMotherboardConfig(_sourceRaw) {
    return {
        source: 'vds',
        telemetryUrl: MOTHERBOARD_VDS_TELEMETRY_URL,
        telemetryUrls: MOTHERBOARD_VDS_TELEMETRY_URLS,
        dashboardUrl: MOTHERBOARD_VDS_DASHBOARD_URL,
        chartsUrl: MOTHERBOARD_VDS_CHARTS_URL
    };
}

function newestIso(values) {
    let best = null;
    for (const value of values) {
        const ms = Date.parse(value || '');
        if (!Number.isFinite(ms)) continue;
        if (!best || ms > best.ms) best = { ms, value };
    }
    return best?.value || new Date().toISOString();
}

function combineLiveBotPayloads(payloads, cfg) {
    const usable = payloads.filter((payload) => payload && payload.ok);
    if (usable.length <= 1) return usable[0] || null;
    const profiles = usable.flatMap((payload) => Array.isArray(payload.profiles) ? payload.profiles : []);
    const copierRows = usable.flatMap((payload) => Array.isArray(payload.copierFeed?.rows) ? payload.copierFeed.rows : []);
    const generatedAt = newestIso(usable.map((payload) => payload.generatedAt));
    const sum = (selector) => Number(usable.reduce((total, payload) => total + Number(selector(payload) || 0), 0).toFixed(2));
    const baselineFor = (row) => {
        const raw = row?.accountStartEquity ?? row?.depositAmount ?? row?.dayStartEquity;
        const n = Number(raw);
        return Number.isFinite(n) && n > 0 ? n : 0;
    };
    const dayBaseline = profiles.reduce((total, row) => total + baselineFor(row), 0);
    const lifetimeMatched = profiles.reduce((total, row) => total + Number(row?.lifetimeMatchedCloses || 0), 0);
    const lifetimeWinsApprox = profiles.reduce((total, row) => {
        const matched = Number(row?.lifetimeMatchedCloses || 0);
        const wr = Number(row?.lifetimeWinRatePct);
        return total + (matched > 0 && Number.isFinite(wr) ? (matched * wr / 100) : 0);
    }, 0);
    const lifetimeNet = sum((payload) => payload.summary?.lifetimeNetUsd);
    const dayNet = sum((payload) => payload.summary?.dayNetUsd);
    const monthNet = sum((payload) => payload.summary?.monthNetUsd);
    const openProfit = sum((payload) => payload.summary?.openProfitUsd);
    return {
        ok: true,
        generatedAt,
        stale: usable.some((payload) => payload.stale),
        staleReason: usable.find((payload) => payload.staleReason)?.staleReason || null,
        degraded: usable.some((payload) => payload.degraded),
        degradedReason: usable.find((payload) => payload.degradedReason)?.degradedReason || null,
        telemetryAgeSec: Math.max(...usable.map((payload) => Number(payload.telemetryAgeSec || 0))),
        source: {
            node: cfg?.source || 'vds',
            telemetryUrl: cfg?.telemetryUrl || null,
            telemetryUrls: cfg?.telemetryUrls || [],
            dashboardUrl: cfg?.dashboardUrl || null
        },
        diagnostics: {
            upstreams: usable.map((payload) => ({
                telemetryUrl: payload?.source?.telemetryUrl || null,
                generatedAt: payload?.generatedAt || null,
                profilesTotal: payload?.summary?.profilesTotal || 0,
                stale: !!payload?.stale
            })),
            rawProfilesTotal: profiles.length,
            visibleProfilesTotal: profiles.length,
            trustedProfilesTotal: profiles.filter((row) => row.balanceSource === 'mt5-probe-live' || row.balanceSource === 'mt5-probe-standby-zero').length
        },
        summary: {
            profilesTotal: profiles.length,
            openPositions: sum((payload) => payload.summary?.openPositions),
            openOrders: sum((payload) => payload.summary?.openOrders),
            dayNetUsd: dayNet,
            dayReturnPct: dayBaseline > 0 ? Number(((100 * dayNet) / dayBaseline).toFixed(2)) : null,
            weekNetUsd: sum((payload) => payload.summary?.weekNetUsd),
            weekReturnPct: null,
            monthNetUsd: monthNet,
            monthReturnPct: dayBaseline > 0 ? Number(((100 * monthNet) / dayBaseline).toFixed(2)) : null,
            openProfitUsd: openProfit,
            lifetimeNetUsd: lifetimeNet,
            lifetimeReturnPct: dayBaseline > 0 ? Number(((100 * lifetimeNet) / dayBaseline).toFixed(2)) : null,
            lifetimeMatchedCloses: lifetimeMatched,
            lifetimeWinRatePct: lifetimeMatched > 0 ? Number(((100 * lifetimeWinsApprox) / lifetimeMatched).toFixed(2)) : null,
            lifetimeProfitFactor: null
        },
        profiles: profiles.sort((a, b) => Number(b.dayNetUsd || 0) - Number(a.dayNetUsd || 0)),
        copierFeed: {
            generatedAt,
            columns: usable.find((payload) => Array.isArray(payload.copierFeed?.columns) && payload.copierFeed.columns.length)?.copierFeed.columns || [],
            rows: copierRows
        }
    };
}

function shapeLiveBotPayload(raw, cfg) {
    const telemetry = raw?.telemetry || raw || {};
    const copierFeedRaw = raw?.copierFeed || telemetry?.copierFeed || null;
    const generatedAt = telemetry.generatedAt || new Date().toISOString();
    const ageMs = telemetryAgeMs(generatedAt);
    const isStale = Number.isFinite(ageMs) ? ageMs > MOTHERBOARD_TELEMETRY_MAX_AGE_MS : false;
    const vdsHideNameParts = ['BASE', 'PRESET', 'LAB', 'DOMINION', 'EDGE', 'SURGE', 'FRESH', 'BRAND_NEW', 'COPIER_NEW', 'COPIER_CLEAN', 'TF_SETUP'];
    const shouldHideVdsProfile = (nameRaw) => {
        const name = String(nameRaw || '').trim().toUpperCase();
        if (!name) return true;
        if (name.endsWith(':BASE') || name.endsWith(':PRESETS')) return true;
        return vdsHideNameParts.some((part) => name.includes(part));
    };
    const profilesRaw = Array.isArray(telemetry.profiles) ? telemetry.profiles : [];
    const visibleProfiles = cfg?.source === 'vds'
        ? profilesRaw.filter((p) => !shouldHideVdsProfile(p?.profile || p?.profileLabel))
        : profilesRaw;
    const trustedProfiles = visibleProfiles.filter((profile) => isTrustedLiveBalanceSource(profile?.balanceSource));
    const useFallbackProfiles = false;
    const profiles = cfg?.source === 'vds'
        ? visibleProfiles.map((profile) => {
            const hasExactFunds = Number.isFinite(Number(profile?.currentBalance)) || Number.isFinite(Number(profile?.currentEquity));
            const source = String(profile?.balanceSource || '').trim();
            const keepLiveSource = source === 'mt5-probe-live' || source === 'mt5-probe-standby-zero' || source === 'derived';
            if (!hasExactFunds || keepLiveSource) return profile;
            return { ...profile, balanceSource: 'snapshot' };
        })
        : visibleProfiles;
    const summary = telemetry.summary || {};
    const day = summary.day || {};
    const week = summary.week || {};

    let rows = profiles
        .map((p) => {
            const dayMetrics = p?.metrics?.day || {};
            const weekMetrics = p?.metrics?.week || {};
            const monthMetrics = p?.metrics?.month || {};
            const lifetimeMetrics = p?.metrics?.lifetime || {};
            const totalMetrics = p?.metrics?.total || {};
            const status = p?.metrics?.status || {};
            let balance = Number.isFinite(Number(p.currentBalance)) ? Number(p.currentBalance) : null;
            let equity = Number.isFinite(Number(p.currentEquity)) ? Number(p.currentEquity) : null;
            let depositAmount = Number.isFinite(Number(p.depositAmount)) ? Number(p.depositAmount)
                : (Number.isFinite(Number(p.deposit)) ? Number(p.deposit)
                    : (Number.isFinite(Number(p.depositStartEq)) ? Number(p.depositStartEq)
                        : (Number.isFinite(Number(p.depositStartingEq)) ? Number(p.depositStartingEq) : null)));
            let withdrawAmount = Number.isFinite(Number(p.withdrawAmount)) ? Number(p.withdrawAmount)
                : (Number.isFinite(Number(p.withdraw)) ? Number(p.withdraw)
                    : (Number.isFinite(Number(p.withdrawUsd)) ? Number(p.withdrawUsd)
                        : (Number.isFinite(Number(p.withdrawalUsd)) ? Number(p.withdrawalUsd)
                            : (Number.isFinite(Number(p.withdrawalsUsd)) ? Number(p.withdrawalsUsd) : null))));
            const cashflowSource = String(p.cashflowSource || '').trim() || null;
            const cashflowLedgerChannel = String(p.cashflowLedgerChannel || '').trim() || null;
            const cashflowLedgerFetchedAt = p.cashflowLedgerFetchedAt || null;
            const cashflowLedgerNote = String(p.cashflowLedgerNote || '').trim() || null;
            let accountStartEquity = Number.isFinite(Number(p.accountStartEquity)) ? Number(p.accountStartEquity) : null;
            if (cashflowSource === 'missing') {
                depositAmount = null;
                withdrawAmount = null;
                accountStartEquity = null;
            }
            if (cashflowSource === 'ledger') {
                if ((!Number.isFinite(depositAmount) || depositAmount <= 0) && Number.isFinite(accountStartEquity) && accountStartEquity > 0) {
                    depositAmount = accountStartEquity;
                }
                if (!Number.isFinite(depositAmount) || depositAmount <= 0) {
                    depositAmount = null;
                }
                if (!Number.isFinite(withdrawAmount) || withdrawAmount <= 0) {
                    withdrawAmount = null;
                }
            }
            if (cfg?.source !== 'vds' && !Number.isFinite(depositAmount) && Number.isFinite(accountStartEquity) && accountStartEquity > 0) {
                depositAmount = accountStartEquity;
            }
            const balanceSource = String(p.balanceSource || '').trim();
            if (balanceSource === 'mt5-probe-live' && (!Number.isFinite(balance) || !Number.isFinite(equity) || (balance === 0 && equity === 0))) {
                const recovered = recoverSnapshotFunds(p);
                if (Number.isFinite(recovered.balance) && recovered.balance > 0) balance = recovered.balance;
                if (Number.isFinite(recovered.equity) && recovered.equity > 0) equity = recovered.equity;
            }
            const liveFundsAnchor = Math.max(
                Number.isFinite(balance) ? balance : 0,
                Number.isFinite(equity) ? equity : 0,
            );
            const maxReasonableLiveBaseline = liveFundsAnchor > 0 ? liveFundsAnchor * 5 : 0;
            if (balanceSource === 'mt5-probe-live' && maxReasonableLiveBaseline > 0) {
                if (Number.isFinite(depositAmount) && depositAmount > maxReasonableLiveBaseline) depositAmount = null;
                if (Number.isFinite(accountStartEquity) && accountStartEquity > maxReasonableLiveBaseline) {
                    accountStartEquity = Number.isFinite(depositAmount) ? depositAmount : null;
                }
            }
            let dayStart = Number(p.dayStartEquity ?? p.dayStartBalance ?? dayMetrics.equityBaseline);
            const baselineFallback = Number.isFinite(accountStartEquity) && accountStartEquity > 0
                ? accountStartEquity
                : (Number.isFinite(depositAmount) && depositAmount > 0 ? depositAmount : null);
            if (!Number.isFinite(dayStart) || dayStart <= 0) {
                dayStart = Number.isFinite(baselineFallback)
                    ? baselineFallback
                    : (liveFundsAnchor > 0 ? liveFundsAnchor : null);
            }
            if (Number.isFinite(dayStart) && dayStart > 0) {
                const cap = Math.max(equity * 1.8, Number.isFinite(baselineFallback) ? Number(baselineFallback) * 1.8 : 0);
                if (cap > 0 && dayStart > cap) {
                    dayStart = Number.isFinite(baselineFallback)
                        ? baselineFallback
                        : (liveFundsAnchor > 0 ? liveFundsAnchor : equity);
                }
            }
            if (balanceSource === 'mt5-probe-live' && maxReasonableLiveBaseline > 0 && Number.isFinite(dayStart) && dayStart > maxReasonableLiveBaseline) {
                dayStart = Number.isFinite(baselineFallback) ? baselineFallback : (liveFundsAnchor > 0 ? liveFundsAnchor : null);
            }
            if (balanceSource === 'derived') {
                const sanityBaseline = Math.max(
                    Number.isFinite(accountStartEquity) ? accountStartEquity : 0,
                    Number.isFinite(depositAmount) ? depositAmount : 0,
                    Number.isFinite(dayStart) ? dayStart : 0
                );
                const maxReasonable = sanityBaseline > 0 ? sanityBaseline * 5 : 0;
                if (maxReasonable > 0) {
                    if (Number.isFinite(balance) && balance > maxReasonable) balance = null;
                    if (Number.isFinite(equity) && equity > maxReasonable) equity = null;
                }
            }
            const hasEquity = Number.isFinite(equity);
            let liveDayFromEq = (hasEquity && Number.isFinite(dayStart) && dayStart > 0)
                ? Number((equity - dayStart).toFixed(2))
                : null;
            if (Number.isFinite(withdrawAmount) && Number.isFinite(liveDayFromEq) && liveDayFromEq < 0 && Math.abs(liveDayFromEq) <= (withdrawAmount + 75)) {
                liveDayFromEq = Number((liveDayFromEq + withdrawAmount).toFixed(2));
            }
            const liveDayPctFromEq = (Number.isFinite(dayStart) && dayStart > 0 && Number.isFinite(liveDayFromEq))
                ? Number(((100 * liveDayFromEq) / dayStart).toFixed(2))
                : null;
            // Keep Day P/L as realized daily performance; Open P/L is displayed separately.
            const dayNet = Number.isFinite(Number(dayMetrics.netUsd))
                ? Number(dayMetrics.netUsd)
                : (Number.isFinite(Number(dayMetrics.netUsdLive))
                    ? Number(dayMetrics.netUsdLive)
                    : (Number.isFinite(liveDayFromEq) ? liveDayFromEq : 0));
            const dayRet = Number.isFinite(Number(dayMetrics.returnPct))
                ? Number(dayMetrics.returnPct)
                : (Number.isFinite(Number(dayMetrics.returnPctLive))
                    ? Number(dayMetrics.returnPctLive)
                    : (Number.isFinite(liveDayPctFromEq) ? liveDayPctFromEq : null));
            const openProfit = resolveOpenProfitValue(p, balance, equity);
            const totalBaseline = Number.isFinite(accountStartEquity) && accountStartEquity > 0
                ? accountStartEquity
                : (Number.isFinite(depositAmount) && depositAmount > 0 ? depositAmount : (balanceSource === 'mt5-probe-live' && liveFundsAnchor > 0 ? liveFundsAnchor : null));
            const totalNetCashflow = (hasEquity && Number.isFinite(totalBaseline) && totalBaseline > 0)
                ? Number((equity + n(withdrawAmount, 0) - totalBaseline).toFixed(2))
                : null;
            const totalPctCashflow = (Number.isFinite(totalBaseline) && totalBaseline > 0 && Number.isFinite(totalNetCashflow))
                ? Number(((100 * totalNetCashflow) / totalBaseline).toFixed(2))
                : null;
            const conservativeLiveMetrics = balanceSource !== 'mt5-probe-live';
            const rawDayNet = Number.isFinite(Number(dayNet)) ? Number(dayNet) : null;
            const rawDayRet = Number.isFinite(Number(dayRet)) ? Number(dayRet) : null;
            const rawWeekNet = Number.isFinite(Number(weekMetrics.netUsd)) ? Number(weekMetrics.netUsd) : null;
            const rawWeekRet = Number.isFinite(Number(weekMetrics.returnPct)) ? Number(weekMetrics.returnPct) : null;
            const rawMonthNet = Number.isFinite(Number(monthMetrics.netUsd)) ? Number(monthMetrics.netUsd) : null;
            const rawMonthRet = Number.isFinite(Number(monthMetrics.returnPct)) ? Number(monthMetrics.returnPct) : null;
            const rawLifetimeNet = Number.isFinite(Number(lifetimeMetrics.netUsd)) ? Number(lifetimeMetrics.netUsd) : null;
            const rawLifetimeRet = Number.isFinite(Number(lifetimeMetrics.returnPct)) ? Number(lifetimeMetrics.returnPct) : null;
            const rawStoredTotalNet = Number.isFinite(Number(p.totalNetUsd)) ? Number(p.totalNetUsd) : (Number.isFinite(Number(totalMetrics.netUsd)) ? Number(totalMetrics.netUsd) : null);
            const rawStoredTotalRet = Number.isFinite(Number(p.totalReturnPct)) ? Number(p.totalReturnPct) : (Number.isFinite(Number(totalMetrics.returnPct)) ? Number(totalMetrics.returnPct) : null);
            const liveMetricSanityCap = liveFundsAnchor > 0 ? liveFundsAnchor * 5 : 0;
            const mt5RawDayLooksBroken = (
                balanceSource === 'mt5-probe-live'
                && liveMetricSanityCap > 0
                && Number.isFinite(rawDayNet)
                && Math.abs(rawDayNet) > liveMetricSanityCap
            );
            const mt5RawTotalLooksBroken = (
                balanceSource === 'mt5-probe-live'
                && liveMetricSanityCap > 0
                && (
                    (Number.isFinite(rawLifetimeNet) && Math.abs(rawLifetimeNet) > liveMetricSanityCap)
                    || (Number.isFinite(rawStoredTotalNet) && Math.abs(rawStoredTotalNet) > liveMetricSanityCap)
                )
            );
            const safeDayNet = (conservativeLiveMetrics || mt5RawDayLooksBroken)
                ? (Number.isFinite(liveDayFromEq) ? liveDayFromEq : rawDayNet)
                : rawDayNet;
            const safeDayRet = (conservativeLiveMetrics || mt5RawDayLooksBroken)
                ? (Number.isFinite(liveDayPctFromEq) ? liveDayPctFromEq : rawDayRet)
                : rawDayRet;
            const safeWeekNet = conservativeLiveMetrics
                ? (Number.isFinite(totalNetCashflow) ? totalNetCashflow : rawWeekNet)
                : rawWeekNet;
            const safeWeekRet = conservativeLiveMetrics
                ? (Number.isFinite(totalPctCashflow) ? totalPctCashflow : rawWeekRet)
                : rawWeekRet;
            const safeMonthNet = conservativeLiveMetrics
                ? (Number.isFinite(totalNetCashflow) ? totalNetCashflow : rawMonthNet)
                : rawMonthNet;
            const safeMonthRet = conservativeLiveMetrics
                ? (Number.isFinite(totalPctCashflow) ? totalPctCashflow : rawMonthRet)
                : rawMonthRet;
            const safeLifetimeNet = conservativeLiveMetrics
                ? (Number.isFinite(totalNetCashflow) ? totalNetCashflow : rawLifetimeNet)
                : rawLifetimeNet;
            const safeLifetimeRet = conservativeLiveMetrics
                ? (Number.isFinite(totalPctCashflow) ? totalPctCashflow : rawLifetimeRet)
                : rawLifetimeRet;
            return {
                profile: p.profile,
                profileLabel: p.profileLabel || p.profile,
                accountName: p.accountName || null,
                account: p.account || null,
                onlineHint: Boolean(p.onlineHint),
                balanceSource: balanceSource || null,
                riskPct: p.riskPct ?? null,
                leverage: p.leverage || null,
                leverageSource: p.leverageSource || null,
                depositAmount,
                withdrawAmount,
                cashflowSource,
                cashflowLedgerChannel,
                cashflowLedgerFetchedAt,
                cashflowLedgerNote,
                accountStartEquity,
                dayStartAt: p.dayStartAt || p.dayOpeningAt || null,
                dayStartBalance: Number.isFinite(Number(p.dayStartBalance)) ? Number(p.dayStartBalance) : null,
                dayStartEquity: Number.isFinite(Number(p.dayStartEquity)) ? Number(p.dayStartEquity) : null,
                balance,
                equity,
                openProfit,
                currentPnlGross: Number.isFinite(Number(p.currentPnlGross)) ? Number(p.currentPnlGross) : null,
                currentPnlWithOpen: Number.isFinite(Number(p.currentPnlWithOpen)) ? Number(p.currentPnlWithOpen) : null,
                dayNetUsd: safeDayNet,
                dayReturnPct: safeDayRet,
                weekNetUsd: safeWeekNet,
                weekReturnPct: safeWeekRet,
                monthNetUsd: safeMonthNet,
                monthReturnPct: safeMonthRet,
                lifetimeNetUsd: safeLifetimeNet,
                lifetimeReturnPct: safeLifetimeRet,
                lifetimeMatchedCloses: Number.isFinite(Number(lifetimeMetrics.matchedCloses)) ? Number(lifetimeMetrics.matchedCloses) : 0,
                lifetimeWinRatePct: Number.isFinite(Number(lifetimeMetrics.winRatePct)) ? Number(lifetimeMetrics.winRatePct) : null,
                lifetimeProfitFactor: Number.isFinite(Number(lifetimeMetrics.profitFactor)) ? Number(lifetimeMetrics.profitFactor) : null,
                totalNetUsd: Number.isFinite(totalNetCashflow)
                    ? totalNetCashflow
                    : (mt5RawTotalLooksBroken
                        ? 0
                        : (Number.isFinite(rawStoredTotalNet)
                    ? rawStoredTotalNet
                    : (Number.isFinite(Number(totalMetrics.netUsd))
                        ? Number(totalMetrics.netUsd)
                        : (Number.isFinite(Number(p.currentEquity)) && Number.isFinite(Number(p.accountStartEquity))
                            ? Number((Number(p.currentEquity) - Number(p.accountStartEquity)).toFixed(2))
                            : null)))),
                totalReturnPct: Number.isFinite(totalPctCashflow)
                    ? totalPctCashflow
                    : (mt5RawTotalLooksBroken
                        ? 0
                        : (Number.isFinite(rawStoredTotalRet)
                    ? rawStoredTotalRet
                    : (Number.isFinite(Number(totalMetrics.returnPct))
                        ? Number(totalMetrics.returnPct)
                        : (Number.isFinite(Number(p.currentEquity)) && Number.isFinite(Number(p.accountStartEquity)) && Number(p.accountStartEquity) > 0
                            ? Number(((100 * (Number(p.currentEquity) - Number(p.accountStartEquity))) / Number(p.accountStartEquity)).toFixed(2))
                            : null)))),
                status: status.label || 'UNKNOWN',
                statusReason: status.reason || '',
                recentEvents: Array.isArray(p.recentEvents) ? p.recentEvents.slice(-40) : [],
                dailyBuckets: Array.isArray(p.dailyBuckets) ? p.dailyBuckets : [],
                recentClosedDeals: Array.isArray(p.recentClosedDeals) ? p.recentClosedDeals.slice(0, 600) : [],
                journal: Array.isArray(p.journal) ? p.journal.slice(0, 120) : [],
                history: Array.isArray(p.history) ? p.history.slice(-160) : [],
                executorVersion: p.executorVersion || null,
                journalTelemetry: typeof p.journalTelemetry === 'boolean' ? p.journalTelemetry : null,
                exposureSwitches: typeof p.exposureSwitches === 'boolean' ? p.exposureSwitches : null,
                updatedAt: p.lastActivityAt || p.snapshotAt || p.lastSyncAt || telemetry.generatedAt || null
            };
        })
        .sort((a, b) => b.dayNetUsd - a.dayNetUsd);


    const summaryDayNetUsd = rows.reduce((a, r) => a + n(r.dayNetUsd, 0), 0);
    const summaryOpenProfitUsd = rows.reduce((a, r) => a + n(r.openProfit, 0), 0);
    const summaryMonthNetUsd = rows.reduce((a, r) => a + n(r.monthNetUsd, 0), 0);
    const summaryMonthBaseline = rows.reduce((a, r) => {
        const b = Number(r.accountStartEquity ?? r.depositAmount);
        return a + (Number.isFinite(b) && b > 0 ? b : 0);
    }, 0);
    const summaryLifetimeNetUsd = rows.reduce((a, r) => a + n(r.lifetimeNetUsd, 0), 0);
    const summaryLifetimeMatched = rows.reduce((a, r) => a + n(r.lifetimeMatchedCloses, 0), 0);
    const summaryLifetimeWinsApprox = rows.reduce((a, r) => {
        const matched = n(r.lifetimeMatchedCloses, 0);
        const winRate = Number(r.lifetimeWinRatePct);
        if (matched <= 0 || !Number.isFinite(winRate)) return a;
        return a + ((matched * winRate) / 100);
    }, 0);
    const summaryLifetimeGrossProfit = rows.reduce((a, r) => {
        const pf = Number(r.lifetimeProfitFactor);
        const net = Number(r.lifetimeNetUsd);
        if (!Number.isFinite(pf) || !Number.isFinite(net) || pf <= 0) return a;
        if (net >= 0) {
            const grossLoss = pf > 1 ? net / (pf - 1) : 0;
            return a + Math.max(0, net + grossLoss);
        }
        return a;
    }, 0);
    const summaryLifetimeGrossLoss = rows.reduce((a, r) => {
        const pf = Number(r.lifetimeProfitFactor);
        const net = Number(r.lifetimeNetUsd);
        if (!Number.isFinite(pf) || !Number.isFinite(net) || pf <= 0) return a;
        if (net >= 0 && pf > 1) return a + Math.max(0, net / (pf - 1));
        if (net < 0) return a + Math.abs(net);
        return a;
    }, 0);
    const summaryLifetimeBaseline = rows.reduce((a, r) => {
        const b = Number(r.accountStartEquity ?? r.depositAmount);
        return a + (Number.isFinite(b) && b > 0 ? b : 0);
    }, 0);
    const summaryDayBaseline = rows.reduce((a, r) => {
        const b = Number(r.dayStartEquity ?? r.dayStartBalance ?? r.accountStartEquity);
        return a + (Number.isFinite(b) && b > 0 ? b : 0);
    }, 0);
    const summaryDayReturnPct = summaryDayBaseline > 0
        ? Number(((100 * summaryDayNetUsd) / summaryDayBaseline).toFixed(2))
        : null;

    return {
        ok: true,
        generatedAt,
        stale: isStale,
        staleReason: isStale ? 'telemetry_stale' : null,
        degraded: useFallbackProfiles,
        degradedReason: useFallbackProfiles ? 'no_trusted_live_balance_profiles' : null,
        telemetryAgeSec: Number.isFinite(ageMs) ? Math.round(ageMs / 1000) : null,
        source: {
            node: cfg?.source || 'vds',
            telemetryUrl: cfg?.telemetryUrl || null,
            dashboardUrl: cfg?.dashboardUrl || null
        },
        diagnostics: {
            rawProfilesTotal: profilesRaw.length,
            visibleProfilesTotal: visibleProfiles.length,
            trustedProfilesTotal: trustedProfiles.length,
            runtimeDriftProfiles: n(summary.runtimeDriftProfiles, 0),
            profilesWithSync: n(summary.profilesWithSync, 0)
        },
        summary: {
            profilesTotal: rows.length,
            openPositions: n(summary.totalOpenPositions, 0),
            openOrders: n(summary.totalOpenOrders, 0),
            dayNetUsd: Number(summaryDayNetUsd.toFixed(2)),
            dayReturnPct: summaryDayReturnPct,
            weekNetUsd: n(week.netUsd, 0),
            weekReturnPct: Number.isFinite(Number(week.returnPct)) ? Number(week.returnPct) : null,
            monthNetUsd: Number(summaryMonthNetUsd.toFixed(2)),
            monthReturnPct: summaryMonthBaseline > 0 ? Number(((100 * summaryMonthNetUsd) / summaryMonthBaseline).toFixed(2)) : null,
            openProfitUsd: Number(summaryOpenProfitUsd.toFixed(2)),
            lifetimeNetUsd: Number(summaryLifetimeNetUsd.toFixed(2)),
            lifetimeReturnPct: summaryLifetimeBaseline > 0 ? Number(((100 * summaryLifetimeNetUsd) / summaryLifetimeBaseline).toFixed(2)) : null,
            lifetimeMatchedCloses: summaryLifetimeMatched,
            lifetimeWinRatePct: summaryLifetimeMatched > 0 ? Number(((100 * summaryLifetimeWinsApprox) / summaryLifetimeMatched).toFixed(2)) : null,
            lifetimeProfitFactor: summaryLifetimeGrossLoss > 0 ? Number((summaryLifetimeGrossProfit / summaryLifetimeGrossLoss).toFixed(3)) : null
        },
        profiles: rows,
        copierFeed: {
            generatedAt: copierFeedRaw?.generatedAt || (telemetry.generatedAt || new Date().toISOString()),
            columns: Array.isArray(copierFeedRaw?.columns) ? copierFeedRaw.columns : [],
            rows: Array.isArray(copierFeedRaw?.rows) ? copierFeedRaw.rows : []
        }
    };
}

// POST /validate: read body ourselves and tolerate bad chars (MT5 broker names etc.) so we never throw SyntaxError
app.use((req, res, next) => {
    if (req.method !== 'POST' || (req.path !== '/validate' && req.originalUrl.split('?')[0] !== '/validate')) return next();
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
        const raw = Buffer.concat(chunks);
        req.rawBody = raw;
        let str = raw.toString('utf8');
        try {
            req.body = JSON.parse(str);
            next();
            return;
        } catch (e) {
            // Strip control chars; replace non-printable ASCII with space so JSON parses (MT5 can send bad bytes)
            const sanitized = str.replace(/[\x00-\x1f]/g, ' ').replace(/[^\x20-\x7e]/g, ' ');
            try {
                req.body = JSON.parse(sanitized);
                console.log('[validate] Body parsed after stripping control chars (len=' + raw.length + ')');
                next();
                return;
            } catch (e2) {
                console.error('[validate] JSON parse failed. len=', str.length, 'around pos 90:', JSON.stringify(str.slice(70, 115)), 'charCode(90)=', str.length > 90 ? str.charCodeAt(90) : 'n/a');
                res.status(400).json({ valid: false, error: 'Invalid JSON', message: e2.message });
            }
        }
    });
    req.on('error', (err) => { next(err); });
});

// Parse JSON for all other routes - capture raw body for debugging
app.use((req, res, next) => {
    if (req.method === 'POST' && (req.path === '/validate' || req.originalUrl.split('?')[0] === '/validate')) return next();
    express.json({
        type: ['application/json', 'text/plain', 'text/json', '*/*'],
        strict: false,
        verify: (req, res, buf) => { req.rawBody = buf; }
    })(req, res, next);
});

// Serve admin.html
app.get('/admin.html', (req, res) => {
    res.sendFile(path.join(__dirname, 'admin.html'));
});

const publicDir = path.join(__dirname, 'public');
const servePublicPage = (fileName) => (req, res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    res.sendFile(path.join(publicDir, fileName));
};

function registerPublicPage(route, fileName) {
    const handler = servePublicPage(fileName);
    const normalized = String(route || '/').replace(/\/+$/, '') || '/';
    const routes = normalized === '/'
        ? ['/', '/index.html']
        : [normalized, `${normalized}/`, `${normalized}.html`];
    app.get(routes, handler);
}

// Serve marketing site pages
registerPublicPage('/', 'index.html');
registerPublicPage('/bots', 'bots.html');
registerPublicPage('/live-feed', 'live-feed.html');
registerPublicPage('/bot-lab', 'bot-lab.html');
registerPublicPage('/copy-trading', 'copy-trading.html');
registerPublicPage('/setup-guide', 'setup-guide.html');
registerPublicPage('/pricing', 'pricing.html');
registerPublicPage('/checkout', 'checkout.html');
registerPublicPage('/faq', 'faq.html');
registerPublicPage('/contact', 'contact.html');

// Serve V2 preview page (safe sandbox for edits)
app.get('/v2', (req, res) => {
    res.sendFile(path.join(__dirname, 'index_v2.html'));
});

// Serve setup guide
app.get('/setup', (req, res) => {
    res.sendFile(path.join(__dirname, 'setup.html'));
});

//+------------------------------------------------------------------+
//| Load Licenses from File (restore from .backup if main missing)    |
//+------------------------------------------------------------------+
async function loadLicenses() {
    const backupPath = LICENSE_FILE + '.backup';
    const tryLoad = async (filePath) => {
        const data = await fs.readFile(filePath, 'utf8');
        const obj = JSON.parse(data);
        if (!obj || !Array.isArray(obj.licenses)) return null;
        return obj;
    };
    try {
        return await tryLoad(LICENSE_FILE);
    } catch (_) {}
    try {
        const obj = await tryLoad(backupPath);
        if (obj) {
            await fs.writeFile(LICENSE_FILE, JSON.stringify(obj, null, 2), 'utf8');
            return obj;
        }
    } catch (_) {}
    const defaultLicenses = { licenses: [], lastUpdated: new Date().toISOString() };
    try { await saveLicenses(defaultLicenses); } catch (e) { /* ignore */ }
    return defaultLicenses;
}

//+------------------------------------------------------------------+
//| Save Licenses to File (and .backup so redeploy can restore)       |
//+------------------------------------------------------------------+
async function saveLicenses(licenses) {
    const json = JSON.stringify(licenses, null, 2);
    await fs.writeFile(LICENSE_FILE, json, 'utf8');
    try { await fs.writeFile(LICENSE_FILE + '.backup', json, 'utf8'); } catch (e) { /* ignore */ }
}

function normalizeAllowedBrokers(value) {
    if (!value) return [];
    if (Array.isArray(value)) {
        return value.map((broker) => String(broker).trim()).filter(Boolean);
    }
    if (typeof value === 'string') {
        return value
            .split(',')
            .map((broker) => broker.trim())
            .filter(Boolean);
    }
    return [];
}

function buildLicenseEntry(input) {
    const accountNumber = String(input.accountNumber || '').trim();
    const userName = String(input.userName || 'Unknown').trim();
    const eaName = String(input.eaName || '').trim();
    const expiryDate = input.expiryDate ? String(input.expiryDate).trim() : null;
    const allowedBrokers = normalizeAllowedBrokers(input.allowedBrokers);
    const licenseKey = input.licenseKey ? String(input.licenseKey).trim() : '';

    if (!accountNumber || !eaName) {
        return { error: 'accountNumber and eaName are required' };
    }

    return {
        entry: {
            id: crypto.randomBytes(16).toString('hex'),
            accountNumber: accountNumber,
            userName: userName || 'Unknown',
            eaName: eaName,
            expiryDate: expiryDate || null,
            allowedBrokers: allowedBrokers,
            licenseKey: licenseKey || generateLicenseHash(accountNumber, 'any', expiryDate),
            isActive: true,
            createdAt: new Date().toISOString(),
            lastValidated: null
        }
    };
}

//+------------------------------------------------------------------+
//| Load Copier Subscribers (restore from .backup if main missing)    |
//+------------------------------------------------------------------+
async function loadCopierSubscribers() {
    const backupPath = COPIER_SUBSCRIBERS_FILE + '.backup';
    try {
        const data = await fs.readFile(COPIER_SUBSCRIBERS_FILE, 'utf8');
        return JSON.parse(data);
    } catch (_) {}
    try {
        const data = await fs.readFile(backupPath, 'utf8');
        const obj = JSON.parse(data);
        await fs.writeFile(COPIER_SUBSCRIBERS_FILE, data, 'utf8');
        return obj;
    } catch (_) {}
    const defaultSubscribers = { subscribers: [], lastUpdated: new Date().toISOString() };
    await saveCopierSubscribers(defaultSubscribers);
    return defaultSubscribers;
}

//+------------------------------------------------------------------+
//| Save Copier Subscribers (and .backup for restore on redeploy)     |
//+------------------------------------------------------------------+
async function saveCopierSubscribers(subscribers) {
    const json = JSON.stringify(subscribers, null, 2);
    await fs.writeFile(COPIER_SUBSCRIBERS_FILE, json, 'utf8');
    try { await fs.writeFile(COPIER_SUBSCRIBERS_FILE + '.backup', json, 'utf8'); } catch (e) { /* ignore */ }
}

async function loadCheckoutOrders() {
    const backupPath = CHECKOUT_ORDERS_FILE + '.backup';
    try {
        const data = await fs.readFile(CHECKOUT_ORDERS_FILE, 'utf8');
        return JSON.parse(data);
    } catch (_) {}
    try {
        const data = await fs.readFile(backupPath, 'utf8');
        const obj = JSON.parse(data);
        await fs.writeFile(CHECKOUT_ORDERS_FILE, data, 'utf8');
        return obj;
    } catch (_) {}
    const defaults = { orders: [], lastUpdated: new Date().toISOString() };
    await saveCheckoutOrders(defaults);
    return defaults;
}

async function saveCheckoutOrders(data) {
    const json = JSON.stringify(data, null, 2);
    await fs.writeFile(CHECKOUT_ORDERS_FILE, json, 'utf8');
    try { await fs.writeFile(CHECKOUT_ORDERS_FILE + '.backup', json, 'utf8'); } catch (e) { /* ignore */ }
}

function resolveEaNameForPlan(planKey, botVersion) {
    const v = String(botVersion || '').toLowerCase();
    const pick = (goldName, silverName) => (v.includes('silver') ? silverName : goldName);
    if (planKey.startsWith('blueprint_')) return pick('Goldmine Blueprint – Gold', 'Goldmine Blueprint – Silver');
    if (planKey.startsWith('nexus_')) return pick('Goldmine Nexus – Gold', 'Goldmine Nexus – Silver');
    if (planKey.startsWith('dominion_')) return 'Goldmine Dominion';
    if (planKey === 'add_seat') return 'Goldmine Blueprint – Gold';
    return '';
}

async function activateOrderLicense(order, override = {}) {
    const accountNumber = String(override.accountNumber || order.accountNumber || '').trim();
    const plan = String(order.plan || '').trim();
    const botVersion = override.botVersion || order.botVersion || '';
    const eaName = String(override.eaName || order.eaName || resolveEaNameForPlan(plan, botVersion)).trim();
    if (!accountNumber || !eaName) {
        return { ok: false, reason: 'missing_account_or_ea' };
    }

    const licenses = await loadLicenses();
    const existing = licenses.licenses.find((l) => String(l.accountNumber).trim() === accountNumber && normalizeEaName(l.eaName) === normalizeEaName(eaName));
    if (existing) return { ok: true, created: false, license: existing };

    const build = buildLicenseEntry({
        accountNumber,
        userName: order.name || 'Website Buyer',
        eaName,
        expiryDate: null,
        allowedBrokers: [],
        licenseKey: ''
    });
    if (build.error) return { ok: false, reason: build.error };
    licenses.licenses.push(build.entry);
    licenses.lastUpdated = new Date().toISOString();
    await saveLicenses(licenses);
    return { ok: true, created: true, license: build.entry };
}

function verifyCoinbaseWebhook(req) {
    if (!COINBASE_WEBHOOK_SHARED_SECRET) return true;
    const sig = req.headers['x-cc-webhook-signature'];
    if (!sig || !req.rawBody) return false;
    const expected = crypto.createHmac('sha256', COINBASE_WEBHOOK_SHARED_SECRET).update(req.rawBody).digest('hex');
    return sig === expected;
}

//+------------------------------------------------------------------+
//| Generate License Hash (for validation)                           |
//+------------------------------------------------------------------+
function generateLicenseHash(accountNumber, broker, expiry) {
    const data = `${accountNumber}-${broker}-${expiry}-${SECRET_KEY}`;
    return crypto.createHash('sha256').update(data).digest('hex');
}

//+------------------------------------------------------------------+
//| Validate License Request                                         |
//+------------------------------------------------------------------+
async function validateLicense(accountNumber, broker, licenseKey, eaName) {
    const data = await loadLicenses();
    const list = Array.isArray(data.licenses) ? data.licenses : [];
    const accountStr = String(accountNumber ?? '').trim();
    const eaNameTrimmed = String(eaName ?? '').trim();
    const eaCandidates = getEaNameCandidates(eaNameTrimmed);
    
    // Find license: match account (string comparison) + active + EA name in same group
    const license = list.find(l => 
        String(l.accountNumber ?? '').trim() === accountStr && 
        l.isActive === true &&
        (eaCandidates.includes(l.eaName) || (l.eaName && eaCandidates.some(c => normalizeEaName(c) === normalizeEaName(String(l.eaName)))))
    );
    
    if (!license) {
        // Log why lookup failed so you can fix it (e.g. empty file after deploy, wrong account/eaName)
        const accountNumbers = [...new Set(list.map(l => String(l.accountNumber ?? '').trim()).filter(Boolean))];
        console.error(`[LICENSE] No license found. Account: "${accountStr}" EA: "${eaNameTrimmed}" | Total licenses in file: ${list.length} | Active for this account: ${list.filter(l => String(l.accountNumber ?? '').trim() === accountStr).length} | Account IDs in file (sample): ${accountNumbers.slice(0, 5).join(', ')}`);
        return {
            valid: false,
            reason: 'Account not licensed',
            message: `Account ${accountNumber} is not licensed for ${eaName}`
        };
    }
    
    // Check broker restriction (if set)
    if (license.allowedBrokers && license.allowedBrokers.length > 0) {
        const brokerAllowed = license.allowedBrokers.some(b => 
            broker.toLowerCase().includes(b.toLowerCase())
        );
        if (!brokerAllowed) {
            return {
                valid: false,
                reason: 'Broker not authorized',
                message: `Broker '${broker}' is not authorized for this license`
            };
        }
    }
    
    // Check expiry
    if (license.expiryDate) {
        const expiry = new Date(license.expiryDate);
        const now = new Date();
        if (now > expiry) {
            return {
                valid: false,
                reason: 'License expired',
                message: `License expired on ${license.expiryDate}`,
                expiryDate: license.expiryDate
            };
        }
    }
    
    // Validate license key (if provided)
    if (licenseKey && license.licenseKey) {
        if (licenseKey !== license.licenseKey) {
            return {
                valid: false,
                reason: 'Invalid license key',
                message: 'License key does not match'
            };
        }
    }
    
    // License is valid
    return {
        valid: true,
        accountNumber: license.accountNumber,
        userName: license.userName || 'Unknown',
        expiryDate: license.expiryDate || null,
        daysRemaining: license.expiryDate ? 
            Math.ceil((new Date(license.expiryDate) - new Date()) / (1000 * 60 * 60 * 24)) : 
            null,
        message: 'License valid'
    };
}

//+------------------------------------------------------------------+
//| Coinbase Commerce Checkout                                       |
//+------------------------------------------------------------------+
const CHECKOUT_PLANS = {
    // Goldmine bot licenses (website checkout dropdown)
    blueprint_single_full: {
        name: 'Blueprint - 1 Version Full Pay',
        amount: 5000,
        description: 'Blueprint license (Gold OR Silver) - full pay'
    },
    blueprint_single_installment: {
        name: 'Blueprint - 1 Version Installments',
        amount: 5600,
        description: 'Blueprint license (Gold OR Silver) - 3-month installment total'
    },
    blueprint_bundle_full: {
        name: 'Blueprint - Bundle Full Pay',
        amount: 8000,
        description: 'Blueprint bundle (Gold + Silver) - full pay'
    },
    blueprint_bundle_installment: {
        name: 'Blueprint - Bundle Installments',
        amount: 8600,
        description: 'Blueprint bundle (Gold + Silver) - 3-month installment total'
    },
    blueprint_20_full: {
        name: 'Blueprint 20',
        amount: 5000,
        description: 'Blueprint 20 license - full pay'
    },
    nexus_single_full: {
        name: 'Nexus - 1 Version Full Pay',
        amount: 5000,
        description: 'Nexus license (Gold OR Silver) - full pay'
    },
    nexus_single_installment: {
        name: 'Nexus - 1 Version Installments',
        amount: 5600,
        description: 'Nexus license (Gold OR Silver) - 3-month installment total'
    },
    nexus_bundle_full: {
        name: 'Nexus - Bundle Full Pay',
        amount: 8000,
        description: 'Nexus bundle (Gold + Silver) - full pay'
    },
    nexus_bundle_installment: {
        name: 'Nexus - Bundle Installments',
        amount: 8600,
        description: 'Nexus bundle (Gold + Silver) - 3-month installment total'
    },
    dominion_single_full: {
        name: 'Dominion - 1 Version Full Pay',
        amount: 5000,
        description: 'Dominion license (Gold OR Silver) - full pay'
    },
    dominion_single_installment: {
        name: 'Dominion - 1 Version Installments',
        amount: 5600,
        description: 'Dominion license (Gold OR Silver) - 3-month installment total'
    },
    dominion_bundle_full: {
        name: 'Dominion - Bundle Full Pay',
        amount: 8000,
        description: 'Dominion bundle (Gold + Silver) - full pay'
    },
    dominion_bundle_installment: {
        name: 'Dominion - Bundle Installments',
        amount: 8600,
        description: 'Dominion bundle (Gold + Silver) - 3-month installment total'
    },
    add_seat: {
        name: 'Additional Account Seat',
        amount: 1999,
        description: 'Additional active MT5 account seat'
    },
    // Legacy aliases (backward compatibility)
    goldmine_blueprint_gold: { name: 'Legacy Blueprint Gold', amount: 5000, description: 'Legacy mapped: Blueprint one-version full pay' },
    goldmine_blueprint_silver: { name: 'Legacy Blueprint Silver', amount: 5000, description: 'Legacy mapped: Blueprint one-version full pay' },
    goldmine_nexus_gold: { name: 'Legacy Nexus Gold', amount: 5000, description: 'Legacy mapped: Nexus one-version full pay' },
    goldmine_nexus_silver: { name: 'Legacy Nexus Silver', amount: 5000, description: 'Legacy mapped: Nexus one-version full pay' },
    goldmine_dominion: { name: 'Legacy Dominion', amount: 5000, description: 'Legacy mapped: Dominion one-version full pay' },
    // Copier subscriptions (monthly)
    copier_option_a: {
        name: 'Copytrading $1k-$3k - excluding VDS',
        amount: 250,
        description: 'Copytrading service for $1k-$3k balances, excluding VDS - monthly',
        recurring: true
    },
    copier_option_b: {
        name: 'Copytrading $1k-$3k - including VDS',
        amount: 280,
        description: 'Copytrading service for $1k-$3k balances, including VDS - monthly',
        recurring: true
    },
    copier_3k_10k_no_vds: {
        name: 'Copytrading $3k-$10k - excluding VDS',
        amount: 500,
        description: 'Copytrading service for $3k-$10k balances, excluding VDS - monthly',
        recurring: true
    },
    copier_3k_10k_with_vds: {
        name: 'Copytrading $3k-$10k - including VDS',
        amount: 530,
        description: 'Copytrading service for $3k-$10k balances, including VDS - monthly',
        recurring: true
    },
    // Legacy
    advanced_scalper_1: {
        name: 'Advanced Scalper 1',
        amount: 2000,
        description: 'Bot license - Advanced Scalper 1'
    },
    advanced_scalper_2: {
        name: 'Advanced Scalper 2.0',
        amount: 3000,
        description: 'Bot license - Advanced Scalper 2.0'
    },
    fxgoldtraderplugsmc: {
        name: 'FXGOLDTRADERPLUGSMC',
        amount: 5000,
        description: 'Bot license - FXGOLDTRADERPLUGSMC'
    }
};

function createCoinbaseCharge(chargeData) {
    return new Promise((resolve, reject) => {
        const payload = JSON.stringify(chargeData);
        const request = https.request(
            {
                hostname: 'api.commerce.coinbase.com',
                path: '/charges',
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(payload),
                    'X-CC-Api-Key': COINBASE_COMMERCE_API_KEY,
                    'X-CC-Version': '2018-03-22'
                },
                timeout: 25000
            },
            (response) => {
                let body = '';
                response.on('data', (chunk) => {
                    body += chunk;
                });
                response.on('end', () => {
                    let parsed;
                    try {
                        parsed = JSON.parse(body);
                    } catch (error) {
                        return reject(new Error('Invalid response from Coinbase Commerce'));
                    }
                    if (response.statusCode < 200 || response.statusCode >= 300) {
                        return reject(new Error(parsed.error?.message || 'Coinbase Commerce error'));
                    }
                    resolve(parsed);
                });
            }
        );

        request.on('timeout', () => {
            request.destroy(new Error('Coinbase Commerce request timed out'));
        });
        request.on('error', reject);
        request.write(payload);
        request.end();
    });
}

function getMailer() {
    if (!SMTP_USER || !SMTP_PASS) {
        return null;
    }
    return nodemailer.createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_SECURE,
        connectionTimeout: 25000,
        greetingTimeout: 25000,
        socketTimeout: 25000,
        auth: {
            user: SMTP_USER,
            pass: SMTP_PASS
        }
    });
}

function isSameUtcMonth(dateA, dateB) {
    return (
        dateA.getUTCFullYear() === dateB.getUTCFullYear() &&
        dateA.getUTCMonth() === dateB.getUTCMonth()
    );
}

function getInvoiceEmailContent({ subscriber, planInfo, hostedUrl, chargeId }) {
    const invoiceMonth = new Date().toLocaleString('en-US', {
        month: 'long',
        year: 'numeric',
        timeZone: 'UTC'
    });
    const amount = `$${planInfo.amount.toFixed(2)}`;
    const subject = `GOLDMINE copier invoice - ${planInfo.name} (${invoiceMonth})`;
    const text = [
        `Hello ${subscriber.name || 'Trader'},`,
        '',
        `Your ${planInfo.name} subscription invoice is ready.`,
        `Amount: ${amount} USD (paid in crypto via Coinbase Commerce).`,
        '',
        `Pay here: ${hostedUrl}`,
        '',
        'Notes:',
        '- MT5-only copier service',
        '- Returns are paid in USDT',
        '- No guaranteed returns. Subscription refunded if service fails.',
        '',
        `Invoice ID: ${chargeId || 'n/a'}`,
        '',
        'Thank you,',
        'GOLDMINE'
    ].join('\n');
    return { subject, text };
}

async function sendInvoiceEmail({ subscriber, planInfo, hostedUrl, chargeId }) {
    const { subject, text } = getInvoiceEmailContent({ subscriber, planInfo, hostedUrl, chargeId });

    // Option 1: Resend (no Gmail/app passwords – just API key; use resend.com)
    if (RESEND_API_KEY) {
        try {
            const { Resend } = require('resend');
            const resend = new Resend(RESEND_API_KEY);
            const from = RESEND_FROM_EMAIL.includes('<') ? RESEND_FROM_EMAIL : `GOLDMINE <${RESEND_FROM_EMAIL}>`;
            const { data, error } = await resend.emails.send({
                from,
                to: subscriber.email,
                subject,
                text
            });
            if (error) {
                throw new Error(error.message || 'Resend send failed');
            }
            return;
        } catch (err) {
            if (err.code === 'MODULE_NOT_FOUND' || (err.message && err.message.includes('Cannot find module'))) {
                console.error('Resend package not installed. Add "resend" to package.json, run npm install, and redeploy.');
                throw new Error('Resend is configured but the resend package is not installed. Redeploy after adding resend to package.json.');
            }
            console.error('Resend invoice send error:', err.message);
            throw err;
        }
    }

    // Option 2: SMTP (Gmail, Mailgun, SendGrid, Outlook, etc.)
    const mailer = getMailer();
    if (!mailer) {
        throw new Error('Neither Resend nor SMTP is configured. Set RESEND_API_KEY or SMTP_USER/SMTP_PASS.');
    }
    await mailer.sendMail({
        from: SMTP_FROM ? `${SMTP_FROM_NAME} <${SMTP_FROM}>` : SMTP_FROM_NAME,
        to: subscriber.email,
        subject,
        text
    });
}

async function runCopierInvoiceJob({ force = false, subscriberId = null } = {}) {
    const subscribersData = await loadCopierSubscribers();
    const subscribers = subscribersData.subscribers || [];
    const now = new Date();
    const results = [];

    if (!COINBASE_COMMERCE_API_KEY) {
        return { ok: false, error: 'Coinbase Commerce is not configured', results };
    }

    for (const subscriber of subscribers) {
        if (subscriberId && subscriber.id !== subscriberId) {
            continue;
        }

        if (subscriber.isActive === false) {
            continue;
        }

        const planInfo = CHECKOUT_PLANS[subscriber.plan];
        if (!planInfo || !planInfo.recurring) {
            continue;
        }

        const lastInvoicedAt = subscriber.lastInvoicedAt ? new Date(subscriber.lastInvoicedAt) : null;
        if (!force && lastInvoicedAt && isSameUtcMonth(lastInvoicedAt, now)) {
            continue;
        }

        try {
            const baseUrl = normalizeBaseUrl(PUBLIC_BASE_URL);
            console.log('Copier invoice started:', {
                subscriberId: subscriber.id,
                email: subscriber.email,
                plan: subscriber.plan
            });

            let charge;
            try {
                charge = await createCoinbaseCharge({
                    name: planInfo.name,
                    description: planInfo.description,
                    pricing_type: 'fixed_price',
                    local_price: { amount: planInfo.amount.toFixed(2), currency: 'USD' },
                    redirect_url: baseUrl ? `${baseUrl}/#checkout` : undefined,
                    cancel_url: baseUrl ? `${baseUrl}/#checkout` : undefined,
                    metadata: {
                        subscriberId: subscriber.id,
                        customerName: subscriber.name || '',
                        customerEmail: subscriber.email || '',
                        accountSize: subscriber.accountSize || '',
                        contact: subscriber.contact || '',
                        plan: subscriber.plan
                    }
                });
            } catch (coinbaseErr) {
                console.error('Copier invoice: Coinbase charge failed:', coinbaseErr.message);
                throw new Error('Coinbase: ' + (coinbaseErr.message || 'Connection timeout'));
            }

            const hostedUrl = charge?.data?.hosted_url;
            const chargeId = charge?.data?.id;
            if (!hostedUrl) {
                throw new Error('Coinbase Commerce charge missing hosted URL');
            }

            try {
                await sendInvoiceEmail({ subscriber, planInfo, hostedUrl, chargeId });
            } catch (emailErr) {
                console.error('Copier invoice: Email send failed:', emailErr.message);
                throw new Error('Email: ' + (emailErr.message || 'Connection timeout'));
            }
            console.log('Copier invoice sent:', {
                subscriberId: subscriber.id,
                email: subscriber.email,
                chargeId: chargeId
            });

            subscriber.lastInvoicedAt = now.toISOString();
            subscriber.lastChargeId = chargeId || null;
            subscriber.lastInvoiceStatus = 'sent';
            subscriber.lastInvoiceError = null;

            results.push({ id: subscriber.id, status: 'sent' });
        } catch (error) {
            subscriber.lastInvoiceStatus = 'failed';
            subscriber.lastInvoiceError = error.message;
            console.error('Copier invoice error:', {
                subscriberId: subscriber.id,
                email: subscriber.email,
                plan: subscriber.plan,
                error: error.message
            });
            results.push({ id: subscriber.id, status: 'failed', error: error.message });
        }
    }

    subscribersData.lastUpdated = new Date().toISOString();
    await saveCopierSubscribers(subscribersData);

    return { ok: true, results };
}

//+------------------------------------------------------------------+
//| API Endpoints                                                     |
//+------------------------------------------------------------------+

// Health check
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Public live bot feed (proxied from motherboard so website can consume over HTTPS)
app.get('/api/bots/live', async (req, res) => {
    const cfg = getMotherboardConfig(req.query.source);
    const cacheKey = cfg.source;
    try {
        const now = Date.now();
        const cached = botFeedCache.bySource.get(cacheKey);
        if (cached?.payload && (now - cached.ts) < 5000) {
            return res.json(cached.payload);
        }
        const urls = Array.isArray(cfg.telemetryUrls) && cfg.telemetryUrls.length ? cfg.telemetryUrls : [cfg.telemetryUrl];
        const shaped = await Promise.all(urls.map(async (telemetryUrl) => {
            const raw = await fetchJsonWithTimeout(withCacheBust(telemetryUrl), 15000);
            return shapeLiveBotPayload(raw, { ...cfg, telemetryUrl });
        }));
        const payload = combineLiveBotPayloads(shaped, cfg) || shaped[0];
        botFeedCache.bySource.set(cacheKey, { ts: now, payload });
        res.json(payload);
    } catch (error) {
        const stale = botFeedCache.bySource.get(cacheKey)?.payload;
        if (stale) {
            return res.status(200).json({
                ...stale,
                stale: true,
                staleReason: error.message || 'motherboard_unreachable'
            });
        }
        res.status(502).json({
            ok: false,
            error: 'live_feed_unavailable',
            message: error.message || 'Could not reach motherboard telemetry',
            source: cfg.source
        });
    }
});

app.get('/api/fxg/client-dashboard-public', async (req, res) => {
    try {
        const upstream = await fetch('https://fxg-client-dashboard-production.up.railway.app/api/dashboard', {
            headers: { Accept: 'application/json' }
        });
        const text = await upstream.text();
        res.setHeader('Content-Type', 'application/json; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.status(upstream.status).send(text);
    } catch (error) {
        res.status(502).json({
            ok: false,
            error: 'fxg_dashboard_unavailable',
            message: error.message || 'Could not reach FXG client dashboard'
        });
    }
});

app.get('/api/bot-lab/latest', async (req, res) => {
    try {
        const payload = normalizeBotLabPayload(await fetchJsonWithTimeout(withCacheBust(BOT_LAB_API_URL), 15000));
        const payloadToWrite = hasUsableBotLabRows(payload) ? payload : (resolveBotLabCachedPayload('latest') || payload);
        writeJsonCache(BOT_LAB_LATEST_CACHE_FILE, payloadToWrite);
        res.json({ ok: true, source: BOT_LAB_API_URL, payload: payloadToWrite });
    } catch (error) {
        const cached = resolveBotLabCachedPayload('latest');
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab unavailable', source: BOT_LAB_API_URL });
    }
});

app.get('/api/bot-lab/history', async (req, res) => {
    try {
        const limit = Math.max(1, Math.min(50, Number(req.query.limit || 12)));
        const joiner = BOT_LAB_HISTORY_URL.includes('?') ? '&' : '?';
        const url = `${BOT_LAB_HISTORY_URL}${joiner}limit=${limit}`;
        const payload = normalizeBotLabPayload(await fetchJsonWithTimeout(withCacheBust(url), 15000));
        const payloadToWrite = hasUsableBotLabRows(payload) ? payload : (resolveBotLabCachedPayload('history', { limit }) || payload);
        writeJsonCache(BOT_LAB_HISTORY_CACHE_FILE, payloadToWrite);
        res.json({ ok: true, source: BOT_LAB_HISTORY_URL, payload: payloadToWrite });
    } catch (error) {
        const cached = resolveBotLabCachedPayload('history', { limit: Math.max(1, Math.min(50, Number(req.query.limit || 12))) });
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_history_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab history unavailable', source: BOT_LAB_HISTORY_URL });
    }
});

app.get('/api/bot-lab/analysis', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_ANALYSIS_URL), 20000);
        writeJsonCache(BOT_LAB_ANALYSIS_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_ANALYSIS_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_ANALYSIS_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_analysis_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab analysis unavailable', source: BOT_LAB_ANALYSIS_URL });
    }
});

app.get('/api/bot-lab/catalog', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_CATALOG_URL), 15000);
        writeJsonCache(BOT_LAB_CATALOG_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_CATALOG_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_CATALOG_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_catalog_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab catalog unavailable', source: BOT_LAB_CATALOG_URL });
    }
});

app.get('/api/bot-lab/progress', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_PROGRESS_URL), 20000);
        writeJsonCache(BOT_LAB_PROGRESS_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_PROGRESS_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_PROGRESS_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_progress_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab progress unavailable', source: BOT_LAB_PROGRESS_URL });
    }
});

app.get('/api/bot-lab/discord-summary', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_DISCORD_SUMMARY_URL), 20000);
        const payloadToWrite = (payload && typeof payload === 'object' && payload.status) ? payload : (resolveBotLabCachedPayload('discord-summary') || payload);
        writeJsonCache(BOT_LAB_DISCORD_SUMMARY_CACHE_FILE, payloadToWrite);
        res.json({ ok: true, source: BOT_LAB_DISCORD_SUMMARY_URL, payload: payloadToWrite });
    } catch (error) {
        const cached = resolveBotLabCachedPayload('discord-summary');
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_discord_summary_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab discord summary unavailable', source: BOT_LAB_DISCORD_SUMMARY_URL });
    }
});

app.get('/api/bot-lab/recommendations', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_RECOMMENDATIONS_URL), 20000);
        writeJsonCache(BOT_LAB_RECOMMENDATIONS_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_RECOMMENDATIONS_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_RECOMMENDATIONS_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_recommendations_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab recommendations unavailable', source: BOT_LAB_RECOMMENDATIONS_URL });
    }
});

app.get('/api/bot-lab/schedule', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_SCHEDULE_URL), 20000);
        writeJsonCache(BOT_LAB_SCHEDULE_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_SCHEDULE_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_SCHEDULE_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'bot_lab_schedule_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab schedule unavailable', source: BOT_LAB_SCHEDULE_URL });
    }
});

app.get('/api/param-sweep/status', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_SWEEP_STATUS_URL), 20000);
        writeJsonCache(BOT_LAB_SWEEP_STATUS_CACHE_FILE, payload);
        res.json({ ok: true, source: BOT_LAB_SWEEP_STATUS_URL, payload });
    } catch (error) {
        const cached = readJsonCache(BOT_LAB_SWEEP_STATUS_CACHE_FILE);
        if (cached) {
            return res.status(200).json({ ok: true, source: 'cache', stale: true, staleReason: error.message || 'param_sweep_status_unavailable', payload: cached });
        }
        res.status(502).json({ ok: false, error: error.message || 'Param sweep status unavailable', source: BOT_LAB_SWEEP_STATUS_URL });
    }
});

// Public live charts feed (proxied from motherboard live chart API)
app.get('/api/bots/charts', async (req, res) => {
    const cfg = getMotherboardConfig(req.query.source || 'vds');
    try {
        const symbolsRaw = String(req.query.symbols || 'XAUUSD,XAGUSD');
        const limit = Math.max(30, Math.min(320, Number(req.query.limit || 180)));
        const key = `${cfg.source}|${symbolsRaw}|${limit}`;
        const now = Date.now();
        const cached = botChartCache.bySourceKey.get(key);
        if (cached && (now - cached.ts) < 4000) {
            return res.json(cached.payload);
        }

        const q = new URLSearchParams({ symbols: symbolsRaw, limit: String(limit) });
        const url = withCacheBust(`${cfg.chartsUrl}?${q.toString()}`);
        const raw = await fetchJsonWithTimeout(url, 15000);
        const payload = {
            ok: true,
            generatedAt: raw?.generatedAt || new Date().toISOString(),
            source: {
                node: cfg.source,
                chartsUrl: cfg.chartsUrl,
                dashboardUrl: cfg.dashboardUrl
            },
            charts: Array.isArray(raw?.charts) ? raw.charts : []
        };
        botChartCache.bySourceKey.set(key, { ts: now, payload });
        res.json(payload);
    } catch (error) {
        const symbolsRaw = String(req.query.symbols || 'XAUUSD,XAGUSD');
        const limit = Math.max(30, Math.min(320, Number(req.query.limit || 180)));
        const key = `${cfg.source}|${symbolsRaw}|${limit}`;
        const stale = botChartCache.bySourceKey.get(key)?.payload || null;
        if (stale) {
            return res.status(200).json({
                ...stale,
                stale: true,
                staleReason: error.message || 'motherboard_chart_unreachable'
            });
        }
        res.status(502).json({
            ok: false,
            error: 'live_chart_unavailable',
            message: error.message || 'Could not reach motherboard chart feed',
            source: cfg.source
        });
    }
});

// Public VDS chart snapshots (exact motherboard terminal captures)
app.get('/api/bots/vds-snapshots', async (req, res) => {
    try {
        const base = MOTHERBOARD_VDS_DASHBOARD_URL.replace(/\/+$/,'');
        const maxSnapshotAgeMs = 15 * 60 * 1000;
        const nowMs = Date.now();
        const [snapRaw, teleRaw] = await Promise.all([
            fetchJsonWithTimeout(`${base}/api/snapshots/terminal`, 15000),
            fetchJsonWithTimeout(MOTHERBOARD_VDS_TELEMETRY_URL, 15000)
        ]);

        const isFreshSnapshot = (snapshot) => {
            const updatedMs = Date.parse(snapshot?.updatedAt || '');
            return Number.isFinite(updatedMs) && ((nowMs - updatedMs) <= maxSnapshotAgeMs);
        };
        const snapList = (Array.isArray(snapRaw?.snapshots) ? snapRaw.snapshots : [])
            .filter((snapshot) => snapshot?.account && isFreshSnapshot(snapshot));
        const snapByAcct = new Map(snapList.map((s) => [String(s?.account || ''), s]));

        const telemetry = teleRaw?.telemetry || teleRaw || {};
        const profiles = Array.isArray(telemetry?.profiles) ? telemetry.profiles : [];
        const ranked = profiles
            .map((p) => {
                const day = p?.metrics?.day || {};
                const pnl = Number(day.netUsdLive ?? day.netUsd ?? 0);
                return {
                    account: String(p?.account || ''),
                    profile: p?.profile || '',
                    profileLabel: p?.profileLabel || p?.profile || '',
                    botName: p?.botName || '',
                    symbols: p?.symbols || '',
                    riskPct: Number.isFinite(Number(p?.riskPct)) ? Number(p.riskPct) : null,
                    dayNetUsd: Number.isFinite(pnl) ? pnl : 0
                };
            })
            .filter((r) => r.account)
            .sort((a, b) => {
                const labelA = String(a.profileLabel || a.profile || a.account || '');
                const labelB = String(b.profileLabel || b.profile || b.account || '');
                return labelA.localeCompare(labelB) || String(a.account).localeCompare(String(b.account));
            });

        const matched = ranked
            .map((r) => ({ s: snapByAcct.get(r.account), r }))
            .filter(({ s }) => Boolean(s));
        const rotationWindowMs = 30 * 1000;
        const offset = matched.length > 0 ? Math.floor(Date.now() / rotationWindowMs) % matched.length : 0;
        const picked = matched.length <= 2
            ? matched
            : [matched[offset], matched[(offset + 1) % matched.length]];

        const snapshots = picked.slice(0, 2).map(({ s, r }, i) => ({
            index: i,
            account: s?.account || null,
            profile: r?.profile || null,
            profileLabel: r?.profileLabel || null,
            botName: r?.botName || null,
            symbols: r?.symbols || null,
            riskPct: r?.riskPct ?? null,
            dayNetUsd: r?.dayNetUsd ?? null,
            title: s?.title || null,
            updatedAt: s?.updatedAt || null,
            imageUrl: `/api/bots/vds-snapshot-image?path=${encodeURIComponent(String(s?.url || ''))}`
        }));

        res.json({ ok: true, source: 'vds', count: snapshots.length, snapshots });
    } catch (error) {
        res.status(502).json({ ok: false, error: 'vds_snapshots_unavailable', message: error.message || 'Could not reach VDS snapshots' });
    }
});

app.get('/api/bots/vds-snapshot-image', async (req, res) => {
    try {
        const p = String(req.query.path || '');
        if (!p.startsWith('/snapshots/')) return res.status(400).json({ ok: false, error: 'invalid_path' });
        const target = `${MOTHERBOARD_VDS_DASHBOARD_URL.replace(/\/+$/,'')}${p}`;
        const response = await fetch(target, { headers: { Accept: 'image/*' } });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const ct = response.headers.get('content-type') || 'image/png';
        const buf = Buffer.from(await response.arrayBuffer());
        res.setHeader('Content-Type', ct);
        res.setHeader('Cache-Control', 'no-store');
        res.status(200).send(buf);
    } catch (error) {
        res.status(502).json({ ok: false, error: 'vds_snapshot_image_unavailable', message: error.message || 'Could not fetch snapshot image' });
    }
});

// Public config (support email for mailto links and checkout error message)
app.get('/api/config', (req, res) => {
    res.json({
        supportEmail: SUPPORT_EMAIL || 'goldminebotsltd@gmail.com'
    });
});

// Create Coinbase Commerce checkout
app.post('/api/coinbase/charge', async (req, res) => {
    try {
        if (!COINBASE_COMMERCE_API_KEY) {
            return res.status(503).json({ error: 'Coinbase Commerce is not configured' });
        }

        let body = req.body;
        if (Buffer.isBuffer(body)) {
            try {
                body = JSON.parse(body.toString('utf8'));
            } catch (error) {
                return res.status(400).json({ error: 'Invalid JSON payload' });
            }
        } else if (typeof body === 'string') {
            try {
                body = JSON.parse(body);
            } catch (error) {
                // Leave as-is if already parsed
            }
        }

        const { name, email, plan, accountSize, contact, accountNumber, botVersion, eaName } = body || {};
        if (!name || !email || !plan) {
            return res.status(400).json({ error: 'Name, email, and plan are required' });
        }

        const planInfo = CHECKOUT_PLANS[plan];
        if (!planInfo) {
            return res.status(400).json({ error: 'Invalid plan selection' });
        }

        const amount = planInfo.amount.toFixed(2);
        const description = planInfo.description;
        const protocol = req.headers['x-forwarded-proto'] || req.protocol || 'http';
        const baseUrl = PUBLIC_BASE_URL || `${protocol}://${req.get('host')}`;

        const charge = await createCoinbaseCharge({
            name: planInfo.name,
            description: description,
            pricing_type: 'fixed_price',
            local_price: { amount, currency: 'USD' },
            redirect_url: `${baseUrl}/#checkout`,
            cancel_url: `${baseUrl}/#checkout`,
            metadata: {
                customerName: name,
                customerEmail: email,
                accountSize: accountSize || '',
                contact: contact || '',
                plan: plan,
                accountNumber: String(accountNumber || '').trim(),
                botVersion: String(botVersion || '').trim(),
                eaName: String(eaName || '').trim()
            }
        });

        const orders = await loadCheckoutOrders();
        orders.orders.push({
            id: charge?.data?.id || crypto.randomBytes(8).toString('hex'),
            status: 'created',
            createdAt: new Date().toISOString(),
            name,
            email,
            plan,
            accountSize: accountSize || '',
            contact: contact || '',
            accountNumber: String(accountNumber || '').trim(),
            botVersion: String(botVersion || '').trim(),
            eaName: String(eaName || '').trim(),
            hostedUrl: charge?.data?.hosted_url || ''
        });
        orders.lastUpdated = new Date().toISOString();
        await saveCheckoutOrders(orders);

        res.json({
            hostedUrl: charge?.data?.hosted_url,
            chargeId: charge?.data?.id
        });
    } catch (error) {
        console.error('Coinbase checkout error:', error.message);
        const message = error.message || 'Failed to create Coinbase checkout';
        res.status(500).json({ error: message });
    }
});

// Coinbase webhook: confirms payment, then auto-activates if account number exists.
app.post('/api/coinbase/webhook', async (req, res) => {
    try {
        if (!verifyCoinbaseWebhook(req)) {
            return res.status(401).json({ error: 'Invalid webhook signature' });
        }
        const event = req.body?.event || req.body || {};
        const eventType = String(event.type || '').toLowerCase();
        const charge = event.data || {};
        const chargeId = charge.id;
        if (!chargeId) return res.status(200).json({ ok: true, ignored: 'missing_charge_id' });

        const orders = await loadCheckoutOrders();
        const order = orders.orders.find((o) => o.id === chargeId);
        if (!order) return res.status(200).json({ ok: true, ignored: 'order_not_found' });

        const paid = ['charge:confirmed', 'charge:resolved', 'charge:completed'].includes(eventType);
        if (!paid) {
            order.status = eventType || 'webhook_received';
            order.updatedAt = new Date().toISOString();
            orders.lastUpdated = new Date().toISOString();
            await saveCheckoutOrders(orders);
            return res.status(200).json({ ok: true, status: order.status });
        }

        order.status = 'paid';
        order.updatedAt = new Date().toISOString();

        const activation = await activateOrderLicense(order);
        if (activation.ok) {
            order.activationStatus = 'activated';
            order.activatedAt = new Date().toISOString();
            order.licenseId = activation.license?.id || null;
        } else {
            order.activationStatus = 'pending_account';
        }

        orders.lastUpdated = new Date().toISOString();
        await saveCheckoutOrders(orders);
        return res.status(200).json({ ok: true, activationStatus: order.activationStatus });
    } catch (error) {
        console.error('Coinbase webhook error:', error.message);
        return res.status(500).json({ error: 'Webhook processing failed' });
    }
});

// Customer can submit MT5 account later to complete pending activation.
app.post('/api/activation/submit-account', async (req, res) => {
    try {
        const { chargeId, email, accountNumber, botVersion, eaName } = req.body || {};
        const account = String(accountNumber || '').trim();
        if (!chargeId || !email || !account) {
            return res.status(400).json({ error: 'chargeId, email, and accountNumber are required' });
        }

        const orders = await loadCheckoutOrders();
        const order = orders.orders.find((o) => o.id === String(chargeId).trim() && String(o.email || '').toLowerCase() === String(email).trim().toLowerCase());
        if (!order) return res.status(404).json({ error: 'Order not found' });

        order.accountNumber = account;
        if (botVersion) order.botVersion = String(botVersion).trim();
        if (eaName) order.eaName = String(eaName).trim();

        const activation = await activateOrderLicense(order, { accountNumber: account, botVersion, eaName });
        if (!activation.ok) {
            order.activationStatus = 'pending_account';
            orders.lastUpdated = new Date().toISOString();
            await saveCheckoutOrders(orders);
            return res.status(400).json({ error: activation.reason || 'Activation failed' });
        }

        order.activationStatus = 'activated';
        order.activatedAt = new Date().toISOString();
        order.licenseId = activation.license?.id || null;
        orders.lastUpdated = new Date().toISOString();
        await saveCheckoutOrders(orders);
        return res.json({ success: true, activationStatus: 'activated', licenseId: order.licenseId });
    } catch (error) {
        console.error('Submit account activation error:', error.message);
        res.status(500).json({ error: 'Failed to activate order' });
    }
});

// Validate license
app.post('/validate', async (req, res) => {
    try {
        // Parse body - handle both JSON and raw Buffer from MQL5
        let body = req.body;
        if (Buffer.isBuffer(body)) {
            try {
                body = JSON.parse(body.toString('utf8'));
            } catch (e) {
                console.error('Failed to parse body:', e);
                return res.status(400).json({
                    valid: false,
                    error: 'Invalid JSON',
                    message: 'Could not parse request body as JSON'
                });
            }
        } else if (typeof body === 'string') {
            try {
                body = JSON.parse(body);
            } catch (e) {
                // Already parsed or invalid
            }
        }
        // If body is empty or missing fields, try parsing raw body (MT5 sometimes sends so express.json() leaves body empty)
        if ((!body || typeof body !== 'object' || (!body.accountNumber && !body.account) || !body.broker || !body.eaName) && req.rawBody && req.rawBody.length > 0) {
            try {
                const raw = req.rawBody.toString('utf8');
                body = JSON.parse(raw);
                console.log('[validate] Parsed body from rawBody (len=' + req.rawBody.length + ')');
            } catch (e) {
                console.error('[validate] Raw body parse failed:', e.message, 'first 200 chars:', String(req.rawBody.slice(0, 200)));
            }
        }
        body = body || {};
        // Accept "account" as alias for "accountNumber" (some EAs send account)
        const accountNumber = (body.accountNumber != null ? String(body.accountNumber) : (body.account != null ? String(body.account) : '')).trim();
        const broker = (body.broker != null ? String(body.broker) : '').trim();
        const eaName = (body.eaName != null ? String(body.eaName) : '').trim();
        const licenseKey = (body.licenseKey != null ? String(body.licenseKey) : '').trim();
        
        // Log incoming request for debugging
        console.log(`[${new Date().toISOString()}] /validate request received:`, {
            contentType: req.headers['content-type'],
            bodyKeys: Object.keys(body),
            accountNumber: accountNumber ? accountNumber : '(empty)',
            broker: broker ? broker : '(empty)',
            eaName: eaName ? eaName : '(empty)'
        });
        
        // Validate required fields
        if (!accountNumber || !broker || !eaName) {
            console.error('Missing required fields:', { accountNumber, broker, eaName, bodyKeys: Object.keys(body), rawBodyLength: req.rawBody ? req.rawBody.length : 0 });
            return res.status(400).json({
                valid: false,
                error: 'Missing required fields',
                message: 'accountNumber, broker, and eaName are required',
                received: { accountNumber, broker, eaName, licenseKey },
                debug: { bodyKeys: Object.keys(body), rawBodyLen: req.rawBody ? req.rawBody.length : 0 }
            });
        }
        
        // Validate license
        const result = await validateLicense(accountNumber, broker, licenseKey, eaName);
        
        // Log validation attempt
        console.log(`[${new Date().toISOString()}] License check:`, {
            accountNumber,
            broker,
            eaName,
            valid: result.valid,
            reason: result.reason || 'valid'
        });
        
        res.json(result);
    } catch (error) {
        console.error('Validation error:', error);
        res.status(500).json({
            valid: false,
            error: 'Server error',
            message: 'Failed to validate license'
        });
    }
});

// Get all licenses (admin only - add authentication in production)
app.get('/admin/licenses', async (req, res) => {
    try {
        const licenses = await loadLicenses();
        res.json(licenses);
    } catch (error) {
        res.status(500).json({ error: 'Failed to load licenses' });
    }
});

// Add new license (admin only)
app.post('/admin/licenses', async (req, res) => {
    try {
        const build = buildLicenseEntry(req.body || {});
        if (build.error) {
            return res.status(400).json({ error: build.error });
        }
        
        const licenses = await loadLicenses();
        
        // Check if license already exists
        const exists = licenses.licenses.find(l => 
            l.accountNumber === build.entry.accountNumber && l.eaName === build.entry.eaName
        );
        
        if (exists) {
            return res.status(400).json({ error: 'License already exists for this account and EA' });
        }
        
        const newLicense = build.entry;
        
        licenses.licenses.push(newLicense);
        licenses.lastUpdated = new Date().toISOString();
        
        await saveLicenses(licenses);
        
        res.json({ success: true, license: newLicense });
    } catch (error) {
        console.error('Add license error:', error);
        res.status(500).json({ error: 'Failed to add license' });
    }
});

// Bulk add licenses (admin only)
app.post('/admin/licenses/bulk', async (req, res) => {
    try {
        const items = Array.isArray(req.body) ? req.body : req.body?.licenses;
        if (!Array.isArray(items)) {
            return res.status(400).json({ error: 'Expected an array of licenses' });
        }

        const licenses = await loadLicenses();
        const results = { added: 0, skipped: 0, errors: [] };

        items.forEach((item, index) => {
            const build = buildLicenseEntry(item || {});
            if (build.error) {
                results.errors.push({ index, error: build.error });
                return;
            }

            const exists = licenses.licenses.find(l =>
                l.accountNumber === build.entry.accountNumber && l.eaName === build.entry.eaName
            );
            if (exists) {
                results.skipped += 1;
                return;
            }

            licenses.licenses.push(build.entry);
            results.added += 1;
        });

        if (results.added > 0) {
            licenses.lastUpdated = new Date().toISOString();
            await saveLicenses(licenses);
        }

        res.json({ success: true, ...results, total: licenses.licenses.length });
    } catch (error) {
        console.error('Bulk add licenses error:', error);
        res.status(500).json({ error: 'Failed to add licenses' });
    }
});

// Update license
app.put('/admin/licenses/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const updates = req.body;
        
        const licenses = await loadLicenses();
        const licenseIndex = licenses.licenses.findIndex(l => l.id === id);
        
        if (licenseIndex === -1) {
            return res.status(404).json({ error: 'License not found' });
        }
        
        // Update license
        licenses.licenses[licenseIndex] = {
            ...licenses.licenses[licenseIndex],
            ...updates,
            updatedAt: new Date().toISOString()
        };
        
        licenses.lastUpdated = new Date().toISOString();
        await saveLicenses(licenses);
        
        res.json({ success: true, license: licenses.licenses[licenseIndex] });
    } catch (error) {
        res.status(500).json({ error: 'Failed to update license' });
    }
});

// Deactivate license
app.delete('/admin/licenses/:id', async (req, res) => {
    try {
        const { id } = req.params;
        
        const licenses = await loadLicenses();
        const licenseIndex = licenses.licenses.findIndex(l => l.id === id);
        
        if (licenseIndex === -1) {
            return res.status(404).json({ error: 'License not found' });
        }
        
        licenses.licenses[licenseIndex].isActive = false;
        licenses.lastUpdated = new Date().toISOString();
        await saveLicenses(licenses);
        
        res.json({ success: true, message: 'License deactivated' });
    } catch (error) {
        res.status(500).json({ error: 'Failed to deactivate license' });
    }
});

// Get license stats
app.get('/admin/stats', async (req, res) => {
    try {
        const licenses = await loadLicenses();
        const stats = {
            total: licenses.licenses.length,
            active: licenses.licenses.filter(l => l.isActive).length,
            expired: licenses.licenses.filter(l => {
                if (!l.expiryDate) return false;
                return new Date(l.expiryDate) < new Date();
            }).length,
            byEA: {}
        };
        
        licenses.licenses.forEach(license => {
            if (!stats.byEA[license.eaName]) {
                stats.byEA[license.eaName] = { total: 0, active: 0 };
            }
            stats.byEA[license.eaName].total++;
            if (license.isActive) stats.byEA[license.eaName].active++;
        });
        
        res.json(stats);
    } catch (error) {
        res.status(500).json({ error: 'Failed to get stats' });
    }
});

app.get('/admin/vds-cashflows', async (req, res) => {
    try {
        const payload = await loadVdsCashflowLedger();
        res.json({
            success: true,
            file: VDS_CASHFLOW_LEDGER_FILE,
            rows: payload.rows,
        });
    } catch (error) {
        console.error('Load VDS cashflows error:', error);
        res.status(500).json({ success: false, error: 'Failed to load VDS cashflow ledger' });
    }
});

app.post('/admin/vds-cashflows', async (req, res) => {
    try {
        const entry = await upsertVdsCashflowLedgerEntry(req.body || {});
        res.json({ success: true, row: entry });
    } catch (error) {
        console.error('Upsert VDS cashflow error:', error);
        res.status(400).json({ success: false, error: error.message || 'Failed to save VDS cashflow entry' });
    }
});

app.put('/admin/vds-cashflows/:profile', async (req, res) => {
    try {
        const entry = await upsertVdsCashflowLedgerEntry({
            ...(req.body || {}),
            profile: req.params.profile,
        });
        res.json({ success: true, row: entry });
    } catch (error) {
        console.error('Update VDS cashflow error:', error);
        res.status(400).json({ success: false, error: error.message || 'Failed to update VDS cashflow entry' });
    }
});

// Copier subscribers (admin only - add authentication in production)
app.get('/admin/copier-subscribers', async (req, res) => {
    try {
        const subscribers = await loadCopierSubscribers();
        res.json(subscribers);
    } catch (error) {
        res.status(500).json({ error: 'Failed to load copier subscribers' });
    }
});

app.post('/admin/copier-subscribers', async (req, res) => {
    try {
        const { name, email, plan, accountSize, contact } = req.body;

        if (!name || !email || !plan) {
            return res.status(400).json({ error: 'name, email, and plan are required' });
        }

        const planInfo = CHECKOUT_PLANS[plan];
        if (!planInfo || !planInfo.recurring) {
            return res.status(400).json({ error: 'Invalid copier plan selection' });
        }

        const subscribers = await loadCopierSubscribers();
        const exists = subscribers.subscribers.find(
            (subscriber) => subscriber.email === email && subscriber.plan === plan && subscriber.isActive !== false
        );
        if (exists) {
            return res.status(400).json({ error: 'Subscriber already exists for this plan' });
        }

        const newSubscriber = {
            id: crypto.randomBytes(16).toString('hex'),
            name: name,
            email: email,
            plan: plan,
            accountSize: accountSize || '',
            contact: contact || '',
            isActive: true,
            createdAt: new Date().toISOString(),
            lastInvoicedAt: null,
            lastChargeId: null,
            lastInvoiceStatus: null,
            lastInvoiceError: null
        };

        subscribers.subscribers.push(newSubscriber);
        subscribers.lastUpdated = new Date().toISOString();
        await saveCopierSubscribers(subscribers);

        res.json({ success: true, subscriber: newSubscriber });
    } catch (error) {
        res.status(500).json({ error: 'Failed to add copier subscriber' });
    }
});

app.put('/admin/copier-subscribers/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const updates = req.body || {};

        if (updates.plan) {
            const planInfo = CHECKOUT_PLANS[updates.plan];
            if (!planInfo || !planInfo.recurring) {
                return res.status(400).json({ error: 'Invalid copier plan selection' });
            }
        }

        const subscribers = await loadCopierSubscribers();
        const subscriberIndex = subscribers.subscribers.findIndex((subscriber) => subscriber.id === id);
        if (subscriberIndex === -1) {
            return res.status(404).json({ error: 'Subscriber not found' });
        }

        subscribers.subscribers[subscriberIndex] = {
            ...subscribers.subscribers[subscriberIndex],
            ...updates,
            updatedAt: new Date().toISOString()
        };
        subscribers.lastUpdated = new Date().toISOString();
        await saveCopierSubscribers(subscribers);

        res.json({ success: true, subscriber: subscribers.subscribers[subscriberIndex] });
    } catch (error) {
        res.status(500).json({ error: 'Failed to update copier subscriber' });
    }
});

app.delete('/admin/copier-subscribers/:id', async (req, res) => {
    try {
        const { id } = req.params;
        const subscribers = await loadCopierSubscribers();
        const subscriberIndex = subscribers.subscribers.findIndex((subscriber) => subscriber.id === id);
        if (subscriberIndex === -1) {
            return res.status(404).json({ error: 'Subscriber not found' });
        }

        subscribers.subscribers[subscriberIndex].isActive = false;
        subscribers.subscribers[subscriberIndex].updatedAt = new Date().toISOString();
        subscribers.lastUpdated = new Date().toISOString();
        await saveCopierSubscribers(subscribers);

        res.json({ success: true, message: 'Subscriber deactivated' });
    } catch (error) {
        res.status(500).json({ error: 'Failed to deactivate subscriber' });
    }
});

app.post('/admin/copier-subscribers/:id/invoice', async (req, res) => {
    try {
        const { id } = req.params;
        const result = await runCopierInvoiceJob({ force: true, subscriberId: id });
        if (!result.ok) {
            console.error('Copier invoice job failed:', result.error);
            return res.status(500).json({ error: result.error || 'Invoice job failed' });
        }
        const status = result.results.find((entry) => entry.id === id);
        if (!status) {
            return res.status(404).json({ error: 'Subscriber not found or not eligible' });
        }
        if (status.status === 'failed') {
            console.error('Copier invoice failed for subscriber:', id, status.error);
            return res.status(500).json({ error: status.error || 'Invoice failed' });
        }
        res.json({ success: true, status: status.status });
    } catch (error) {
        console.error('Copier invoice request error:', error.message);
        res.status(500).json({ error: 'Failed to send invoice' });
    }
});

//+------------------------------------------------------------------+
//| Start Server                                                      |
//+------------------------------------------------------------------+
if (INVOICE_CRON && INVOICE_CRON !== 'off') {
    cron.schedule(
        INVOICE_CRON,
        () => {
            runCopierInvoiceJob().catch((error) => {
                console.error('Copier invoice job failed:', error.message);
            });
        },
        { timezone: INVOICE_TIMEZONE }
    );
    console.log(`Copier invoice schedule enabled: ${INVOICE_CRON} (${INVOICE_TIMEZONE})`);
} else {
    console.log('Copier invoice schedule disabled.');
}

refreshBotLabCaches().then((results) => {
    const ok = results.filter((row) => row.ok).length;
    console.log(`Bot Lab cache warmup complete: ${ok}/${results.length} sources refreshed`);
}).catch((error) => {
    console.error('Bot Lab cache warmup failed:', error.message);
});

setInterval(() => {
    refreshBotLabCaches().catch((error) => {
        console.error('Bot Lab cache refresh failed:', error.message);
    });
}, BOT_LAB_CACHE_REFRESH_MS);

app.listen(PORT, () => {
    const envLicense = process.env.LICENSE_FILE;
    const envCopier = process.env.COPIER_SUBSCRIBERS_FILE;
    console.log(`========================================`);
    console.log(`License Server Running`);
    console.log(`========================================`);
    console.log(`Port: ${PORT}`);
    console.log(`LICENSE_FILE (env): ${envLicense === undefined ? '(not set)' : envLicense}`);
    console.log(`COPIER_SUBSCRIBERS_FILE (env): ${envCopier === undefined ? '(not set)' : envCopier}`);
    console.log(`License File (resolved): ${LICENSE_FILE}`);
    console.log(`Copier File (resolved): ${COPIER_SUBSCRIBERS_FILE}`);
    if (!envLicense && !useDataDir) {
        console.log(`WARNING: No LICENSE_FILE set and /data not found. Licenses will not persist across redeploys.`);
    }
    if (useDataDir) {
        console.log(`Using /data for licenses (volume detected).`);
    }
    if (RESEND_API_KEY) {
        console.log(`Invoice emails: Resend (RESEND_API_KEY set)`);
    } else if (SMTP_USER && SMTP_PASS) {
        console.log(`Invoice emails: SMTP`);
    } else {
        console.log(`Invoice emails: NOT CONFIGURED (set RESEND_API_KEY or SMTP_USER/SMTP_PASS)`);
    }
    console.log(`Server URL: http://localhost:${PORT}`);
    console.log(`Health Check: http://localhost:${PORT}/health`);
    console.log(`========================================`);
});
