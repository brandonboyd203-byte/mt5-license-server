let activeFilter = 'ALL';
let runtimeTimeline = [];
let selectedProfile = null;
const liveChartCache = new Map();
const terminalSnapshotCache = new Map();
const AUDIT_KEY = 'ops_action_audit';
const PROFILE_ALIAS = {
  Lab2: 'Blueprint Original',
};
const PROFILE_ORDER = [
  'Blueprint_Risk15',
  'Blueprint_Risk20',
  'Lab2',
  'Blueprint20_leverage500',
  'Blueprint20_leverage1000',
  'Blueprint20_leverage2000',
  'Nexus',
  'Nexus_Risk15',
  'Nexus_Risk20',
  'Fresh',
  'Edge',
  'Dominion',
];
const PROFILE_SYMBOLS = {
  Fresh: ['XAUUSD', 'XAGUSD'],
  Edge: ['XAUUSD', 'XAGUSD'],
  Dominion: ['XAUUSD', 'XAGUSD'],
  Nexus: ['XAUUSD', 'XAGUSD'],
  Nexus_Risk15: ['XAUUSD', 'XAGUSD'],
  Nexus_Risk20: ['XAUUSD', 'XAGUSD'],
  Blueprint_Risk15: ['XAUUSD', 'XAGUSD'],
  Blueprint_Risk20: ['XAUUSD', 'XAGUSD'],
  Blueprint20_leverage500: ['XAUUSD', 'XAGUSD'],
  Blueprint20_leverage1000: ['XAUUSD', 'XAGUSD'],
  Blueprint20_leverage2000: ['XAUUSD', 'XAGUSD'],
  Lab2: ['XAUUSD', 'XAGUSD'],
};
const DEFAULT_DEPOSIT_START_EQ = null;
const DEFAULT_WITHDRAW_USD = null;
const DEFAULT_RISK_PCT = 9;
const PREFER_TERMINAL_SNAPSHOT = true;
const TOP_FEED_SNAPSHOT_ONLY = false;

function el(id) {
  return document.getElementById(id);
}

function setText(id, value) {
  const node = el(id);
  if (node) node.textContent = value;
}

function aliasProfileName(name) {
  if (!name) return name;
  return PROFILE_ALIAS[name] || name;
}

function profileLabel(profile) {
  if (!profile) return '-';
  const raw = profile.profileLabel || profile.profile || '-';
  return aliasProfileName(raw);
}

function botFamilyFromProfileName(nameRaw) {
  const s = String(nameRaw || '').toUpperCase();
  if (!s) return 'OTHER';
  if (s.includes('BLUEPRINT')) return 'BLUEPRINT';
  if (s.includes('NEXUS')) return 'NEXUS';
  if (s.includes('FRESH')) return 'FRESH';
  if (s.includes('DOMINION')) return 'DOMINION';
  if (s.includes('EDGE')) return 'EDGE';
  if (s.includes('SURGE')) return 'SURGE';
  if (s.includes('JORDAN') || s.includes('COPIER')) return 'COPIER';
  return 'OTHER';
}

function detectFeedMismatch(profileRows) {
  const rows = Array.isArray(profileRows) ? profileRows : [];
  const byFamily = new Map();
  for (const p of rows) {
    const family = botFamilyFromProfileName(p?.profileLabel || p?.profile || '');
    const server = String(
      p?.brokerServer
      || p?.server
      || p?.accountServer
      || p?.metrics?.brokerServer
      || ''
    ).trim();
    if (!server) continue;
    if (!byFamily.has(family)) byFamily.set(family, new Set());
    byFamily.get(family).add(server);
  }
  const mismatches = [];
  for (const [family, servers] of byFamily.entries()) {
    if (servers.size > 1) mismatches.push({ family, servers: [...servers] });
  }
  return mismatches.sort((a, b) => a.family.localeCompare(b.family));
}

function profileSortRank(name) {
  const raw = String(name || '');
  const upper = raw.toUpperCase();
  if (upper === 'BASE' || upper === 'PRESETS' || upper === 'UNKNOWN:BASE' || upper === 'UNKNOWN:PRESETS') return 9999;
  if (upper.includes('BLUEPRINT')) return 0;
  if (upper.includes('NEXUS')) return 1;
  if (upper.includes('FRESH')) return 2;
  if (upper.includes('DOMINION')) return 3;
  if (upper.includes('EDGE')) return 4;
  if (upper.includes('SURGE')) return 5;
  const idx = PROFILE_ORDER.indexOf(raw);
  return idx >= 0 ? idx : 999;
}

function isBaseOrPresetName(name) {
  const upper = String(name || '').toUpperCase();
  return (
    upper === 'BASE'
    || upper === 'PRESETS'
    || upper === 'UNKNOWN:BASE'
    || upper === 'UNKNOWN:PRESETS'
    || upper.endsWith(':BASE')
    || upper.endsWith(':PRESETS')
  );
}

function shouldHideProfileRow(row) {
  return isBaseOrPresetName(row?.profileLabel || row?.profile || row?.botName);
}

function shouldHideAccountSummaryRow(row) {
  const labels = [];
  if (Array.isArray(row?.profiles)) labels.push(...row.profiles);
  labels.push(row?.profileLabel, row?.profile, row?.botName);
  return labels.some((x) => isBaseOrPresetName(x));
}

function sortProfiles(rows) {
  return (Array.isArray(rows) ? rows : [])
    .slice()
    .sort((a, b) => {
      const ra = profileSortRank(a?.profile || '');
      const rb = profileSortRank(b?.profile || '');
      if (ra !== rb) return ra - rb;
      return String(a?.profile || '').localeCompare(String(b?.profile || ''));
    });
}

function timeSinceSeconds(ts) {
  const t = Date.parse(ts || '');
  if (!Number.isFinite(t)) return null;
  return Math.max(0, Math.round((Date.now() - t) / 1000));
}

function freshestTimestamp(...candidates) {
  let best = null;
  let bestMs = -1;
  for (const c of candidates) {
    const ms = Date.parse(c || '');
    if (!Number.isFinite(ms)) continue;
    if (ms > bestMs) {
      bestMs = ms;
      best = c;
    }
  }
  return best;
}

function pushActionAudit(entry) {
  const arr = JSON.parse(localStorage.getItem(AUDIT_KEY) || '[]');
  arr.unshift(entry);
  while (arr.length > 80) arr.pop();
  localStorage.setItem(AUDIT_KEY, JSON.stringify(arr));
  return arr;
}

function readActionAudit() {
  return JSON.parse(localStorage.getItem(AUDIT_KEY) || '[]');
}

function pushHistoryPoint(label, value) {
  const key = 'ops_runtime_history';
  const arr = JSON.parse(localStorage.getItem(key) || '[]');
  arr.push({ t: Date.now(), label, value });
  while (arr.length > 40) arr.shift();
  localStorage.setItem(key, JSON.stringify(arr));
  return arr;
}

