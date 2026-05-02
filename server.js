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
const MOTHERBOARD_VDS_TELEMETRY_URL = process.env.MOTHERBOARD_VDS_TELEMETRY_URL || 'http://46.250.244.188:8788/api/telemetry';
const MOTHERBOARD_VDS_DASHBOARD_URL = process.env.MOTHERBOARD_VDS_DASHBOARD_URL || 'http://46.250.244.188:8788/';
const MOTHERBOARD_VDS_CHARTS_URL = process.env.MOTHERBOARD_VDS_CHARTS_URL || MOTHERBOARD_VDS_TELEMETRY_URL.replace(/\/api\/telemetry$/i, '/api/charts/live');
const BOT_LAB_API_URL = process.env.BOT_LAB_API_URL || 'http://46.250.244.188:8788/api/bot-lab/latest';
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
const BOT_LAB_SCHEDULE_URL = process.env.BOT_LAB_SCHEDULE_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/bot-lab/schedule');
const BOT_LAB_SWEEP_STATUS_URL = process.env.BOT_LAB_SWEEP_STATUS_URL
    || BOT_LAB_API_URL.replace(/\/api\/bot-lab\/latest$/i, '/api/param-sweep/status');

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

app.get('/app-icon.svg', (req, res) => {
    const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#05070d"/>
      <stop offset="100%" stop-color="#141a28"/>
    </linearGradient>
    <linearGradient id="gold" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f4d17f"/>
      <stop offset="55%" stop-color="#c6933f"/>
      <stop offset="100%" stop-color="#f9e4a1"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#bg)"/>
  <rect x="44" y="44" width="424" height="424" rx="96" fill="none" stroke="rgba(255,255,255,0.1)"/>
  <path d="M154 148h112c62 0 98 28 98 76 0 29-14 49-42 60 35 11 54 36 54 72 0 59-44 96-113 96H154V148zm84 62v58h34c29 0 45-10 45-29 0-20-15-29-45-29h-34zm0 119v62h43c31 0 48-11 48-31 0-21-17-31-48-31h-43z" fill="url(#gold)"/>
  <path d="M104 362h33l38-48 33 28 53-72 48 37 63-88 36 25" fill="none" stroke="url(#gold)" stroke-width="24" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
    res.setHeader('Content-Type', 'image/svg+xml; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    res.send(svg);
});

app.get('/manifest.webmanifest', (req, res) => {
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
            { src: '/app-icon.svg', sizes: '192x192', type: 'image/svg+xml', purpose: 'any maskable' },
            { src: '/app-icon.svg', sizes: '512x512', type: 'image/svg+xml', purpose: 'any maskable' }
        ]
    }));
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

function n(v, fallback = 0) {
    const x = Number(v);
    return Number.isFinite(x) ? x : fallback;
}

function getMotherboardConfig(_sourceRaw) {
    return {
        source: 'vds',
        telemetryUrl: MOTHERBOARD_VDS_TELEMETRY_URL,
        dashboardUrl: MOTHERBOARD_VDS_DASHBOARD_URL,
        chartsUrl: MOTHERBOARD_VDS_CHARTS_URL
    };
}

