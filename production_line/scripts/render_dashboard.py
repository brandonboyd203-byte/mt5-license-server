#!/usr/bin/env python3
import json, os, sys, datetime

if len(sys.argv) < 4:
    print("Usage: render_dashboard.py <summary.json> <vps_snapshot.json> <output.html>")
    sys.exit(1)

summary = json.load(open(sys.argv[1]))
snap = json.load(open(sys.argv[2]))
out = sys.argv[3]

rows = []
for p in summary.get('profiles', []):
    c = p.get('compile', {})
    rows.append(
        "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>".format(
            p.get('profile'), c.get('status'), c.get('errors'), c.get('warnings'), p.get('runtime_critical_hits'), c.get('target')
        )
    )

verdict_cls = 'ok' if summary.get('verdict') == 'PASS' else 'warn'

html = """
<!doctype html><html><head><meta charset='utf-8'><title>Bot Ops Dashboard</title>
<style>
body{font-family:Arial;margin:24px;background:#0f172a;color:#e2e8f0} .card{background:#111827;padding:16px;border-radius:12px;margin-bottom:14px}
table{width:100%;border-collapse:collapse} td,th{border-bottom:1px solid #334155;padding:8px;text-align:left} .ok{color:#34d399} .warn{color:#fbbf24}
.mini{font-size:12px;color:#94a3b8}
.feed-list{list-style:none;padding-left:0;display:grid;gap:6px;max-height:320px;overflow:auto}
.feed-list li{padding:8px;border:1px solid #334155;border-radius:8px;background:#0b1324}
</style></head><body>
<h1>Goldmine Bot Ops Dashboard</h1>
<div class='card'>
<b>Generated:</b> __GENERATED__<br/>
<b>Branch:</b> __BRANCH__<br/>
<b>Focus bot:</b> __BOT__<br/>
<b>Verdict:</b> <span class='__VERDICT_CLS__'>__VERDICT__</span><br/>
<b>terminal64 running:</b> __TERMINALS__<br/>
<b>metaeditor64 running:</b> __METAEDITORS__<br/>
<b>Compile bad profiles:</b> __COMPILE_BAD__<br/>
<b>Compile unknown profiles:</b> __COMPILE_UNKNOWN__<br/>
<b>Runtime critical hits:</b> __RUNTIME_CRIT__
</div>
<div class='card'>
<h3>Profile Status</h3>
<table><tr><th>Profile</th><th>Compile</th><th>Errors</th><th>Warnings</th><th>Runtime Crit</th><th>Target</th></tr>
__PROFILE_ROWS__
</table>
</div>
<div class='card'>
  <h3>VDS Live Feed (Home/Navigate)</h3>
  <div class='mini'>Source: <code id='vdsFeedSrc'>http://46.250.244.188:8788/api/feed?limit=40</code></div>
  <ul id='vdsLiveFeed' class='feed-list'><li>Connecting...</li></ul>
</div>
<div class='card'><h3>Latest Report Folders</h3><pre>__LATEST_REPORTS__</pre></div>
<script>
(function(){
  const src = (window.VDS_FEED_URL || 'http://46.250.244.188:8788/api/feed?limit=40');
  const srcEl = document.getElementById('vdsFeedSrc');
  const listEl = document.getElementById('vdsLiveFeed');
  if(srcEl) srcEl.textContent = src;
  async function load(){
    try{
      const r = await fetch(src, { cache:'no-store' });
      if(!r.ok) throw new Error('HTTP '+r.status);
      const j = await r.json();
      const rows = Array.isArray(j.feed) ? j.feed : [];
      if(!rows.length){ listEl.innerHTML = '<li>No events yet.</li>'; return; }
      listEl.innerHTML = rows.slice(0, 40).map((e)=>{
        const t = e && e.t ? new Date(e.t).toLocaleTimeString() : '-';
        const p = (e && (e.profile || e.profileLabel)) || '-';
        const k = (e && e.kind) || 'event';
        const txt = String((e && e.text) || '').slice(0, 170);
        return `<li><b>${t}</b> [${p}] ${k} — ${txt}</li>`;
      }).join('');
    }catch(err){
      listEl.innerHTML = '<li>VDS feed unavailable from this host (network/CORS).</li>';
    }
  }
  load();
  setInterval(load, 10000);
})();
</script>
</body></html>
"""

html = (html
    .replace('__GENERATED__', datetime.datetime.now().isoformat(timespec='seconds'))
    .replace('__BRANCH__', str(summary.get('branch')))
    .replace('__BOT__', str(summary.get('bot')))
    .replace('__VERDICT_CLS__', verdict_cls)
    .replace('__VERDICT__', str(summary.get('verdict')))
    .replace('__TERMINALS__', str(snap.get('terminal64_count')))
    .replace('__METAEDITORS__', str(snap.get('metaeditor64_count')))
    .replace('__COMPILE_BAD__', str(summary.get('compile_bad_profiles')))
    .replace('__COMPILE_UNKNOWN__', str(summary.get('compile_unknown_profiles')))
    .replace('__RUNTIME_CRIT__', str(summary.get('runtime_critical_hits')))
    .replace('__PROFILE_ROWS__', ''.join(rows))
    .replace('__LATEST_REPORTS__', json.dumps(snap.get('latest_reports', []), indent=2))
)

os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w').write(html)
print(out)
