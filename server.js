//+------------------------------------------------------------------+
//| Remote License Server for MT5 EAs                                |
//| Validates licenses for BigBeluga and Advanced Scalper EAs         |
//+------------------------------------------------------------------+

const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

const app = express();
// Railway sets PORT automatically - use it or default to 3001
const PORT = process.env.PORT || 3001;
const LICENSE_FILE = path.join(__dirname, 'licenses.json');
const SECRET_KEY = process.env.SECRET_KEY || 'your-secret-key-change-this';

// Middleware
app.use(cors());
app.use(express.json());

//+------------------------------------------------------------------+
//| Load Licenses from File                                          |
//+------------------------------------------------------------------+
async function loadLicenses() {
    try {
        const data = await fs.readFile(LICENSE_FILE, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        // File doesn't exist, create default
        const defaultLicenses = {
            licenses: [],
            lastUpdated: new Date().toISOString()
        };
        await saveLicenses(defaultLicenses);
        return defaultLicenses;
    }
}

//+------------------------------------------------------------------+
//| Save Licenses to File                                            |
//+------------------------------------------------------------------+
async function saveLicenses(licenses) {
    await fs.writeFile(LICENSE_FILE, JSON.stringify(licenses, null, 2), 'utf8');
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
    const licenses = await loadLicenses();
    const accountStr = String(accountNumber);
    
    // Find license for this account
    const license = licenses.licenses.find(l => 
        l.accountNumber === accountStr && 
        l.eaName === eaName &&
        l.isActive === true
    );
    
    if (!license) {
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
//| API Endpoints                                                     |
//+------------------------------------------------------------------+

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'online', timestamp: new Date().toISOString() });
});

// Validate license
app.post('/validate', async (req, res) => {
    try {
        const { accountNumber, broker, licenseKey, eaName } = req.body;
        
        // Validate required fields
        if (!accountNumber || !broker || !eaName) {
            return res.status(400).json({
                valid: false,
                error: 'Missing required fields',
                message: 'accountNumber, broker, and eaName are required'
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
        const { accountNumber, userName, eaName, expiryDate, allowedBrokers, licenseKey } = req.body;
        
        if (!accountNumber || !eaName) {
            return res.status(400).json({ error: 'accountNumber and eaName are required' });
        }
        
        const licenses = await loadLicenses();
        
        // Check if license already exists
        const exists = licenses.licenses.find(l => 
            l.accountNumber === String(accountNumber) && l.eaName === eaName
        );
        
        if (exists) {
            return res.status(400).json({ error: 'License already exists for this account and EA' });
        }
        
        // Create new license
        const newLicense = {
            id: crypto.randomBytes(16).toString('hex'),
            accountNumber: String(accountNumber),
            userName: userName || 'Unknown',
            eaName: eaName,
            expiryDate: expiryDate || null,
            allowedBrokers: allowedBrokers || [],
            licenseKey: licenseKey || generateLicenseHash(accountNumber, 'any', expiryDate),
            isActive: true,
            createdAt: new Date().toISOString(),
            lastValidated: null
        };
        
        licenses.licenses.push(newLicense);
        licenses.lastUpdated = new Date().toISOString();
        
        await saveLicenses(licenses);
        
        res.json({ success: true, license: newLicense });
    } catch (error) {
        console.error('Add license error:', error);
        res.status(500).json({ error: 'Failed to add license' });
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

//+------------------------------------------------------------------+
//| Start Server                                                      |
//+------------------------------------------------------------------+
app.listen(PORT, () => {
    console.log(`========================================`);
    console.log(`License Server Running`);
    console.log(`========================================`);
    console.log(`Port: ${PORT}`);
    console.log(`License File: ${LICENSE_FILE}`);
    console.log(`Server URL: http://localhost:${PORT}`);
    console.log(`Health Check: http://localhost:${PORT}/health`);
    console.log(`========================================`);
});