function shapeLiveBotPayload(raw, cfg) {
    const telemetry = raw?.telemetry || raw || {};
    const copierFeedRaw = raw?.copierFeed || telemetry?.copierFeed || null;
    const vdsHideNameParts = ['BASE', 'PRESET', 'LAB', 'DOMINION', 'EDGE', 'SURGE', 'FRESH', 'BRAND_NEW', 'COPIER_NEW', 'COPIER_CLEAN', 'TF_SETUP'];
    const shouldHideVdsProfile = (nameRaw) => {
        const name = String(nameRaw || '').trim().toUpperCase();
        if (!name) return true;
        if (name.endsWith(':BASE') || name.endsWith(':PRESETS')) return true;
        return vdsHideNameParts.some((part) => name.includes(part));
    };
    const profilesRaw = Array.isArray(telemetry.profiles) ? telemetry.profiles : [];
    const profiles = cfg?.source === 'vds'
        ? profilesRaw.filter((p) => !shouldHideVdsProfile(p?.profile || p?.profileLabel))
        : profilesRaw;
    const summary = telemetry.summary || {};
    const day = summary.day || {};
    const week = summary.week || {};

    let rows = profiles
        .map((p) => {
            const dayMetrics = p?.metrics?.day || {};
            const weekMetrics = p?.metrics?.week || {};
            const lifetimeMetrics = p?.metrics?.lifetime || {};
            const totalMetrics = p?.metrics?.total || {};
            const status = p?.metrics?.status || {};
            const balance = Number.isFinite(Number(p.currentBalance)) ? Number(p.currentBalance) : null;
            const equity = Number.isFinite(Number(p.currentEquity)) ? Number(p.currentEquity) : null;
            const depositAmount = Number.isFinite(Number(p.depositAmount)) ? Number(p.depositAmount) : (Number.isFinite(Number(p.deposit)) ? Number(p.deposit) : null);
            const withdrawAmount = Number.isFinite(Number(p.withdrawAmount)) ? Number(p.withdrawAmount) : (Number.isFinite(Number(p.withdraw)) ? Number(p.withdraw) : null);
            const accountStartEquity = Number.isFinite(Number(p.accountStartEquity)) ? Number(p.accountStartEquity) : null;
            let dayStart = Number(p.dayStartEquity ?? p.dayStartBalance ?? dayMetrics.equityBaseline);
            const baselineFallback = Number.isFinite(accountStartEquity) && accountStartEquity > 0
                ? accountStartEquity
                : (Number.isFinite(depositAmount) && depositAmount > 0 ? depositAmount : null);
            if (!Number.isFinite(dayStart) || dayStart <= 0) dayStart = Number(baselineFallback);
            if (Number.isFinite(dayStart) && dayStart > 0) {
                const cap = Math.max(equity * 1.8, Number.isFinite(baselineFallback) ? Number(baselineFallback) * 1.8 : 0);
                if (cap > 0 && dayStart > cap) dayStart = Number(baselineFallback ?? equity);
            }
            let liveDayFromEq = (Number.isFinite(dayStart) && dayStart > 0)
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
            const reportedOpen = Number(p.openProfit);
            const openPositions = n(p.openPositions, 0);
            const openProfit = Number.isFinite(reportedOpen)
                ? (openPositions > 0 ? reportedOpen : 0)
                : 0;
            const totalBaseline = Number.isFinite(accountStartEquity) && accountStartEquity > 0
                ? accountStartEquity
                : (Number.isFinite(depositAmount) && depositAmount > 0 ? depositAmount : null);
            const totalNetCashflow = (Number.isFinite(totalBaseline) && totalBaseline > 0)
                ? Number((equity + n(withdrawAmount, 0) - totalBaseline).toFixed(2))
                : null;
            const totalPctCashflow = (Number.isFinite(totalBaseline) && totalBaseline > 0 && Number.isFinite(totalNetCashflow))
                ? Number(((100 * totalNetCashflow) / totalBaseline).toFixed(2))
                : null;
            return {
                profile: p.profile,
                profileLabel: p.profileLabel || p.profile,
                accountName: p.accountName || null,
                account: p.account || null,
                balanceSource: p.balanceSource || null,
                riskPct: p.riskPct ?? null,
                leverage: p.leverage || null,
                leverageSource: p.leverageSource || null,
                depositAmount,
                withdrawAmount,
                accountStartEquity,
                dayStartBalance: Number.isFinite(Number(p.dayStartBalance)) ? Number(p.dayStartBalance) : null,
                dayStartEquity: Number.isFinite(Number(p.dayStartEquity)) ? Number(p.dayStartEquity) : null,
                balance,
                equity,
                openProfit,
                currentPnlGross: Number.isFinite(Number(p.currentPnlGross)) ? Number(p.currentPnlGross) : null,
                currentPnlWithOpen: Number.isFinite(Number(p.currentPnlWithOpen)) ? Number(p.currentPnlWithOpen) : null,
                dayNetUsd: n(dayNet, 0),
                dayReturnPct: Number.isFinite(Number(dayRet)) ? Number(dayRet) : null,
                weekNetUsd: n(weekMetrics.netUsd, 0),
                weekReturnPct: Number.isFinite(Number(weekMetrics.returnPct)) ? Number(weekMetrics.returnPct) : null,
                lifetimeNetUsd: Number.isFinite(Number(lifetimeMetrics.netUsd)) ? Number(lifetimeMetrics.netUsd) : null,
                lifetimeReturnPct: Number.isFinite(Number(lifetimeMetrics.returnPct)) ? Number(lifetimeMetrics.returnPct) : null,
                lifetimeMatchedCloses: Number.isFinite(Number(lifetimeMetrics.matchedCloses)) ? Number(lifetimeMetrics.matchedCloses) : 0,
                lifetimeWinRatePct: Number.isFinite(Number(lifetimeMetrics.winRatePct)) ? Number(lifetimeMetrics.winRatePct) : null,
                lifetimeProfitFactor: Number.isFinite(Number(lifetimeMetrics.profitFactor)) ? Number(lifetimeMetrics.profitFactor) : null,
                totalNetUsd: Number.isFinite(totalNetCashflow)
                    ? totalNetCashflow
                    : (Number.isFinite(Number(p.totalNetUsd))
                    ? Number(p.totalNetUsd)
                    : (Number.isFinite(Number(totalMetrics.netUsd))
                        ? Number(totalMetrics.netUsd)
                        : (Number.isFinite(Number(p.currentEquity)) && Number.isFinite(Number(p.accountStartEquity))
                            ? Number((Number(p.currentEquity) - Number(p.accountStartEquity)).toFixed(2))
                            : null))),
                totalReturnPct: Number.isFinite(totalPctCashflow)
                    ? totalPctCashflow
                    : (Number.isFinite(Number(p.totalReturnPct))
                    ? Number(p.totalReturnPct)
                    : (Number.isFinite(Number(totalMetrics.returnPct))
                        ? Number(totalMetrics.returnPct)
                        : (Number.isFinite(Number(p.currentEquity)) && Number.isFinite(Number(p.accountStartEquity)) && Number(p.accountStartEquity) > 0
                            ? Number(((100 * (Number(p.currentEquity) - Number(p.accountStartEquity))) / Number(p.accountStartEquity)).toFixed(2))
                            : null))),
                status: status.label || 'UNKNOWN',
                statusReason: status.reason || '',
                updatedAt: p.lastActivityAt || p.snapshotAt || p.lastSyncAt || telemetry.generatedAt || null
            };
        })
        .sort((a, b) => b.dayNetUsd - a.dayNetUsd);


    const summaryDayNetUsd = rows.reduce((a, r) => a + n(r.dayNetUsd, 0), 0);
    const summaryOpenProfitUsd = rows.reduce((a, r) => a + n(r.openProfit, 0), 0);
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
        generatedAt: telemetry.generatedAt || new Date().toISOString(),
        source: {
            node: cfg?.source || 'vds',
            telemetryUrl: cfg?.telemetryUrl || null,
            dashboardUrl: cfg?.dashboardUrl || null
        },
        summary: {
            profilesTotal: rows.length,
            openPositions: n(summary.totalOpenPositions, 0),
            openOrders: n(summary.totalOpenOrders, 0),
            dayNetUsd: Number(summaryDayNetUsd.toFixed(2)),
            dayReturnPct: summaryDayReturnPct,
            weekNetUsd: n(week.netUsd, 0),
            weekReturnPct: Number.isFinite(Number(week.returnPct)) ? Number(week.returnPct) : null,
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
        name: 'Copier Option A',
        amount: 262,
        description: 'Copier Option A (small accounts) - monthly',
        recurring: true
    },
    copier_option_b: {
        name: 'Copier Option B',
        amount: 500,
        description: 'Copier Option B (large accounts) - monthly',
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
        const raw = await fetchJsonWithTimeout(withCacheBust(cfg.telemetryUrl), 15000);
        const payload = shapeLiveBotPayload(raw, cfg);
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

app.get('/api/bot-lab/latest', async (req, res) => {
    try {
        const payload = normalizeBotLabPayload(await fetchJsonWithTimeout(withCacheBust(BOT_LAB_API_URL), 15000));
        res.json({ ok: true, source: BOT_LAB_API_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab unavailable', source: BOT_LAB_API_URL });
    }
});

app.get('/api/bot-lab/history', async (req, res) => {
    try {
        const limit = Math.max(1, Math.min(50, Number(req.query.limit || 12)));
        const joiner = BOT_LAB_HISTORY_URL.includes('?') ? '&' : '?';
        const url = `${BOT_LAB_HISTORY_URL}${joiner}limit=${limit}`;
        const payload = normalizeBotLabPayload(await fetchJsonWithTimeout(withCacheBust(url), 15000));
        res.json({ ok: true, source: BOT_LAB_HISTORY_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab history unavailable', source: BOT_LAB_HISTORY_URL });
    }
});

app.get('/api/bot-lab/analysis', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_ANALYSIS_URL), 20000);
        res.json({ ok: true, source: BOT_LAB_ANALYSIS_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab analysis unavailable', source: BOT_LAB_ANALYSIS_URL });
    }
});

app.get('/api/bot-lab/catalog', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_CATALOG_URL), 15000);
        res.json({ ok: true, source: BOT_LAB_CATALOG_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab catalog unavailable', source: BOT_LAB_CATALOG_URL });
    }
});

app.get('/api/bot-lab/progress', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_PROGRESS_URL), 20000);
        res.json({ ok: true, source: BOT_LAB_PROGRESS_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab progress unavailable', source: BOT_LAB_PROGRESS_URL });
    }
});

