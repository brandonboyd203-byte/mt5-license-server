#!/usr/bin/env node
/**
 * Bulk-add licenses from bulk-licenses-demo-accounts.json
 * Usage: node add-bulk-licenses.js [baseUrl]
 * Example: node add-bulk-licenses.js
 *          node add-bulk-licenses.js https://your-license-server.up.railway.app
 * Requires server running (or use full URL for remote).
 */
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const baseUrl = process.argv[2] || 'http://localhost:3001';
const jsonPath = path.join(__dirname, 'bulk-licenses-demo-accounts.json');

let licenses;
try {
  licenses = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
} catch (e) {
  console.error('Failed to read', jsonPath, e.message);
  process.exit(1);
}

const url = new URL('/admin/licenses/bulk', baseUrl);
const isHttps = url.protocol === 'https:';
const body = JSON.stringify(licenses);

const options = {
  hostname: url.hostname,
  port: url.port || (isHttps ? 443 : 80),
  path: url.pathname,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(body)
  }
};

const req = (isHttps ? https : http).request(options, (res) => {
  let data = '';
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    try {
      const out = JSON.parse(data);
      if (out.success) {
        console.log('Success:', out.added, 'added,', out.skipped, 'skipped (already exist). Total licenses:', out.total);
        if (out.errors && out.errors.length) console.log('Errors:', out.errors);
      } else {
        console.error('Response:', out);
      }
    } catch (_) {
      console.log('Response:', res.statusCode, data);
    }
  });
});

req.on('error', (e) => {
  console.error('Request failed:', e.message);
  if (baseUrl.includes('localhost')) console.error('Is the server running? Start with: npm start');
  process.exit(1);
});

req.write(body);
req.end();