function drawRuntimeChart(points) {
  const c = el('runtimeChart');
  if (!c) return;
  const ctx = c.getContext('2d');
  const w = c.width = c.clientWidth;
  const h = c.height = 90;
  ctx.clearRect(0, 0, w, h);
  ctx.strokeStyle = '#2b3a5a';
  ctx.beginPath();
  ctx.moveTo(0, h - 18);
  ctx.lineTo(w, h - 18);
  ctx.stroke();
  if (!points.length) return;

  const vals = points.map((p) => Number(p.value) || 0);
  const max = Math.max(1, ...vals);
  ctx.strokeStyle = '#4ea1ff';
  ctx.lineWidth = 2;
  ctx.beginPath();
  points.forEach((p, i) => {
    const x = (i / (points.length - 1 || 1)) * w;
    const y = (h - 18) - ((Number(p.value) || 0) / max) * (h - 28);
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.stroke();
}

function num(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

function firstFinite(...values) {
  for (const v of values) {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

function money(v, signed = true) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '-';
  if (!signed) return n.toFixed(2);
  return `${n >= 0 ? '+' : ''}${n.toFixed(2)}`;
}

function pct(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '-';
  return `${n.toFixed(2)}%`;
}

function openPnlValue(row) {
  const openPositions = num(row?.openPositions, 0);
  if (openPositions <= 0) return 0;
  const eq = Number(row?.currentEquity);
  const bal = Number(row?.currentBalance);
  const eqDiff = (Number.isFinite(eq) && Number.isFinite(bal)) ? (eq - bal) : null;
  const rawOpen = Number(row?.openProfit);
  if (Number.isFinite(rawOpen)) {
    if (eqDiff == null) return rawOpen;
    const rawIsZeroish = Math.abs(rawOpen) < 0.01;
    const eqHasSignal = Math.abs(eqDiff) >= 0.01;
    const oppositeSign = Math.abs(rawOpen) > 0.01 && eqHasSignal && Math.sign(rawOpen) !== Math.sign(eqDiff);
    const largeDrift = Math.abs(rawOpen - eqDiff) >= 25;
    if ((rawIsZeroish && eqHasSignal) || (oppositeSign && largeDrift)) return eqDiff;
    return rawOpen;
  }
  if (eqDiff != null) return eqDiff;
  return 0;
}

function fmtPf(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(2) : '-';
}

function inferRiskPctFromName(name) {
  const s = String(name || '').toUpperCase();
  if (!s) return null;
  if (/\b20\b|[_/-]20\b/.test(s) || s.includes('SILVER20')) return 20;
  if (/\b15\b|[_/-]15\b/.test(s) || s.includes('SILVER15')) return 15;
  if (s.includes('500_LEVERAGE')) return 9;
  if (s.includes('GOLD') || s.includes('SILVER') || s.includes('NEXUS') || s.includes('BLUEPRINT') || s.includes('EDGE') || s.includes('DOMINION') || s.includes('SURGE') || s.includes('FRESH')) return DEFAULT_RISK_PCT;
  return null;
}

function riskPctValue(row) {
  const candidates = [
    row?.riskPct,
    row?.avgRiskPct,
    row?.risk,
    row?.riskPercent,
    row?.risk_percentage,
  ];
  for (const c of candidates) {
    const n = Number(c);
    if (Number.isFinite(n) && n > 0) return n;
  }
  const fromName = inferRiskPctFromName(
    row?.profile
    || row?.profileLabel
    || row?.botName
    || (Array.isArray(row?.profiles) ? row.profiles[0] : '')
  );
  if (Number.isFinite(fromName)) return fromName;
  return null;
}

function depositStartEqValue(row) {
  const candidates = [
    row?.accountStartEquity,
    row?.depositStartingEq,
    row?.depositStartEq,
    row?.startEquity,
    row?.depositAmount,
    row?.dayStartEquity,
    row?.dayOpeningEquity,
    row?.dayBaseline,
  ];
  for (const c of candidates) {
    const n = Number(c);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return DEFAULT_DEPOSIT_START_EQ;
}

function withdrawUsdValue(row) {
  const candidates = [
    row?.withdrawAmount,
    row?.withdrawUsd,
    row?.withdraw,
    row?.withdrawalsUsd,
    row?.withdrawalUsd,
  ];
  for (const c of candidates) {
    const n = Number(c);
    if (Number.isFinite(n) && n >= 0) return n;
  }
  return DEFAULT_WITHDRAW_USD;
}

function totalBaselineValue(row) {
  const candidates = [
    row?.accountStartEquity,
    row?.startEquity,
    row?.depositStartingEq,
    row?.depositStartEq,
  ];
  for (const c of candidates) {
    const n = Number(c);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return null;
}

function totalNetValue(row) {
  const baseline = totalBaselineValue(row);
  const withdraw = Number(withdrawUsdValue(row));
  const eq = Number(row?.currentEquity ?? row?.equity ?? row?.currentBalance);
  if (Number.isFinite(baseline) && baseline > 0 && Number.isFinite(eq)) return Number((eq + (Number.isFinite(withdraw) ? withdraw : 0) - baseline).toFixed(2));
  const direct = Number(row?.totalNetUsd ?? row?.metrics?.total?.netUsd);
  if (Number.isFinite(direct)) return direct;
  return null;
}

function totalReturnPctValue(row) {
  const baseline = totalBaselineValue(row);
  const totalNet = totalNetValue(row);
  if (Number.isFinite(baseline) && baseline > 0 && Number.isFinite(totalNet)) return Number(((100 * totalNet) / baseline).toFixed(2));
  const direct = Number(row?.totalReturnPct ?? row?.metrics?.total?.returnPct);
  if (Number.isFinite(direct)) return direct;
  return null;
}

function dayReturnPctValue(row, dayNet = null, dayStartEq = null) {
  const directCandidates = [
    row?.dayReturnPct,
    row?.dayReturnPctRealized,
    row?.metrics?.day?.returnPctLive,
    row?.metrics?.day?.returnPct,
  ];
  for (const c of directCandidates) {
    const n = Number(c);
    if (Number.isFinite(n)) return n;
  }
  const baseline = firstFinite(
    dayStartEq,
    row?.dayStartEquity,
    row?.dayStartBalance,
    row?.dayBaseline,
    row?.metrics?.day?.equityBaseline,
    depositStartEqValue(row),
  );
  const net = Number(dayNet);
  if (Number.isFinite(baseline) && baseline > 0 && Number.isFinite(net)) {
    return Number(((100 * net) / baseline).toFixed(2));
  }
  return null;
}

function escapeHtml(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function maskAccount(v) {
  const raw = String(v ?? '').trim();
  if (!/^\d{6,}$/.test(raw)) return raw || '-';
  if (raw.length <= 6) return `${raw.slice(0, 2)}**${raw.slice(-2)}`;
  return `${raw.slice(0, 3)}***${raw.slice(-3)}`;
}

function grossPair(grossProfit, grossLoss) {
  return `${money(grossProfit)} / -${Math.abs(num(grossLoss)).toFixed(2)}`;
}

function dayMetrics(profile) {
  const m = profile?.metrics || {};
  if (m.day) {
    const d = m.day;
    const netUsdRealized = num(d.netUsd);
    const openFallback = num(d.openProfitUsd, openPnlValue(profile));
    const eqNow = firstFinite(profile?.currentEquity, profile?.currentBalance);
    const depositStartEq = depositStartEqValue(profile);
    let baseline = firstFinite(d.equityBaseline, profile?.dayStartEquity, profile?.dayStartBalance, depositStartEq);
    if (!Number.isFinite(baseline) || baseline <= 0) baseline = firstFinite(depositStartEq, eqNow);
    // Guard against stale/corrupt day baseline carried from an old account state.
    if (Number.isFinite(baseline) && baseline > 0 && Number.isFinite(eqNow)) {
      const cap = Math.max(eqNow * 1.8, (Number.isFinite(depositStartEq) ? depositStartEq * 1.8 : 0));
      if (baseline > cap && cap > 0) baseline = firstFinite(depositStartEq, eqNow, baseline);
    }
    if (Number.isFinite(baseline) && baseline > 0 && Number.isFinite(depositStartEq) && depositStartEq > 0) {
      if (baseline < (depositStartEq * 0.5)) baseline = depositStartEq;
    }
    const equityDelta = (Number.isFinite(eqNow) && Number.isFinite(baseline) && baseline > 0)
      ? Number((eqNow - baseline).toFixed(2))
      : null;
    const parsedLive = Number(d.netUsdLive);
    const parsedVsEquityDrift = Number.isFinite(parsedLive) && Number.isFinite(equityDelta)
      && Math.abs(parsedLive - equityDelta) > Math.max(250, Math.abs(eqNow || 0) * 0.2);
    const parsedLooksCorrupt = Number.isFinite(parsedLive) && Number.isFinite(eqNow)
      && Math.abs(parsedLive) > Math.max(5000, Math.abs(eqNow) * 3);
    const netUsdDisplay = (parsedLooksCorrupt || parsedVsEquityDrift)
      ? num(equityDelta, num(d.netUsdEst, netUsdRealized + openFallback))
      : num(d.netUsdLive, num(d.netUsdEst, netUsdRealized + openFallback));
    const returnPctDisplay = Number.isFinite(baseline) && baseline > 0
      ? Number(((100 * netUsdDisplay) / baseline).toFixed(2))
      : (d.returnPctLive ?? d.returnPctEst ?? d.returnPct);
    return {
      ...d,
      equityBaseline: baseline,
      netUsdDisplay,
      returnPctDisplay,
      netUsdRealized: d.netUsdRealized ?? netUsdRealized,
      returnPctRealized: d.returnPctRealized ?? d.returnPct,
    };
  }
  const netUsdRealized = num(m.netUsdEst ?? m.netUsd);
  const netUsdDisplay = netUsdRealized + openPnlValue(profile);
  const returnPctDisplay = num(m.equityBaseline) > 0 ? Number(((100 * netUsdDisplay) / num(m.equityBaseline)).toFixed(2)) : (m.returnPctEst ?? m.returnPct);
  return {
    wins: num(m.wins),
    losses: num(m.losses),
    breakeven: num(m.breakeven),
    winRatePct: m.winRatePct,
    grossProfitUsd: num(m.grossProfitUsd),
    grossLossUsd: num(m.grossLossUsd),
    netUsd: num(m.netUsdEst ?? m.netUsd),
    returnPct: m.returnPctEst ?? m.returnPct,
    matchRatePct: m.matchRatePct,
    matchedCloses: num(m.matchedCloses),
    closeRequests: num(m.closeRequests),
    unmatchedDeals: num(m.unmatchedDeals),
    profitFactor: m.profitFactor,
    netUsdDisplay,
    returnPctDisplay,
    netUsdRealized,
    returnPctRealized: m.returnPct,
  };
}

function buildClientOverview(profileSnapshots) {
  const profiles = Array.isArray(profileSnapshots) ? profileSnapshots : [];
  const ranked = profiles.map((p) => {
    const day = dayMetrics(p);
    const week = weekMetrics(p);
    const status = profileStatus(p);
    return {
      profile: p.profile,
      profileLabel: p.profileLabel || p.profile,
      status: status.label,
      reason: status.reason,
      matchedCloses: day.matchedCloses,
      dayNetUsd: num(day.netUsdDisplay, day.netUsd),
      dayRetPct: num(day.returnPctDisplay, day.returnPct),
      weekRetPct: num(week.returnPct),
      weekNetUsd: num(week.netUsd),
      profitFactor: day.profitFactor,
    };
  });

  const sortedDay = ranked.slice().sort((a, b) => b.dayRetPct - a.dayRetPct);
  const sortedWeek = ranked.slice().sort((a, b) => b.weekRetPct - a.weekRetPct);

  return {
    topWorking: sortedWeek
      .filter((p) => p.status === 'WORKING')
      .slice(0, 5),
    needsAttention: sortedDay
      .filter((p) => p.status === 'OVERTRADING' || p.status === 'FAILING')
      .slice(0, 6),
    leadersToday: sortedDay.slice(0, 3).map((p) => ({
      profile: p.profile,
      profileLabel: p.profileLabel,
      retPct: p.dayRetPct,
      netUsd: p.dayNetUsd,
    })),
    leadersWeek: sortedWeek.slice(0, 3).map((p) => ({
      profile: p.profile,
      profileLabel: p.profileLabel,
      retPct: p.weekRetPct,
      netUsd: p.weekNetUsd,
    })),
  };
}

function weekMetrics(profile) {
  const m = profile?.metrics || {};
  if (m.week) {
    const w = { ...m.week };
    const eq = num(profile?.currentEquity ?? profile?.currentBalance);
    const acctStart = num(profile?.accountStartEquity);
    const rawNet = num(w.netUsd);
    const baseline = num(w.equityBaseline);
    const cap = Math.max(10000, Math.abs(eq) * 6, Math.abs(acctStart) * 6);
    if (Math.abs(rawNet) > cap) {
      const recomputed = (baseline > 0 && baseline < cap * 4)
        ? Number((eq - baseline).toFixed(2))
        : Number(num(profile?.totalNetUsd).toFixed(2));
      w.netUsd = recomputed;
      if (baseline > 0) {
        w.returnPct = Number(((100 * w.netUsd) / baseline).toFixed(2));
      } else if (acctStart > 0) {
        w.returnPct = Number(((100 * w.netUsd) / acctStart).toFixed(2));
      }
    }
    return w;
  }
  return {
    wins: null,
    losses: null,
    netUsd: null,
    returnPct: null,
    grossProfitUsd: null,
    grossLossUsd: null,
    profitFactor: null,
  };
}

function monthMetrics(profile) {
  const m = profile?.metrics || {};
  if (m.month) {
    const mo = { ...m.month };
    const eq = num(profile?.currentEquity ?? profile?.currentBalance);
    const acctStart = num(profile?.accountStartEquity);
    const rawNet = num(mo.netUsd);
    const baseline = num(mo.equityBaseline);
    const cap = Math.max(15000, Math.abs(eq) * 8, Math.abs(acctStart) * 8);
    if (Math.abs(rawNet) > cap) {
      const recomputed = (baseline > 0 && baseline < cap * 4)
        ? Number((eq - baseline).toFixed(2))
        : Number(num(profile?.totalNetUsd).toFixed(2));
      mo.netUsd = recomputed;
      if (baseline > 0) {
        mo.returnPct = Number(((100 * mo.netUsd) / baseline).toFixed(2));
      } else if (acctStart > 0) {
        mo.returnPct = Number(((100 * mo.netUsd) / acctStart).toFixed(2));
      }
    }
    return mo;
  }
  return {
    wins: null,
    losses: null,
    netUsd: null,
    returnPct: null,
    grossProfitUsd: null,
    grossLossUsd: null,
    profitFactor: null,
  };
}

function profileStatus(profile) {
  const s = profile?.metrics?.status || {};
  return {
    label: s.label || 'WATCH',
    reason: s.reason || 'No status reason',
  };
}

function runtimeBadge(profile) {
  const drift = Boolean(profile?.runtimeDrift);
  return drift
    ? '<span class="badge badge-fail">DRIFT</span>'
    : '<span class="badge badge-ok">OK</span>';
}

function issueFaultsCell(profile) {
  const a = profile?.issueAudit || {};
  const chips = [];
  const pushIf = (v, label) => {
    const n = Number(v || 0);
    if (n > 0) chips.push(`<span class="status-chip negative">${label}:${n}</span>`);
  };
  pushIf(a.tp1CloseFailed, 'TP1Fail');
  pushIf(a.closeVolumeLow, 'CloseVol');
  pushIf(a.invalidStops, 'Stops');
  pushIf(a.offQuotes, 'Quotes');
  pushIf(a.tradeContextBusy, 'Busy');
  pushIf(a.licenseOrAuth, 'Auth');
  pushIf(a.orderSendFailed, 'Send');
  if (!chips.length) return '<span class="status-chip positive">None</span>';
  const hintsRaw = [a.sampleTp1, a.sampleCloseVol, a.sampleStops, a.sampleExec].filter(Boolean).join(' || ');
  const hints = String(hintsRaw || 'faults detected').replace(/"/g, '&quot;');
  return `<span title="${hints}">${chips.join(' ')}</span>`;
}

function renderFilters(profiles) {
  const node = el('filters');
  if (!node) return;
  const keys = ['ALL', ...profiles.map((p) => p.profile)];
  node.innerHTML = '';
  keys.forEach((k) => {
    const b = document.createElement('button');
    b.className = 'filter-btn' + (activeFilter === k ? ' active' : '');
    if (k === 'ALL') {
      b.textContent = k;
    } else {
      const p = profiles.find((x) => x.profile === k);
      b.textContent = p ? profileLabel(p) : k;
    }
    b.onclick = () => {
      activeFilter = k;
      load();
    };
    node.appendChild(b);
  });
}

function wireTabs() {
  const tabs = document.querySelectorAll('.tab');
  tabs.forEach((t) => {
    t.onclick = () => {
      tabs.forEach((x) => x.classList.remove('active'));
      t.classList.add('active');
      const k = t.dataset.tab;
      document.querySelectorAll('.tab-pane').forEach((p) => {
        p.classList.toggle('hidden', p.dataset.pane !== k);
      });
    };
  });
}

function wireControls() {
  document.querySelectorAll('.ctl').forEach((btn) => {
    btn.onclick = async () => {
      const action = btn.dataset.action;
      const out = el('controlOut');
      out.textContent = `Running ${action}...`;
      try {
        const r = await fetch(`/api/control/${action}`, { method: 'POST' });
        const j = await r.json();
        out.textContent = JSON.stringify(j, null, 2);
        pushActionAudit({
          at: new Date().toISOString(),
          action,
          ok: j?.ok !== false,
          detail: j?.error || j?.stderr || (j?.ok ? 'ok' : 'failed'),
        });
        renderActionAudit();
      } catch (e) {
        const msg = e?.message || String(e);
        out.textContent = `Control error: ${msg}`;
        pushActionAudit({
          at: new Date().toISOString(),
          action,
          ok: false,
          detail: msg,
        });
        renderActionAudit();
      }
    };
  });
}

function setSignedClass(id, value) {
  const node = el(id);
  if (!node) return;
  node.classList.remove('positive', 'negative');
  const n = Number(value);
  if (!Number.isFinite(n)) return;
  node.classList.add(n >= 0 ? 'positive' : 'negative');
}

function renderSummaryCards(data) {
  const s = data.summary || {};
  const v = data.vps || {};
  const telemetry = data.telemetry || {};
  const clientOverview = buildClientOverview(telemetry?.profiles || []);
  const ts = telemetry.summary || {};
  const day = ts.day || {};
  const week = ts.week || {};
  const statusCounts = ts.statusCounts || {};
  const dayNetDisplay = num(day.netUsdLive, num(day.netUsd) + num(ts.totalOpenProfitUsd));
  const dayRetDisplay = day.returnPctLive
    ?? (num(day.baseline) > 0 ? Number(((100 * dayNetDisplay) / num(day.baseline)).toFixed(2)) : day.returnPct);

  const verdict = s.verdict || '-';
  const verdictNode = el('verdict');
  if (verdictNode) {
    verdictNode.textContent = verdict;
    const verdictOk = verdict === 'PASS' || verdict === 'LIVE';
    verdictNode.className = 'badge ' + (verdictOk ? 'badge-ok' : (verdict === 'FAIL' ? 'badge-fail' : 'badge-warn'));
  }

  setText('branch', `Branch: ${s.branch || '-'}`);
  setText('bot', `Focus bot: ${s.bot || '-'}`);
  const leader = (clientOverview.leadersToday || [])[0] || (clientOverview.leadersWeek || [])[0] || null;
  setText('bestBotNow', leader ? `${aliasProfileName(leader.profileLabel || leader.profile)} (${pct(leader.retPct)})` : '-');

  setText('telemetryUpdated', telemetry.generatedAt ? `Generated: ${new Date(telemetry.generatedAt).toLocaleTimeString()}` : 'No telemetry file yet');
  const profileRows = Array.isArray(telemetry.profiles) ? telemetry.profiles : [];
  const openProfilesHint = profileRows.filter((p) => Math.abs(openPnlValue(p)) > 0.01).length;
  const openPosRaw = num(ts.totalOpenPositions);
  const openPosLabel = openPosRaw > 0 ? String(openPosRaw) : (openProfilesHint > 0 ? `~${openProfilesHint}+ (PnL hint)` : '0');
  setText('openPositionsTotal', `Open positions: ${openPosLabel}`);
  setText('openOrdersTotal', `Open orders: ${ts.totalOpenOrders ?? '-'}`);
  setText('profilesSyncTotal', `Profiles with sync: ${ts.profilesWithSync ?? '-'}/${ts.profilesTotal ?? '-'}`);

  setText('dayNetUsd', `${money(dayNetDisplay)} USD`);
  setText('dayGrossUsd', `Realized gross +${num(day.grossProfitUsd).toFixed(2)} / -${Math.abs(num(day.grossLossUsd)).toFixed(2)} | W/L ${day.wins ?? 0}/${day.losses ?? 0}`);
  setText('dayLossUsd', `Realized losses: -${Math.abs(num(day.grossLossUsd)).toFixed(2)} USD`);
  setText('dayRates', `Live Ret ${pct(dayRetDisplay)} | Realized ${money(day.netUsd)} | Win ${pct(day.winRatePct)} | PF ${fmtPf(day.profitFactor)}`);
  setSignedClass('dayNetUsd', dayNetDisplay);

  setText('weekNetUsd', `${money(week.netUsd)} USD`);
  setText('weekGrossUsd', `Gross +${num(week.grossProfitUsd).toFixed(2)} / -${Math.abs(num(week.grossLossUsd)).toFixed(2)} | W/L ${week.wins ?? 0}/${week.losses ?? 0}`);
  setText('weekLossUsd', `Net losses: -${Math.abs(num(week.grossLossUsd)).toFixed(2)} USD`);
  setText('weekRates', `Ret ${pct(week.returnPct)} | Win ${pct(week.winRatePct)} | PF ${fmtPf(week.profitFactor)}`);
  setSignedClass('weekNetUsd', week.netUsd);

  const balanceTotal = num(ts.estimatedCurrentBalanceTotal);
  const equityTotal = num(ts.estimatedCurrentEquityTotal);
  const openPnlFromProfiles = profileRows.reduce((sum, p) => sum + openPnlValue(p), 0);
  const openPnlRaw = Number(ts.totalOpenProfitUsd);
  let openPnl = Number.isFinite(openPnlRaw) ? openPnlRaw : openPnlFromProfiles;
  if (
    Number.isFinite(openPnlRaw) &&
    Math.abs(openPnlRaw - openPnlFromProfiles) >= 50 &&
    Math.abs(openPnlFromProfiles) >= 0.01
  ) {
    openPnl = openPnlFromProfiles;
  }
  const coverage = ts.balanceCoveragePct;
  setText('totalBalanceUsd', `${money(balanceTotal, false)} USD bal | ${money(equityTotal, false)} USD eq`);
  setText('openPnlUsd', `Open PnL: ${money(openPnl)} USD`);
  setSignedClass('openPnlUsd', openPnl);
  setText(
    'qualityCounts',
    `WORKING ${statusCounts.WORKING || 0} | OVERTRADING ${statusCounts.OVERTRADING || 0} | FAILING ${statusCounts.FAILING || 0} | WATCH ${statusCounts.WATCH || 0} | DRIFT ${ts.runtimeDriftProfiles || 0} | Exact ${ts.balanceExactProfiles || 0}/${ts.profilesTotal || 0} (${pct(coverage)})`,
  );

  setText('terminals', `terminal64: ${v.terminal64_count ?? '-'}`);
  setText('metaeditors', `metaeditor64: ${v.metaeditor64_count ?? '-'}`);
  const feedMismatch = detectFeedMismatch(profileRows);
  if (!feedMismatch.length) {
    setText('feedMismatchState', 'Feed check: OK (single server per bot family)');
  } else {
    const brief = feedMismatch
      .slice(0, 3)
      .map((m) => `${m.family}(${m.servers.join(' vs ')})`)
      .join(' | ');
    setText('feedMismatchState', `Feed mismatch: ${brief}${feedMismatch.length > 3 ? ' …' : ''}`);
  }

  const openRiskPct = equityTotal > 0 ? (Math.abs(openPnl) / equityTotal) * 100 : 0;
  const failingCount = (statusCounts.FAILING || 0) + (statusCounts.OVERTRADING || 0);
  const feedRows = Array.isArray(data.liveFeed) ? data.liveFeed : [];
  const breachHits = feedRows.filter((e) => /DAILY LOSS GUARD TRIPPED|ERROR|FAILED|NO MONEY|ABORT/i.test(String(e?.text || ''))).length;
  const totalAlerts = failingCount + breachHits;
  const staleProfiles = profileRows.filter((p) => {
    const freshTs = freshestTimestamp(p?.lastSyncAt, p?.snapshotAt, p?.lastActivityAt);
    const age = timeSinceSeconds(freshTs);
    return age === null || age > 120;
  });

  setText('execTotalEquity', `${money(equityTotal, false)} USD`);
  setText('execTotalBalance', `Balance ${money(balanceTotal, false)} USD`);
  setText('execDayReturn', pct(dayRetDisplay));
  setText('execDayPnl', `Live ${money(dayNetDisplay)} USD`);
  setText('execWeekReturn', pct(week.returnPct));
  setText('execWeekPnl', `Net ${money(week.netUsd)} USD`);
  setText('execOpenRisk', pct(openRiskPct));
  setText('execExposure', `${openPosLabel} open positions | ${money(openPnl)} USD`);
  setText('execAlerts', `${totalAlerts}`);
  setText('execAlertNote', `Status alerts ${failingCount} | Feed alerts ${breachHits}`);
  setSignedClass('execDayReturn', dayRetDisplay);
  setSignedClass('execWeekReturn', week.returnPct);
  setSignedClass('execOpenRisk', -openRiskPct);
  setSignedClass('execAlerts', -totalAlerts);

  const telemetryAge = timeSinceSeconds(telemetry.generatedAt);
  const freshNode = el('freshnessBadge');
  if (freshNode) {
    if (telemetryAge === null) freshNode.innerHTML = '<span class="badge badge-warn">NO TELEMETRY</span>';
    else if (telemetryAge <= 25) freshNode.innerHTML = `<span class="badge badge-ok">LIVE (${telemetryAge}s)</span>`;
    else if (telemetryAge <= 90) freshNode.innerHTML = `<span class="badge badge-warn">LAG (${telemetryAge}s)</span>`;
    else freshNode.innerHTML = `<span class="badge badge-fail">STALE (${telemetryAge}s)</span>`;
  }
  setText(
    'staleWarnings',
    staleProfiles.length
      ? `Stale profiles (${staleProfiles.length}): ${staleProfiles.slice(0, 4).map((p) => profileLabel(p)).join(', ')}${staleProfiles.length > 4 ? '…' : ''}`
      : 'All profile feeds fresh',
  );
  const dh = data.discordHealth || {};
  setText('discordState', dh.connected ? `Discord: connected via ${dh.source || 'health'}` : 'Discord: disconnected');
  setText('lastUpdated', 'Updated ' + new Date().toLocaleTimeString());
}

function renderCompilerView(summary) {
  const profiles = sortProfiles(summary.profiles || []);
  renderFilters(profiles);

  const tbody = document.querySelector('#profiles tbody');
  if (tbody) {
    tbody.innerHTML = '';
    profiles
      .filter((p) => activeFilter === 'ALL' ? true : p.profile === activeFilter)
      .forEach((p) => {
        const tr = document.createElement('tr');
        const c = p.compile?.status ?? '-';
        const chip = c === 'ok'
          ? '<span class="badge badge-ok">OK</span>'
          : (c === 'fail'
            ? '<span class="badge badge-fail">FAIL</span>'
            : '<span class="badge badge-warn">UNKNOWN</span>');
        tr.innerHTML = `<td title="Profile ID: ${p.profile}">${profileLabel(p)}</td><td>${chip}</td><td>${p.compile?.errors ?? '-'}</td><td>${p.compile?.warnings ?? '-'}</td><td>${p.runtime_critical_hits ?? '-'}</td>`;
        tbody.appendChild(tr);
      });
  }

  const cards = el('botCards');
  if (!cards) return;
  cards.innerHTML = '';
  profiles.forEach((p) => {
    const c = p.compile?.status ?? 'unknown';
    const ring = c === 'ok' ? 'ring-ok' : (c === 'fail' ? 'ring-fail' : 'ring-warn');
    const div = document.createElement('div');
    div.className = 'bot-card';
    div.innerHTML = `<div><span class='ring ${ring}'></span><b>${profileLabel(p)}</b></div><div class='muted'>Compile: ${c}</div><div class='muted'>Runtime hits: ${p.runtime_critical_hits ?? 0}</div>`;
    cards.appendChild(div);
  });
}

function renderAccountSummary(accounts) {
  const tbody = document.querySelector('#accountSummary tbody');
  if (!tbody) return;
  tbody.innerHTML = '';

  const rows = (Array.isArray(accounts) ? accounts : []).filter((r) => !shouldHideAccountSummaryRow(r));
  if (!rows.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="22">No account telemetry yet.</td>';
    tbody.appendChild(tr);
    return;
  }

  rows.forEach((a) => {
    const dayNet = num(a.dayNetLiveUsd ?? a.dayNetUsd);
    const weekNet = num(a.weekNetUsd);
    const totalNet = totalNetValue(a);
    const totalRet = totalReturnPctValue(a);
    const dayWinPct = num(a.dayMatchedCloses) > 0 ? Number(((100 * num(a.dayWins)) / num(a.dayMatchedCloses)).toFixed(2)) : null;
    const tr = document.createElement('tr');
    const depositStartEq = depositStartEqValue(a);
    const dayStartEq = firstFinite(a.dayStartEquity, a.dayBaseline, a.dayOpeningEquity, depositStartEq);
    const dayRet = dayReturnPctValue(a, dayNet, dayStartEq);
    const withdrawUsd = withdrawUsdValue(a);
    const wl = `${a.dayWins ?? 0}/${a.dayLosses ?? 0}`;
    const riskPct = riskPctValue(a);
    tr.innerHTML = `
      <td>${maskAccount(a.account)}</td>
      <td>${money(depositStartEq, false)}</td>
      <td>${money(withdrawUsd, false)}</td>
      <td>${money(dayStartEq, false)}</td>
      <td>${pct(riskPct)}</td>
      <td>${wl}</td>
      <td>${a.openPositions ?? 0}</td>
      <td>${pct(dayRet)}</td>
      <td>${pct(a.weekReturnPct)}</td>
      <td>${pct(a.monthReturnPct)}</td>
      <td>${pct(dayWinPct)}</td>
      <td>${pct(a.buyPct)}</td>
      <td>${pct(a.sellPct)}</td>
      <td>${fmtPf(a.dayProfitFactor)} / ${fmtPf(a.weekProfitFactor)} / ${fmtPf(a.monthProfitFactor)}</td>
      <td class="${dayNet >= 0 ? 'positive' : 'negative'}" title="Realized: ${money(a.dayNetUsd)}">${money(dayNet)}</td>
      <td class="${weekNet >= 0 ? 'positive' : 'negative'}">${money(weekNet)}</td>
      <td class="${num(totalNet) >= 0 ? 'positive' : 'negative'}">${money(totalNet)}</td>
      <td class="${num(totalRet) >= 0 ? 'positive' : 'negative'}">${pct(totalRet)}</td>
      <td class="${num(a.openProfit) >= 0 ? 'positive' : 'negative'}">${money(a.openProfit)}</td>
      <td class="${num(a.currentBalance) >= 0 ? 'positive' : 'negative'}">${money(a.currentBalance, false)}</td>
      <td>${Array.isArray(a.profiles) ? a.profiles.length : 0}</td>
    `;
    tbody.appendChild(tr);
  });
}

function renderCopierFeed(feed) {
  const tbody = document.querySelector('#copierFeed tbody');
  if (!tbody) return;
  tbody.innerHTML = '';
  const rows = Array.isArray(feed?.rows) ? feed.rows : [];
  if (!rows.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="20">No copier accounts configured yet.</td>';
    tbody.appendChild(tr);
    return;
  }
  rows.forEach((r) => {
    const tr = document.createElement('tr');
    const updated = r.updatedAt ? new Date(r.updatedAt).toLocaleTimeString() : '-';
    const currentPnlTotal = firstFinite(r.currentPnlWithOpen, r.currentPnlGross);
    tr.innerHTML = `
      <td>${aliasProfileName(r.profileLabel || r.profile || '-')}</td>
      <td>${maskAccount(r.account || '-')}</td>
      <td>${r.client || '-'}</td>
      <td>${r.botName || '-'}</td>
      <td>${pct(r.riskPct)}</td>
      <td>${r.leverage || '-'}</td>
      <td>${money(r.depositAmount, false)}</td>
      <td>${money(r.withdrawAmount, false)}</td>
      <td>${money(r.accountStartEquity, false)}</td>
      <td>${money(r.dayStartEquity, false)}</td>
      <td>${money(r.balance, false)}</td>
      <td>${money(r.equity, false)}</td>
      <td class="${num(r.openProfit) >= 0 ? 'positive' : 'negative'}">${money(r.openProfit)}</td>
      <td class="${num(currentPnlTotal) >= 0 ? 'positive' : 'negative'}">${money(currentPnlTotal)}</td>
      <td class="${num(r.dayNetUsd) >= 0 ? 'positive' : 'negative'}">${money(r.dayNetUsd)}</td>
      <td class="${num(r.dayReturnPct) >= 0 ? 'positive' : 'negative'}">${pct(r.dayReturnPct)}</td>
      <td class="${num(r.weekNetUsd) >= 0 ? 'positive' : 'negative'}">${money(r.weekNetUsd)}</td>
      <td class="${num(r.weekReturnPct) >= 0 ? 'positive' : 'negative'}">${pct(r.weekReturnPct)}</td>
      <td>${r.status || '-'}</td>
      <td>${updated}</td>
    `;
    tbody.appendChild(tr);
  });
}

function renderPerformanceOverview(overview) {
  const topList = el('topWorkingList');
  const attentionList = el('attentionList');
  if (!topList || !attentionList) return;

  const topWorking = Array.isArray(overview?.topWorking) ? overview.topWorking : [];
  const attention = Array.isArray(overview?.needsAttention) ? overview.needsAttention : [];

  topList.innerHTML = '';
  attentionList.innerHTML = '';

  if (!topWorking.length) {
    const li = document.createElement('li');
    li.textContent = 'No WORKING profiles yet.';
    topList.appendChild(li);
  } else {
    topWorking.forEach((p) => {
      const li = document.createElement('li');
      li.innerHTML = `<b>${aliasProfileName(p.profileLabel || p.profile)}</b> day ${pct(p.dayRetPct)} (${money(p.dayNetUsd)}), week ${pct(p.weekRetPct)}`;
      topList.appendChild(li);
    });
  }

  if (!attention.length) {
    const li = document.createElement('li');
    li.textContent = 'No profiles flagged for attention.';
    attentionList.appendChild(li);
  } else {
    attention.forEach((p) => {
      const li = document.createElement('li');
      li.innerHTML = `<b>${aliasProfileName(p.profileLabel || p.profile)}</b> ${p.status}: ${p.reason}. Trades ${p.matchedCloses}, day ${money(p.dayNetUsd)} (${pct(p.dayRetPct)}), PF ${fmtPf(p.profitFactor)}`;
      attentionList.appendChild(li);
    });
  }
}

function parsePositionFromText(text, ts) {
  const m = String(text || '').match(/Position #(\d+)\s+\|\s+Type=(BUY|SELL)\s+\|\s+Open=([0-9.]+)\s+\|\s+Current=([0-9.]+)\s+\|\s+Profit=([-\d.]+)\s+pips\s+\|\s+SL=([0-9.]+)\s+\|\s+TP=([0-9.]+)/i);
  if (!m) return null;
  return {
    ticket: m[1],
    type: m[2],
    open: m[3],
    current: m[4],
    pips: Number(m[5]),
    sl: m[6],
    tp: m[7],
    ts,
  };
}

function renderSelectedProfileDrilldown(profile) {
  setText('selectedTitle', profile ? profileLabel(profile) : '-');
  if (!profile) {
    setText('selectedSnapshot', 'Select a profile row to inspect.');
    const ladder = document.querySelector('#positionLadder tbody');
    if (ladder) ladder.innerHTML = '<tr><td colspan="8">No profile selected.</td></tr>';
    const actions = el('profileActions');
    if (actions) actions.innerHTML = '<li>No actions.</li>';
    setText('selectedHealth', '');
    return;
  }

  const day = dayMetrics(profile);
  const week = weekMetrics(profile);
  const syncAge = timeSinceSeconds(freshestTimestamp(profile.lastSyncAt, profile.snapshotAt, profile.lastActivityAt));
  const month = monthMetrics(profile);
  const riskPct = riskPctValue(profile);
  const snap = `Acct ${maskAccount(profile.account || '-')} | Risk ${pct(riskPct)} | Bal ${money(profile.currentBalance, false)} | Eq ${money(profile.currentEquity, false)} | Open ${money(openPnlValue(profile))} | Day ${money(day.netUsdDisplay)} (${pct(day.returnPctDisplay)}) | Week ${money(week.netUsd)} (${pct(week.returnPct)}) | Month ${money(month.netUsd)} (${pct(month.returnPct)}) | Sync ${syncAge == null ? '-' : `${syncAge}s`}`;
  setText('selectedSnapshot', snap);

  const recent = Array.isArray(profile.recentEvents) ? profile.recentEvents : [];
  const shouldTrigger = recent.find((e) => /Should trigger BE:/i.test(e.text || ''));
  const tpHitState = recent.find((e) => /tp1Hit:\s*(true|false)/i.test(e.text || ''));
  const tpLevels = recent.find((e) => /TP Levels:/i.test(e.text || ''));
  const beSet = recent.find((e) => /BE SET|BE BACKSTOP SET|BE already set/i.test(e.text || ''));
  const status = profileStatus(profile);
  const health = el('selectedHealth');
  if (health) {
    const s1 = shouldTrigger ? (String(shouldTrigger.text).match(/Should trigger BE:\s*(true|false)/i)?.[1] || '-') : '-';
    const s2 = tpHitState ? (String(tpHitState.text).match(/tp1Hit:\s*(true|false)/i)?.[1] || '-') : '-';
    const cls1 = s1 === 'true' ? 'positive' : (s1 === 'false' ? 'negative' : '');
    const cls2 = s2 === 'true' ? 'positive' : (s2 === 'false' ? 'negative' : '');
    health.innerHTML = `
      <span class="status-chip ${status.label}">${status.label}</span>
      <span class="status-chip ${cls1}">BE Trigger ${s1}</span>
      <span class="status-chip ${cls2}">TP1 Hit ${s2}</span>
      <span class="status-chip">${beSet ? 'BE SET' : 'BE pending'}</span>
      <span class="status-chip">${tpLevels ? 'TP map loaded' : 'TP map n/a'}</span>
    `;
  }

  const ladderRows = [];
  recent.forEach((e) => {
    const p = parsePositionFromText(e.text, e.t || Date.parse(e.ts || ''));
    if (p) ladderRows.push(p);
  });
  const unique = [];
  const seen = new Set();
  ladderRows.sort((a, b) => (b.ts || 0) - (a.ts || 0)).forEach((r) => {
    if (seen.has(r.ticket)) return;
    seen.add(r.ticket);
    unique.push(r);
  });
  const ladder = document.querySelector('#positionLadder tbody');
  if (ladder) {
    ladder.innerHTML = '';
    if (!unique.length) {
      ladder.innerHTML = '<tr><td colspan="8">No parsed position ladder events yet.</td></tr>';
    } else {
      unique.slice(0, 10).forEach((r) => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
          <td>${r.ticket}</td>
          <td>${r.type}</td>
          <td>${r.open}</td>
          <td>${r.current}</td>
          <td class="${num(r.pips) >= 0 ? 'positive' : 'negative'}">${num(r.pips).toFixed(1)}</td>
          <td>${r.sl}</td>
          <td>${r.tp}</td>
          <td>${r.ts ? new Date(r.ts).toLocaleTimeString() : '-'}</td>
        `;
        ladder.appendChild(tr);
      });
    }
  }

  const actions = el('profileActions');
  if (actions) {
    actions.innerHTML = '';
    if (!recent.length) {
      actions.innerHTML = '<li>No actions.</li>';
    } else {
      recent.slice(0, 20).forEach((e) => {
        const li = document.createElement('li');
        const t = e.t ? new Date(e.t).toLocaleTimeString() : (e.ts || '-');
        li.innerHTML = `<b>${t}</b> ${e.text || '-'}`;
        actions.appendChild(li);
      });
    }
  }
}

function renderLiveProfiles(telemetry) {
  const rows = sortProfiles(telemetry?.profiles || []).filter((r) => !shouldHideProfileRow(r));
  const tbody = document.querySelector('#liveProfiles tbody');
  if (!tbody) return;
  tbody.innerHTML = '';

  if (!rows.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="28">No telemetry profiles yet.</td>';
    tbody.appendChild(tr);
    renderSelectedProfileDrilldown(null);
    return;
  }

  if (!selectedProfile || !rows.some((r) => r.profile === selectedProfile)) {
    selectedProfile = rows[0].profile;
  }

  rows.forEach((p) => {
    const day = dayMetrics(p);
    const week = weekMetrics(p);
    const month = monthMetrics(p);
    const status = profileStatus(p);
    const openPnl = openPnlValue(p);
    const dayNetDisplay = num(day.netUsdDisplay ?? day.netUsd);
    const openPosKnown = num(p.openPositions);
    const openPosHinted = openPosKnown <= 0 && Math.abs(openPnl) > 0.01;
    const openPosText = openPosHinted ? '~1+' : String(p.openPositions ?? '-');
    const depositStartEq = depositStartEqValue(p);
    const dayStartEq = firstFinite(p.dayStartEquity, p.dayOpeningEquity, p.dayBaseline, depositStartEq);
    const dayRetDisplay = dayReturnPctValue(p, dayNetDisplay, dayStartEq) ?? (day.returnPctDisplay ?? day.returnPct);
    const withdrawUsd = withdrawUsdValue(p);
    const weekNetDisplay = num(week.netUsd);
    const totalNet = totalNetValue(p);
    const totalRet = totalReturnPctValue(p);
    const riskPct = riskPctValue(p);
    const leverage = p.leverage || '-';
    const leverageLabel = (p.leverageSource === 'equity-tier-estimate' && leverage !== '-') ? `~${leverage}` : leverage;
    const runtime = runtimeBadge(p);
    const runtimeReason = Array.isArray(p.runtimeDriftReasons) && p.runtimeDriftReasons.length ? p.runtimeDriftReasons.join(', ') : 'runtime synced';
    const charts = Number.isFinite(num(p.chartCount, NaN)) ? `${num(p.chartCount, 0)}` : '-';
    const wl = `${day.wins ?? 0}/${day.losses ?? 0}`;

    const tr = document.createElement('tr');
    if (p.profile === selectedProfile) tr.classList.add('selected-row');
    if (status.label === 'WORKING') tr.classList.add('status-working');
    if (status.label === 'OVERTRADING') tr.classList.add('status-overtrading');
    if (status.label === 'FAILING') tr.classList.add('status-failing');
    if (p.runtimeDrift) tr.classList.add('status-failing');

    tr.innerHTML = `
      <td title="Profile ID: ${p.profile}">${profileLabel(p)}</td>
      <td title="${p.symbols || '-'}">${p.botName || '-'}</td>
      <td>${maskAccount(p.account || '-')}</td>
      <td title="Source: baseline">${money(depositStartEq, false)}</td>
      <td title="Source: broker cashflow feed (default 0 when unavailable)">${money(withdrawUsd, false)}</td>
      <td title="Locked day baseline ${p.dayStartLocked ? '(locked)' : '(estimated)'}">${Number.isFinite(dayStartEq) ? dayStartEq.toFixed(2) : '-'}</td>
      <td>${pct(riskPct)}</td>
      <td title="Source: ${p.leverageSource || 'none'}">${leverageLabel}</td>
      <td>${wl}</td>
      <td class="${openPnl >= 0 ? 'positive' : 'negative'}">${money(openPnl)}</td>
      <td class="col-open-trades" title="${openPosHinted ? 'Estimated from open PnL (terminal sync count unavailable)' : 'Terminal/mql sync count'}">${openPosText}</td>
      <td title="Source: ${p.balanceSource || 'derived'}">${money(p.currentBalance, false)}${p.balanceSource === 'snapshot' ? '' : ' ~'}</td>
      <td class="${dayNetDisplay >= 0 ? 'positive' : 'negative'}" title="Realized: ${money(day.netUsdRealized)}">${money(dayNetDisplay)}</td>
      <td class="${weekNetDisplay >= 0 ? 'positive' : 'negative'}">${money(weekNetDisplay)}</td>
      <td class="${num(totalNet) >= 0 ? 'positive' : 'negative'}">${money(totalNet)}</td>
      <td class="${num(totalRet) >= 0 ? 'positive' : 'negative'}">${pct(totalRet)}</td>
      <td class="${num(dayRetDisplay) >= 0 ? 'positive' : 'negative'}" title="Realized: ${pct(day.returnPctRealized)}">${pct(dayRetDisplay)}</td>
      <td class="${num(week.returnPct) >= 0 ? 'positive' : 'negative'}">${pct(week.returnPct)}</td>
      <td class="${num(month.returnPct) >= 0 ? 'positive' : 'negative'}">${pct(month.returnPct)}</td>
      <td>${pct(day.winRatePct)}</td>
      <td>${pct(day.buyPct)}</td>
      <td>${pct(day.sellPct)}</td>
      <td>${fmtPf(day.profitFactor)} / ${fmtPf(week.profitFactor)} / ${fmtPf(month.profitFactor)}</td>
      <td title="${runtimeReason}">${runtime}</td>
      <td title="taskConfigMode=${p.taskConfigMode || '-'} | profileLast=${p.profileLast || '-'}">${charts}</td>
      <td>${issueFaultsCell(p)}</td>
      <td><span class="status-chip ${status.label}">${status.label}</span></td>
      <td title="${status.reason}">${p.lastActivityAt ? new Date(p.lastActivityAt).toLocaleTimeString() : '-'}</td>
    `;

    tr.onclick = () => {
      selectedProfile = p.profile;
      renderLiveProfiles(telemetry);
    };
    tbody.appendChild(tr);
  });

  const selected = rows.find((r) => r.profile === selectedProfile) || rows[0];
  renderSelectedProfileDrilldown(selected);
  renderProfileChartView(selected, telemetry);
}

function resolveProfileSymbol(profile) {
  const symbolsRaw = String(profile?.symbols || '').toUpperCase();
  if (symbolsRaw.includes('XAG')) return 'XAGUSD';
  if (symbolsRaw.includes('XAU')) return 'XAUUSD';
  const name = `${profile?.profile || ''} ${profile?.profileLabel || ''} ${profile?.botName || ''}`.toUpperCase();
  if (name.includes('SILVER')) return 'XAGUSD';
  return 'XAUUSD';
}

function drawCandles(canvas, candles, markers = []) {
  const ctx = canvas?.getContext?.('2d');
  if (!ctx) return;
  const dpr = window.devicePixelRatio || 1;
  const width = Math.max(320, canvas.clientWidth || 320);
  const height = Math.max(220, canvas.clientHeight || 260);
  canvas.width = Math.floor(width * dpr);
  canvas.height = Math.floor(height * dpr);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, width, height);

  const bars = Array.isArray(candles) ? candles.filter((c) => Number.isFinite(num(c?.open, NaN))) : [];
  if (!bars.length) {
    ctx.fillStyle = '#5e6b76';
    ctx.font = '13px "IBM Plex Mono", monospace';
    ctx.fillText('Waiting for live candle data...', 12, 24);
    return;
  }

  let min = Infinity;
  let max = -Infinity;
  bars.forEach((b) => {
    min = Math.min(min, num(b.low, b.open));
    max = Math.max(max, num(b.high, b.open));
  });
  if (!Number.isFinite(min) || !Number.isFinite(max)) return;
  if (max === min) {
    max += 0.1;
    min -= 0.1;
  }

  const padTop = 10;
  const padBottom = 18;
  const padLeft = 8;
  const padRight = 8;
  const plotH = height - padTop - padBottom;
  const plotW = width - padLeft - padRight;
  const candleStep = plotW / Math.max(bars.length, 1);
  const bodyW = Math.max(2, Math.floor(candleStep * 0.56));
  const toY = (p) => padTop + ((max - p) / (max - min)) * plotH;

  bars.forEach((b, i) => {
    const open = num(b.open);
    const high = num(b.high, open);
    const low = num(b.low, open);
    const close = num(b.close, open);
    const x = Math.floor(padLeft + i * candleStep + candleStep / 2);
    const yOpen = toY(open);
    const yClose = toY(close);
    const yHigh = toY(high);
    const yLow = toY(low);
    const up = close >= open;
    const color = up ? '#2ea67d' : '#d75b5b';
    ctx.strokeStyle = color;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x, yHigh);
    ctx.lineTo(x, yLow);
    ctx.stroke();

    const bodyTop = Math.min(yOpen, yClose);
    const bodyH = Math.max(1, Math.abs(yClose - yOpen));
    ctx.fillStyle = color;
    ctx.fillRect(Math.floor(x - bodyW / 2), bodyTop, bodyW, bodyH);
  });

  drawTradeMarkers(ctx, width, height, bars, markers);
}

function normalizeAccount(value) {
  const digits = String(value || '').replace(/\D/g, '');
  return digits.length >= 6 ? digits : '';
}

function candleFlatRatio(candles) {
  const bars = Array.isArray(candles)
    ? candles.filter((c) => Number.isFinite(num(c?.open, NaN)))
    : [];
  if (!bars.length) return 1;
  let flat = 0;
  bars.forEach((b) => {
    const o = num(b.open, NaN);
    const h = num(b.high, o);
    const l = num(b.low, o);
    const c = num(b.close, o);
    if (Math.abs(h - l) < 1e-9 && Math.abs(o - c) < 1e-9) flat += 1;
  });
  return flat / bars.length;
}

function setSnapshotMode(card, snapshotUrl) {
  if (!card) return;
  const canvas = card.querySelector('.live-chart-canvas');
  const img = card.querySelector('.live-snapshot-img');
  if (!canvas || !img) return;
  if (snapshotUrl) {
    if (img.getAttribute('src') !== snapshotUrl) img.setAttribute('src', snapshotUrl);
    img.style.display = 'block';
    canvas.style.display = 'none';
    return;
  }
  img.style.display = 'none';
  canvas.style.display = 'block';
}

function setSnapshotOverlay(card, snap) {
  if (!card) return;
  const overlay = card.querySelector('.snapshot-overlay');
  if (!overlay) return;
  const bot = String(card.dataset.bot || '-');
  const acct = maskAccount(card.dataset.account || '-');
  const t = snap?.updatedAt ? new Date(snap.updatedAt).toLocaleTimeString() : '-';
  overlay.textContent = `EA ${bot} | Acct ${acct} | ${t}`;
}

function extractFeedTicks(feed, symbol) {
  const key = String(symbol || '').toUpperCase();
  const re = new RegExp(`\\b${key}\\b[^\\n]*?\\bat\\s+([0-9]+(?:\\.[0-9]+)?)`, 'i');
  const rows = [];
  (Array.isArray(feed) ? feed : []).forEach((e) => {
    const text = String(e?.text || '');
    const m = text.match(re);
    if (!m) return;
    const price = Number(m[1]);
    if (!Number.isFinite(price) || price <= 0) return;
    const t = Number(e?.t || Date.parse(e?.ts || '') || 0);
    if (!Number.isFinite(t) || t <= 0) return;
    rows.push({ t, price, text });
  });
  return rows.sort((a, b) => a.t - b.t);
}

function ticksToCandles(ticks) {
  const map = new Map();
  (Array.isArray(ticks) ? ticks : []).forEach((r) => {
    const barTime = Math.floor(r.t / (5 * 60 * 1000)) * (5 * 60);
    const k = String(barTime);
    const prev = map.get(k);
    if (!prev) {
      map.set(k, { time: barTime, open: r.price, high: r.price, low: r.price, close: r.price });
      return;
    }
    prev.high = Math.max(prev.high, r.price);
    prev.low = Math.min(prev.low, r.price);
    prev.close = r.price;
  });
  return Array.from(map.values()).sort((a, b) => a.time - b.time);
}

function extractTradeMarkers(feed, symbol) {
  const key = String(symbol || '').toUpperCase();
  const re = new RegExp(`\\bdeal\\s+#\\d+\\s+(buy|sell)\\s+[0-9.]+\\s+${key}\\s+at\\s+([0-9]+(?:\\.[0-9]+)?)`, 'i');
  const rows = [];
  (Array.isArray(feed) ? feed : []).forEach((e) => {
    const text = String(e?.text || '');
    const m = text.match(re);
    if (!m) return;
    const side = String(m[1] || '').toLowerCase();
    const price = Number(m[2]);
    const t = Number(e?.t || Date.parse(e?.ts || '') || 0);
    if (!Number.isFinite(price) || !Number.isFinite(t) || t <= 0) return;
    rows.push({ side, price, t });
  });
  return rows.sort((a, b) => a.t - b.t).slice(-80);
}

function drawTradeMarkers(ctx, width, height, bars, markers) {
  if (!ctx || !Array.isArray(bars) || !bars.length || !Array.isArray(markers) || !markers.length) return;
  let min = Infinity;
  let max = -Infinity;
  bars.forEach((b) => {
    min = Math.min(min, num(b.low, b.open));
    max = Math.max(max, num(b.high, b.open));
  });
  if (!Number.isFinite(min) || !Number.isFinite(max) || max === min) return;

  const padTop = 10;
  const padBottom = 18;
  const padLeft = 8;
  const padRight = 8;
  const plotH = height - padTop - padBottom;
  const plotW = width - padLeft - padRight;
  const candleStep = plotW / Math.max(bars.length, 1);
  const firstTs = Number(bars[0].time) * 1000;
  const toY = (p) => padTop + ((max - p) / (max - min)) * plotH;
  const toX = (t) => {
    const idx = (Math.floor(t / (5 * 60 * 1000)) * (5 * 60 * 1000) - firstTs) / (5 * 60 * 1000);
    return Math.floor(padLeft + (idx + 0.5) * candleStep);
  };

  markers.forEach((m) => {
    const x = toX(m.t);
    const y = toY(m.price);
    const isBuy = m.side === 'buy';
    ctx.fillStyle = isBuy ? '#1f6feb' : '#d73a49';
    ctx.beginPath();
    if (isBuy) {
      ctx.moveTo(x, y - 7);
      ctx.lineTo(x - 5, y + 3);
      ctx.lineTo(x + 5, y + 3);
    } else {
      ctx.moveTo(x, y + 7);
      ctx.lineTo(x - 5, y - 3);
      ctx.lineTo(x + 5, y - 3);
    }
    ctx.closePath();
    ctx.fill();
  });
}

async function loadChartSeries(symbols) {
  const unique = [...new Set((symbols || []).map((s) => String(s || '').toUpperCase()).filter(Boolean))];
  if (!unique.length) return {};
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const q = encodeURIComponent(unique.join(','));
      const ctrl = new AbortController();
      const timeout = setTimeout(() => ctrl.abort(), 4500 + (attempt * 1800));
      const res = await fetch(`/api/charts/live?symbols=${q}&limit=180`, { cache: 'no-store', signal: ctrl.signal });
      clearTimeout(timeout);
      if (!res.ok) continue;
      const data = await res.json();
      const rows = Array.isArray(data?.charts) ? data.charts : [];
      const out = rows.reduce((acc, r) => {
        const sym = String(r.symbol || '').toUpperCase();
        if (!sym) return acc;
        acc[sym] = r;
        if (Array.isArray(r.candles) && r.candles.length) liveChartCache.set(sym, r);
        return acc;
      }, {});
      unique.forEach((sym) => {
        if (!out[sym] && liveChartCache.has(sym)) out[sym] = liveChartCache.get(sym);
      });
      return out;
    } catch {}
  }
  return unique.reduce((acc, sym) => {
    if (liveChartCache.has(sym)) acc[sym] = liveChartCache.get(sym);
    return acc;
  }, {});
}

async function loadTerminalSnapshots(accounts) {
  const wanted = [...new Set((accounts || []).map((a) => normalizeAccount(a)).filter(Boolean))];
  if (!wanted.length) return {};
  const query = encodeURIComponent(wanted.join(','));
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const ctrl = new AbortController();
      const timeout = setTimeout(() => ctrl.abort(), 4500 + (attempt * 1800));
      const res = await fetch(`/api/snapshots/terminal?accounts=${query}`, { cache: 'no-store', signal: ctrl.signal });
      clearTimeout(timeout);
      if (!res.ok) continue;
      const data = await res.json();
      const rows = Array.isArray(data?.snapshots) ? data.snapshots : [];
      const out = rows.reduce((acc, r) => {
        const acct = normalizeAccount(r?.account);
        if (!acct) return acc;
        acc[acct] = r;
        if (r?.url) terminalSnapshotCache.set(acct, r);
        return acc;
      }, {});
      wanted.forEach((acct) => {
        if (!out[acct] && terminalSnapshotCache.has(acct)) out[acct] = terminalSnapshotCache.get(acct);
      });
      return out;
    } catch {}
  }
  return wanted.reduce((acc, acct) => {
    if (terminalSnapshotCache.has(acct)) acc[acct] = terminalSnapshotCache.get(acct);
    return acc;
  }, {});
}

function renderProfileChartView(profile, telemetry) {
  const host = el('chartViewGrid');
  if (!host) return;
  host.innerHTML = '';
  const allProfiles = sortProfiles(telemetry?.profiles || []);
  if (!allProfiles.length && !profile) return;

  const ranked = allProfiles
    .filter((p) => !String(p?.profile || '').toUpperCase().startsWith('BLUEPRINT_TF_'))
    .slice()
    .sort((a, b) => {
      const da = dayMetrics(a);
      const db = dayMetrics(b);
      const aScore = num(da.returnPctDisplay, da.returnPct);
      const bScore = num(db.returnPctDisplay, db.returnPct);
      if (aScore !== bScore) return bScore - aScore;
      return num(db.netUsdDisplay, db.netUsd) - num(da.netUsdDisplay, da.netUsd);
    });

  const picks = [];
  if (ranked.length) picks.push(...ranked.slice(0, 2));
  const selected = picks.slice(0, 2);
  const fallbackBySymbol = {};
  const markerBySymbol = {};
  const feed = Array.isArray(telemetry?.liveFeed) ? telemetry.liveFeed : [];

  selected.forEach((row, idx) => {
    const day = dayMetrics(row);
    const risk = riskPctValue(row);
    const symbol = resolveProfileSymbol(row);
    const directEvents = Array.isArray(row?.recentEvents) ? row.recentEvents : [];
    const symbolFeed = [
      ...feed.filter((e) => String(e?.text || '').toUpperCase().includes(symbol)),
      ...feed.filter((e) => String(e?.profile || '') === String(row.profile || '')),
      ...directEvents,
    ];
    const ticks = extractFeedTicks(symbolFeed, symbol);
    fallbackBySymbol[symbol] = ticksToCandles(ticks);
    markerBySymbol[symbol] = extractTradeMarkers(symbolFeed, symbol);
    const wrap = document.createElement('div');
    wrap.className = 'chart-card terminal-card';
    wrap.dataset.symbol = symbol;
    wrap.dataset.account = normalizeAccount(row.account || row.accountId || '');
    wrap.dataset.bot = String(row.botName || '-');
    wrap.innerHTML = `
      <div class="chart-title">#${idx + 1} ${profileLabel(row)} | EA ${row.botName || '-'} | ${symbol} M5 | Acct ${maskAccount(row.account || '-')} | Risk ${pct(risk)} | Day ${money(num(day.netUsdDisplay, day.netUsd))}</div>
      <div class="chart-media">
        <canvas class="live-chart-canvas" height="320"></canvas>
        <img class="live-snapshot-img" alt="Terminal snapshot" style="display:none" />
        <div class="snapshot-overlay">EA ${row.botName || '-'} | Acct ${maskAccount(row.account || '-')} | --:--:--</div>
      </div>
      <div class="chart-subline">Loading live chart feed...</div>
    `;
    host.appendChild(wrap);
  });

  const cards = Array.from(host.querySelectorAll('.chart-card'));
  const symbols = cards.map((c) => c.dataset.symbol).filter(Boolean);
  cards.forEach((card) => {
    const account = normalizeAccount(card.dataset.account);
    const canvas = card.querySelector('.live-chart-canvas');
    const sub = card.querySelector('.chart-subline');
    const snap = account ? (terminalSnapshotCache.get(account) || null) : null;
    if (snap?.url) {
      setSnapshotMode(card, snap.url);
      setSnapshotOverlay(card, snap);
      if (sub) {
        const t = snap.updatedAt ? new Date(snap.updatedAt).toLocaleTimeString() : '-';
        sub.textContent = `Source: MT5 terminal snapshot | Updated: ${t} | Acct: ${maskAccount(account || '-')} | Primary mode`;
      }
      return;
    }
    setSnapshotMode(card, null);
    drawCandles(canvas, []);
    if (sub) sub.textContent = 'Source: MT5 terminal snapshot | Waiting for first snapshot...';
  });

  const accounts = cards.map((c) => normalizeAccount(c.dataset.account)).filter(Boolean);
  Promise.all([loadChartSeries(symbols), loadTerminalSnapshots(accounts)]).then(([chartMap, snapshotMap]) => {
    cards.forEach((card) => {
      const symbol = card.dataset.symbol;
      const account = normalizeAccount(card.dataset.account);
      const row = chartMap[symbol] || {};
      const apiCandles = Array.isArray(row.candles) ? row.candles : [];
      const candles = apiCandles.length ? apiCandles : (fallbackBySymbol[symbol] || []);
      const canvas = card.querySelector('.live-chart-canvas');
      const sub = card.querySelector('.chart-subline');
      const markers = Array.isArray(markerBySymbol[symbol]) ? markerBySymbol[symbol] : [];
      const flatRatio = candleFlatRatio(candles);
      const weakSeries = !apiCandles.length || apiCandles.length < 60 || flatRatio > 0.58;
      const snap = snapshotMap?.[account] || terminalSnapshotCache.get(account) || null;
      if (snap?.url && (PREFER_TERMINAL_SNAPSHOT || weakSeries)) {
        setSnapshotMode(card, snap.url);
        setSnapshotOverlay(card, snap);
        if (sub) {
          const t = snap.updatedAt ? new Date(snap.updatedAt).toLocaleTimeString() : '-';
          const tag = PREFER_TERMINAL_SNAPSHOT ? 'Primary mode' : 'Snapshot mode';
          sub.textContent = `Source: MT5 terminal snapshot | Updated: ${t} | Acct: ${maskAccount(account || '-')} | ${tag}`;
        }
        return;
      }
      if (TOP_FEED_SNAPSHOT_ONLY) {
        setSnapshotMode(card, null);
        drawCandles(canvas, []);
        if (sub) sub.textContent = 'Source: MT5 terminal snapshot | Waiting for fresh snapshot...';
        return;
      }
      setSnapshotMode(card, null);
      drawCandles(canvas, candles, markers);
      if (sub) {
        const t = row.updatedAt ? new Date(row.updatedAt).toLocaleTimeString() : '-';
        const p = Number.isFinite(num(row.lastPrice, NaN)) ? Number(row.lastPrice).toFixed(3) : '-';
        const source = apiCandles.length ? 'live metals feed' : 'MT5 event fallback';
        sub.textContent = `Source: ${source} | Updated: ${t} | Last: ${p} | Bars: ${candles.length} | Markers: ${markers.length}`;
      }
    });
  }).catch(() => {});
}

function renderNexusSellHealth(telemetry) {
  const tbody = document.querySelector('#nexusSellHealth tbody');
  if (!tbody) return;
  tbody.innerHTML = '';

  const rows = Array.isArray(telemetry?.nexusSellHealth) ? telemetry.nexusSellHealth : [];
  if (!rows.length) {
    const tr = document.createElement('tr');
    tr.innerHTML = '<td colspan="11">No Nexus sell-health data yet.</td>';
    tbody.appendChild(tr);
    return;
  }

  rows
    .slice()
    .sort((a, b) => String(a.profile || '').localeCompare(String(b.profile || '')))
    .forEach((r) => {
      const auto = num(r.autoCorrectHits);
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td>${aliasProfileName(r.profile || '-')}</td>
        <td>${r.account || '-'}</td>
        <td>${r.riskPct ?? '-'}</td>
        <td>${r.sellTradesSeen ?? 0}</td>
        <td class="${num(r.beTriggeredPct) >= 70 ? 'positive' : ''}">${pct(r.beTriggeredPct)}</td>
        <td class="${num(r.beSetPct) >= 70 ? 'positive' : ''}">${pct(r.beSetPct)}</td>
        <td class="${num(r.tp1HitPct) >= 30 ? 'positive' : ''}">${pct(r.tp1HitPct)}</td>
        <td class="${num(r.tpFailRatePct) > 0 ? 'negative' : 'positive'}">${pct(r.tpFailRatePct)}</td>
        <td class="${num(r.frozenRatePct) > 0 ? 'negative' : 'positive'}">${pct(r.frozenRatePct)}</td>
        <td class="${auto > 0 ? 'negative' : 'positive'}">${auto}</td>
        <td>${r.lastEventAt ? new Date(r.lastEventAt).toLocaleTimeString() : '-'}</td>
      `;
      tbody.appendChild(tr);
    });
}

function renderLiveFeed(feed) {
  const list = el('liveFeed');
  if (!list) return;
  list.innerHTML = '';
  const rows = Array.isArray(feed) ? feed.slice(0, 120) : [];
  if (!rows.length) {
    const li = document.createElement('li');
    li.textContent = 'No live events yet.';
    list.appendChild(li);
    return;
  }

  rows.forEach((e) => {
    const li = document.createElement('li');
    const t = e.t ? new Date(e.t).toLocaleTimeString() : (e.ts || '-');
    li.innerHTML = `<b>${t}</b> [${e.profile || '-'}] ${e.kind || 'event'} - ${e.text || ''}`;
    list.appendChild(li);
  });
}

function renderDiscord(data) {
  const dm = data.discordMetrics;
  const dh = data.discordHealth || {};

  const html = dh.connected
    ? `<span class="badge badge-ok">CONNECTED (${dh.source || 'health'})</span>`
    : '<span class="badge badge-warn">NOT CONNECTED</span>';
  const metrics = dm ? JSON.stringify(dm, null, 2) : 'No metrics JSON. Service may still be reachable via root health.';

  const h1 = el('discordHealth');
  if (h1) h1.innerHTML = html;
  const m1 = el('discordMetrics');
  if (m1) m1.textContent = metrics;

  const h2 = el('discordHealthMirror');
  if (h2) h2.innerHTML = html;
  const m2 = el('discordMetricsMirror');
  if (m2) m2.textContent = metrics;

  const v = data.vps || {};
  setText('reports', JSON.stringify(v.latest_reports || [], null, 2));
  setText('context', data.runContext || '-');
}

function renderFixTracker(data) {
  const fx = data.fixTracker || {};
  const tracker = el('fixTracker');
  if (tracker) {
    tracker.innerHTML = `
      <div>Target: <b>${fx.targetIssue || '-'}</b></div>
      <div>Profiles total: ${fx.profilesTotal ?? '-'}</div>
      <div>Compile OK: ${fx.compileOk ?? '-'}</div>
      <div>Compile FAIL: ${fx.compileFail ?? '-'}</div>
      <div>Compile UNKNOWN: ${fx.compileUnknown ?? '-'}</div>
      <div>Runtime critical hits: ${fx.runtimeCriticalHits ?? '-'}</div>
    `;
  }

  const s = data.summary || {};
  const history = pushHistoryPoint('runtime', s.runtime_critical_hits ?? 0);
  drawRuntimeChart(history);

  runtimeTimeline.unshift({
    t: new Date().toLocaleTimeString(),
    verdict: s.verdict || '-',
    bad: s.compile_bad_profiles ?? '-',
    runtime: s.runtime_critical_hits ?? '-',
  });
  runtimeTimeline = runtimeTimeline.slice(0, 12);

  const tl = el('timeline');
  if (tl) {
    tl.innerHTML = runtimeTimeline.map((x) => `<li><b>${x.t}</b> - verdict ${x.verdict}, compile bad ${x.bad}, runtime hits ${x.runtime}</li>`).join('');
  }
}

function renderActionAudit() {
  const list = el('actionAudit');
  if (!list) return;
  const rows = readActionAudit();
  list.innerHTML = '';
  if (!rows.length) {
    const li = document.createElement('li');
    li.textContent = 'No control actions recorded yet.';
    list.appendChild(li);
    return;
  }
  rows.slice(0, 20).forEach((r) => {
    const li = document.createElement('li');
    const t = new Date(r.at).toLocaleTimeString();
    li.innerHTML = `<b>${t}</b> ${r.action} - ${r.ok ? 'OK' : 'FAIL'}${r.detail ? ` (${r.detail})` : ''}`;
    list.appendChild(li);
  });
}

async function load() {
  const res = await fetch('/api/status');
  const data = await res.json();
  const clientOverview = buildClientOverview(data.telemetry?.profiles || []);

  renderSummaryCards(data);
  renderCompilerView(data.summary || {});
  renderAccountSummary(data.telemetry?.accounts || []);
  renderCopierFeed(data.copierFeed || data.telemetry?.copierFeed || null);
  renderPerformanceOverview(clientOverview);
  renderLiveProfiles(data.telemetry || {});
  renderNexusSellHealth(data.telemetry || {});
  renderLiveFeed(data.liveFeed || data.telemetry?.liveFeed || []);
  renderDiscord(data);
  renderFixTracker(data);
  renderActionAudit();
}

wireTabs();
wireControls();
load();
setInterval(load, 5000);