app.get('/api/bot-lab/discord-summary', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_DISCORD_SUMMARY_URL), 20000);
        res.json({ ok: true, source: BOT_LAB_DISCORD_SUMMARY_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab discord summary unavailable', source: BOT_LAB_DISCORD_SUMMARY_URL });
    }
});

app.get('/api/bot-lab/schedule', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_SCHEDULE_URL), 20000);
        res.json({ ok: true, source: BOT_LAB_SCHEDULE_URL, payload });
    } catch (error) {
        res.status(502).json({ ok: false, error: error.message || 'Bot Lab schedule unavailable', source: BOT_LAB_SCHEDULE_URL });
    }
});

app.get('/api/param-sweep/status', async (req, res) => {
    try {
        const payload = await fetchJsonWithTimeout(withCacheBust(BOT_LAB_SWEEP_STATUS_URL), 20000);
        res.json({ ok: true, source: BOT_LAB_SWEEP_STATUS_URL, payload });
    } catch (error) {
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
        const [snapRaw, teleRaw] = await Promise.all([
            fetchJsonWithTimeout(`${base}/api/snapshots/terminal`, 15000),
            fetchJsonWithTimeout(MOTHERBOARD_VDS_TELEMETRY_URL, 15000)
        ]);

        const snapList = Array.isArray(snapRaw?.snapshots) ? snapRaw.snapshots : [];
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
            .sort((a, b) => b.dayNetUsd - a.dayNetUsd);

        const picked = [];
        for (const r of ranked) {
            const s = snapByAcct.get(r.account);
            if (!s) continue;
            picked.push({ s, r });
            if (picked.length >= 2) break;
        }

        if (picked.length < 2) {
            for (const s of snapList) {
                if (picked.find((x) => String(x?.s?.account) === String(s?.account))) continue;
                picked.push({ s, r: null });
                if (picked.length >= 2) break;
            }
        }

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
