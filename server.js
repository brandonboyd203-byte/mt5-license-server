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
const SECRET_KEY = process.env.SECRET_KEY || 'your-secret-key-change-this';
const COINBASE_COMMERCE_API_KEY = process.env.COINBASE_COMMERCE_API_KEY || '';
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

// Middleware
app.use(cors());
app.use('/assets', express.static(path.join(__dirname, 'assets')));
// Parse JSON - handle both with and without Content-Type header
app.use(express.json({ 
    type: ['application/json', 'text/plain', 'text/json', '*/*'],
    strict: false 
}));

// Serve admin.html
app.get('/admin.html', (req, res) => {
    res.sendFile(path.join(__dirname, 'admin.html'));
});

// Serve marketing homepage
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
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
    goldmine_blueprint_gold: {
        name: 'Goldmine Blueprint – Gold',
        amount: 4999,
        description: 'Bot license - Goldmine Blueprint Gold'
    },
    goldmine_blueprint_silver: {
        name: 'Goldmine Blueprint – Silver',
        amount: 4999,
        description: 'Bot license - Goldmine Blueprint Silver'
    },
    goldmine_nexus_gold: {
        name: 'Goldmine Nexus – Gold',
        amount: 4999,
        description: 'Bot license - Goldmine Nexus Gold'
    },
    goldmine_nexus_silver: {
        name: 'Goldmine Nexus – Silver',
        amount: 4999,
        description: 'Bot license - Goldmine Nexus Silver'
    },
    goldmine_dominion: {
        name: 'Goldmine Dominion',
        amount: 4999,
        description: 'Bot license - Goldmine Dominion'
    },
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

        const { name, email, plan, accountSize, contact } = body || {};
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
                plan: plan
            }
        });

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
        
        // Log incoming request for debugging
        console.log(`[${new Date().toISOString()}] /validate request received:`, {
            headers: req.headers,
            body: body,
            contentType: req.headers['content-type'],
            bodyType: typeof req.body
        });
        
        const accountNumber = body.accountNumber != null ? String(body.accountNumber).trim() : '';
        const broker = body.broker != null ? String(body.broker).trim() : '';
        const eaName = body.eaName != null ? String(body.eaName).trim() : '';
        const licenseKey = body.licenseKey != null ? String(body.licenseKey).trim() : '';
        
        // Validate required fields
        if (!accountNumber || !broker || !eaName) {
            console.error('Missing required fields:', { accountNumber, broker, eaName, body: body, rawBody: req.body });
            return res.status(400).json({
                valid: false,
                error: 'Missing required fields',
                message: 'accountNumber, broker, and eaName are required',
                received: { accountNumber, broker, eaName, licenseKey },
                debug: { bodyType: typeof body, bodyKeys: body ? Object.keys(body) : 'null' }
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
