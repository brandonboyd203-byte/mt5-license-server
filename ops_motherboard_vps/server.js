#!/usr/bin/env node
import http from 'http';
import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';

const PORT = Number(process.env.PORT || 8788);
const ROOT = path.resolve(process.cwd());
const REPORTS = 'C:/GoldmineOps/reports/raw';
const LIVE_LOG = 'C:/GoldmineOps/reports/live-window.log';
const DISCORD_METRICS_URL = process.env.DISCORD_METRICS_URL || 'https://discord-gpt-bot-production-4cb9.up.railway.app/metrics';

function j(res, code, obj){ res.writeHead(code, {'Content-Type':'application/json'}); res.end(JSON.stringify(obj,null,2)); }
function txt(res, code, t){ res.writeHead(code, {'Content-Type':'text/plain'}); res.end(t); }

function ps(cmd){
  return new Promise((resolve)=>{
    exec(`powershell -NoProfile -Command "${cmd}"`, { timeout: 12000, maxBuffer: 1024*1024 }, (err, stdout, stderr)=>{
      resolve({ ok: !err, stdout: stdout?.trim()||'', stderr: stderr?.trim()||'', error: err?.message||null });
    });
  });
}

async function fetchJson(url){
  try {
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 2000);
    const r = await fetch(url,{signal:ctrl.signal});
    clearTimeout(t);
    if(!r.ok) return null;
    try { return await r.json(); } catch { return { ok:true, nonJson:true }; }
  } catch { return null; }
}

async function fetchOk(url){
  try {
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), 2000);
    const r = await fetch(url,{signal:ctrl.signal});
    clearTimeout(t);
    return r.ok;
  } catch { return false; }
}

const server = http.createServer(async (req,res)=>{
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (url.pathname === '/' || url.pathname === '/health') return txt(res,200,'OK');

  if (url.pathname === '/api/status' || url.pathname === '/api/fast-status') {
    const fast = url.pathname === '/api/fast-status';

    const p1 = ps("(Get-Process terminal64 -ErrorAction SilentlyContinue | Measure-Object).Count");
    const p2 = ps("(Get-Process metaeditor64 -ErrorAction SilentlyContinue | Measure-Object).Count");
    const latest = fast
      ? Promise.resolve({ ok:true, stdout:'[]', stderr:'', error:null })
      : ps("if(Test-Path 'C:/GoldmineOps/reports/raw'){ Get-ChildItem 'C:/GoldmineOps/reports/raw' -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 6 FullName,LastWriteTime | ConvertTo-Json -Depth 4 }");
    const liveLog = fast
      ? Promise.resolve({ ok:true, stdout:'', stderr:'', error:null })
      : ps("if(Test-Path 'C:/GoldmineOps/reports/live-window.log'){ Get-Content 'C:/GoldmineOps/reports/live-window.log' -Tail 20 }");

    const discordMetrics = fast ? null : await fetchJson(DISCORD_METRICS_URL);
    let discordHealth = discordMetrics ? { connected:true, source:'metrics' } : { connected:false, source:'none' };
    if (!fast && !discordHealth.connected) {
      const rootUrl = DISCORD_METRICS_URL.replace(/\/metrics\/?$/, '/');
      const ok = await fetchOk(rootUrl);
      if (ok) discordHealth = { connected:true, source:'root-health' };
    }

    const [p1r, p2r, latestr, liveLogr] = await Promise.all([p1, p2, latest, liveLog]);

    let latestReports = [];
    try { latestReports = JSON.parse(latestr.stdout || '[]'); if(!Array.isArray(latestReports)) latestReports=[latestReports]; } catch {}

    return j(res,200,{
      generatedAt: new Date().toISOString(),
      terminal64_count: Number(p1r.stdout||0),
      metaeditor64_count: Number(p2r.stdout||0),
      latest_reports: latestReports,
      live_window_log_tail: liveLogr.stdout ? liveLogr.stdout.split(/\r?\n/) : [],
      discordHealth: fast ? { connected:false, source:'skipped' } : discordHealth,
      discordMetrics: fast ? null : discordMetrics
    });
  }

  if (req.method === 'POST' && url.pathname.startsWith('/api/control/')) {
    const action = url.pathname.split('/').pop();
    let cmd = '';
    if (action === 'pause') cmd = "& 'C:/GoldmineOps/scripts/pause_live.ps1'";
    else if (action === 'resume') cmd = "& 'C:/GoldmineOps/scripts/resume_live.ps1'";
    else if (action === 'restart') cmd = "& 'C:/GoldmineOps/scripts/restart_mt5.ps1'";
    else if (action === 'status') cmd = "Get-Process terminal64 -ErrorAction SilentlyContinue | Select-Object Id,StartTime,CPU";
    else return j(res,400,{ok:false,error:'invalid action'});
    const out = await ps(cmd);
    return j(res,200,{ok:out.ok,action,stdout:out.stdout,stderr:out.stderr,error:out.error});
  }

  j(res,404,{error:'not found'});
});

server.listen(PORT, '0.0.0.0', ()=> console.log(`Ops Motherboard VPS on :${PORT}`));
