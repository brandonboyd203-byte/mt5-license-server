(function () {
  const menu = document.querySelector('[data-menu]');
  const button = document.querySelector('[data-menu-btn]');

  if (menu && button) {
    button.addEventListener('click', () => {
      const isOpen = menu.classList.toggle('open');
      button.setAttribute('aria-expanded', String(isOpen));
    });

    document.addEventListener('click', (event) => {
      if (!menu.contains(event.target)) {
        menu.classList.remove('open');
        button.setAttribute('aria-expanded', 'false');
      }
    });
  }

  const page = document.body.dataset.page;
  document.querySelectorAll('.menu-link[data-page]').forEach((link) => {
    if (link.dataset.page === page) link.classList.add('active');
  });

  function money(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '-';
    const s = n >= 0 ? '+' : '-';
    return `${s}$${Math.abs(n).toFixed(2)}`;
  }

  function pct(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '-';
    const s = n >= 0 ? '+' : '-';
    return `${s}${Math.abs(n).toFixed(2)}%`;
  }

  function numClass(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '';
    return n >= 0 ? 'positive' : 'negative';
  }

  function fmtTime(iso) {
    if (!iso) return '-';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '-';
    return d.toLocaleTimeString();
  }

  async function loadSupportEmail() {
    const nodes = document.querySelectorAll('[data-support-email]');
    if (!nodes.length) return;
    try {
      const response = await fetch('/api/config');
      const data = await response.json();
      const email = data.supportEmail || 'goldminebotsltd@gmail.com';
      nodes.forEach((node) => {
        if (node.tagName === 'A') {
          node.href = `mailto:${email}`;
          node.textContent = email;
        } else {
          node.textContent = email;
        }
      });
      window.__supportEmail = email;
    } catch {
      window.__supportEmail = 'goldminebotsltd@gmail.com';
    }
  }

  function n(v, fallback = 0) {
    const x = Number(v);
    return Number.isFinite(x) ? x : fallback;
  }

  function resolveLiveSymbol(row) {
    const name = `${row?.profile || ''} ${row?.profileLabel || ''}`.toUpperCase();
    if (name.includes('SILVER')) return 'XAGUSD';
    return 'XAUUSD';
  }

  function drawLiveCandles(canvas, candles) {
    const ctx = canvas?.getContext?.('2d');
    if (!ctx) return;
    const dpr = window.devicePixelRatio || 1;
    const width = Math.max(280, canvas.clientWidth || 280);
    const height = Math.max(220, canvas.clientHeight || 260);
    canvas.width = Math.floor(width * dpr);
    canvas.height = Math.floor(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);

    const bars = Array.isArray(candles) ? candles.filter((c) => Number.isFinite(n(c?.open, NaN))) : [];
    if (!bars.length) {
      ctx.fillStyle = '#5e6b76';
      ctx.font = '12px monospace';
      ctx.fillText('Waiting for live candles...', 12, 24);
      return;
    }

    let min = Infinity;
    let max = -Infinity;
    bars.forEach((b) => {
      min = Math.min(min, n(b.low, b.open));
      max = Math.max(max, n(b.high, b.open));
    });
    if (!Number.isFinite(min) || !Number.isFinite(max)) return;
    if (max === min) {
      max += 0.1;
      min -= 0.1;
    }

    const padTop = 10;
    const padBottom = 16;
    const padLeft = 8;
    const padRight = 8;
    const plotH = height - padTop - padBottom;
    const plotW = width - padLeft - padRight;
    const step = plotW / Math.max(bars.length, 1);
    const bodyW = Math.max(2, Math.floor(step * 0.56));
    const toY = (p) => padTop + ((max - p) / (max - min)) * plotH;

    bars.forEach((b, i) => {
      const open = n(b.open);
      const high = n(b.high, open);
      const low = n(b.low, open);
      const close = n(b.close, open);
      const x = Math.floor(padLeft + i * step + step / 2);
      const up = close >= open;
      const color = up ? '#2ea67d' : '#d75b5b';
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, toY(high));
      ctx.lineTo(x, toY(low));
      ctx.stroke();
      const yOpen = toY(open);
      const yClose = toY(close);
      const top = Math.min(yOpen, yClose);
      const bodyH = Math.max(1, Math.abs(yClose - yOpen));
      ctx.fillStyle = color;
      ctx.fillRect(Math.floor(x - bodyW / 2), top, bodyW, bodyH);
    });
  }

  async function loadLiveCharts() {
    const t1 = document.getElementById('liveChartTitle1');
    const t2 = document.getElementById('liveChartTitle2');
    const i1 = document.getElementById('liveChartImg1');
    const i2 = document.getElementById('liveChartImg2');
    const m1 = document.getElementById('liveChartMeta1');
    const m2 = document.getElementById('liveChartMeta2');
    if (!i1 || !i2 || !m1 || !m2) return;

    try {
      const response = await fetch('/api/bots/vds-snapshots');
      const data = await response.json();
      if (!response.ok || !data.ok) throw new Error(data.message || 'VDS snapshots unavailable');
      const a = (data.snapshots || [])[0] || null;
      const b = (data.snapshots || [])[1] || null;

      const fmtPnl = (v) => {
        const n = Number(v);
        if (!Number.isFinite(n)) return 'Day -';
        return `Day ${n >= 0 ? '+' : '-'}${Math.abs(n).toFixed(2)}`;
      };
      const fmtRisk = (v) => Number.isFinite(Number(v)) ? Number(v).toFixed(2) : '-';
      const maskAcc = (a) => {
        const s = String(a || '');
        if (!/^\d{6,}$/.test(s)) return s || '-';
        return `${s.slice(0,3)}***${s.slice(-3)}`;
      };

      if (a) {
        const bot = a.profileLabel || a.profile || 'Best Bot #1';
        const ea = a.botName || '-';
        const sym = (a.symbols || '-').replace(/\+/g, ',');
        if (t1) t1.textContent = `#1 ${bot} | EA ${ea} | ${sym} M5 | Acct ${maskAcc(a.account)} | Risk ${fmtRisk(a.riskPct)}% | ${fmtPnl(a.dayNetUsd)}`;
        i1.src = `${a.imageUrl}&_t=${Date.now()}`;
        m1.textContent = `Updated ${fmtTime(a.updatedAt)} | P/L ${Number(a.dayNetUsd||0) >= 0 ? '+' : '-'}$${Math.abs(Number(a.dayNetUsd||0)).toFixed(2)} | Acc ${a.account || '-'}`;
      } else {
        i1.removeAttribute('src');
        m1.textContent = 'Snapshot unavailable.';
      }

      if (b) {
        const bot = b.profileLabel || b.profile || 'Best Bot #2';
        const ea = b.botName || '-';
        const sym = (b.symbols || '-').replace(/\+/g, ',');
        if (t2) t2.textContent = `#2 ${bot} | EA ${ea} | ${sym} M5 | Acct ${maskAcc(b.account)} | Risk ${fmtRisk(b.riskPct)}% | ${fmtPnl(b.dayNetUsd)}`;
        i2.src = `${b.imageUrl}&_t=${Date.now()}`;
        m2.textContent = `Updated ${fmtTime(b.updatedAt)} | P/L ${Number(b.dayNetUsd||0) >= 0 ? '+' : '-'}$${Math.abs(Number(b.dayNetUsd||0)).toFixed(2)} | Acc ${b.account || '-'}`;
      } else {
        i2.removeAttribute('src');
        m2.textContent = 'Snapshot unavailable.';
      }
    } catch (error) {
      i1.removeAttribute('src');
      i2.removeAttribute('src');
      m1.textContent = `Snapshot feed unavailable: ${error.message || 'unavailable'}`;
      m2.textContent = `Snapshot feed unavailable: ${error.message || 'unavailable'}`;
    }
  }

  function setFeedHealth(id, state, text) {
    const el = document.getElementById(id);
    if (!el) return;
    el.classList.remove('feed-label-ok', 'feed-label-warn', 'feed-label-bad');
    if (state === 'ok') el.classList.add('feed-label-ok');
    else if (state === 'bad') el.classList.add('feed-label-bad');
    else el.classList.add('feed-label-warn');
    el.textContent = text;
  }

  function inferRiskPct(row) {
    const direct = Number(row?.riskPct);
    if (Number.isFinite(direct) && direct > 0) return String(direct);
    const name = `${row?.profileLabel || ''} ${row?.profile || ''}`.toUpperCase();
    let m = name.match(/RISK\s*[_-]?(\d{1,2})/);
    if (m) return m[1];
    m = name.match(/GOLD[_-]?SILVER(\d{1,2})/);
    if (m) return m[1];
    if (name.includes('EDGE')) return '1';
    if (name.includes('FRESH')) return '2';
    if (name.includes('SURGE')) return '2';
    if (name.includes('DOMINION')) return '2';
    if (name.includes('NEXUS')) return '2';
    if (name.includes('BLUEPRINT')) return '2';
    return '-';
  }

  function openPnlValue(row) {
    const rawOpen = Number(row?.openProfit ?? row?.openPnl ?? row?.openProfitUsd);
    const bal = Number(row?.balance);
    const eq = Number(row?.equity);
    const eqDiff = Number.isFinite(eq) && Number.isFinite(bal) ? (eq - bal) : null;
    if (Number.isFinite(rawOpen)) {
      if (Number.isFinite(bal) && Math.abs(rawOpen - bal) < 0.01 && Number.isFinite(eqDiff)) return eqDiff;
      if (Number.isFinite(eqDiff) && Math.abs(rawOpen) > 0 && Math.abs(rawOpen - eqDiff) > 50) return eqDiff;
      return rawOpen;
    }
    if (Number.isFinite(eqDiff)) return eqDiff;
    return 0;
  }

  function profileName(row) {
    return String(row?.profileLabel || row?.profile || '').trim();
  }

  function isBaseOrPresetRow(row) {
    const name = profileName(row).toUpperCase();
    return (
      name === 'BASE'
      || name === 'PRESETS'
      || name === 'UNKNOWN:BASE'
      || name === 'UNKNOWN:PRESETS'
      || name.endsWith(':BASE')
      || name.endsWith(':PRESETS')
    );
  }

  function isJordanRow(row) {
    const name = profileName(row).toUpperCase();
    const client = String(row?.client || '').toUpperCase();
    return name.includes('JORDAN') || client.includes('JORDAN');
  }

  function botGroupRank(row) {
    const name = profileName(row).toUpperCase();
    if (name.includes('BLUEPRINT')) return 0;
    if (name.includes('NEXUS')) return 1;
    if (name.includes('FRESH')) return 2;
    if (name.includes('DOMINION')) return 3;
    if (name.includes('EDGE')) return 4;
    if (name.includes('SURGE')) return 5;
    return 9;
  }

  function sortRowsByBotOrder(rows) {
    return (Array.isArray(rows) ? rows : [])
      .slice()
      .sort((a, b) => {
        const ga = botGroupRank(a);
        const gb = botGroupRank(b);
        if (ga !== gb) return ga - gb;
        return profileName(a).localeCompare(profileName(b));
      });
  }

  function prepareRows(rows) {
    const filtered = (Array.isArray(rows) ? rows : []).filter((r) => !isBaseOrPresetRow(r));
    const jordan = sortRowsByBotOrder(filtered.filter((r) => isJordanRow(r)));
    const main = sortRowsByBotOrder(filtered.filter((r) => !isJordanRow(r)));
    return { main, jordan };
  }

  function inferCashFlows(row) {
    const dep = Number(row?.depositAmount);
    const wd = Number(row?.withdrawAmount);
    if (Number.isFinite(dep) || Number.isFinite(wd)) {
      return {
        deposit: Number.isFinite(dep) ? dep : 0,
        withdraw: Number.isFinite(wd) ? wd : 0,
      };
    }
    return { deposit: 0, withdraw: 0 };
  }

  function renderLiveRows(targetEl, rows, emptyText = 'No live profiles yet.') {
    if (!targetEl) return;
    const list = Array.isArray(rows) ? rows.slice(0, 25) : [];
    if (!list.length) {
      targetEl.innerHTML = `<tr><td colspan="17">${emptyText}</td></tr>`;
      return;
    }
    targetEl.innerHTML = list
      .map((row) => {
        const lev = row.leverage
          ? row.leverageSource === 'equity-tier-estimate'
            ? `~${row.leverage}`
            : row.leverage
          : '-';
        const flows = inferCashFlows(row);
        return `
          <tr>
            <td>${row.profileLabel || row.profile || '-'}</td>
            <td>${row.account || '-'}</td>
            <td>${inferRiskPct(row)}</td>
            <td>${lev}</td>
            <td>${money(flows.deposit)}</td>
            <td>${money(flows.withdraw)}</td>
            <td>${Number.isFinite(Number(row?.dayStartEquity ?? row?.dayStartBalance))
              ? `$${Number(row.dayStartEquity ?? row.dayStartBalance).toFixed(2)}`
              : '-'}</td>
            <td>$${Number(row.balance || 0).toFixed(2)}</td>
            <td>$${Number(row.equity || 0).toFixed(2)}</td>
            <td class="${numClass(openPnlValue(row))}">${money(openPnlValue(row))}</td>
            <td class="${numClass(row.dayNetUsd)}">${money(row.dayNetUsd)}</td>
            <td class="${numClass(row.totalNetUsd)}">${money(row.totalNetUsd)}</td>
            <td class="${numClass(row.totalReturnPct)}">${pct(row.totalReturnPct)}</td>
            <td class="${numClass(row.dayReturnPct)}">${pct(row.dayReturnPct)}</td>
            <td class="${numClass(row.weekNetUsd)}">${money(row.weekNetUsd)}</td>
            <td class="${numClass(row.weekReturnPct)}">${pct(row.weekReturnPct)}</td>
            <td title="${row.statusReason || ''}">${row.status || '-'}</td>
          </tr>
        `;
      })
      .join('');
  }

  function renderLegacyHomeRows(targetEl, rows, emptyText = 'No live profiles yet.') {
    if (!targetEl) return;
    const list = Array.isArray(rows) ? rows.slice(0, 25) : [];
    if (!list.length) {
      targetEl.innerHTML = `<tr><td colspan="14">${emptyText}</td></tr>`;
      return;
    }
    targetEl.innerHTML = list
      .map((row) => {
        const lev = row.leverage
          ? row.leverageSource === 'equity-tier-estimate'
            ? `~${row.leverage}`
            : row.leverage
          : '-';
        return `
          <tr>
            <td>${row.profileLabel || row.profile || '-'}</td>
            <td>${row.account || '-'}</td>
            <td>${inferRiskPct(row)}</td>
            <td>${lev}</td>
            <td>$${Number(row.balance || 0).toFixed(2)}</td>
            <td>$${Number(row.equity || 0).toFixed(2)}</td>
            <td class="${numClass(openPnlValue(row))}">${money(openPnlValue(row))}</td>
            <td class="${numClass(row.dayNetUsd)}">${money(row.dayNetUsd)}</td>
            <td class="${numClass(row.totalNetUsd)}">${money(row.totalNetUsd)}</td>
            <td class="${numClass(row.totalReturnPct)}">${pct(row.totalReturnPct)}</td>
            <td class="${numClass(row.dayReturnPct)}">${pct(row.dayReturnPct)}</td>
            <td class="${numClass(row.weekNetUsd)}">${money(row.weekNetUsd)}</td>
            <td class="${numClass(row.weekReturnPct)}">${pct(row.weekReturnPct)}</td>
            <td title="${row.statusReason || ''}">${row.status || '-'}</td>
          </tr>
        `;
      })
      .join('');
  }

  function renderCopierRows(targetEl, rows, emptyText = 'No copier accounts live yet.') {
    if (!targetEl) return;
    const list = Array.isArray(rows) ? rows.slice(0, 50) : [];
    if (!list.length) {
      targetEl.innerHTML = `<tr><td colspan="18">${emptyText}</td></tr>`;
      return;
    }
    targetEl.innerHTML = list
      .map((row) => {
        const lev = row.leverage || '-';
        return `
          <tr>
            <td>${row.profileLabel || row.profile || '-'}</td>
            <td>${row.account || '-'}</td>
            <td>${row.client || '-'}</td>
            <td>${row.botName || '-'}</td>
            <td>${Number.isFinite(Number(row.riskPct)) ? Number(row.riskPct).toFixed(2) : '-'}</td>
            <td>${lev}</td>
            <td>${money(row.depositAmount)}</td>
            <td>${money(row.withdrawAmount)}</td>
            <td>${Number.isFinite(Number(row?.dayStartEquity))
              ? `$${Number(row.dayStartEquity).toFixed(2)}`
              : '-'}</td>
            <td>$${Number(row.balance || 0).toFixed(2)}</td>
            <td>$${Number(row.equity || 0).toFixed(2)}</td>
            <td class="${numClass(row.openProfit)}">${money(row.openProfit)}</td>
            <td class="${numClass(row.dayNetUsd)}">${money(row.dayNetUsd)}</td>
            <td class="${numClass(row.dayReturnPct)}">${pct(row.dayReturnPct)}</td>
            <td class="${numClass(row.weekNetUsd)}">${money(row.weekNetUsd)}</td>
            <td class="${numClass(row.weekReturnPct)}">${pct(row.weekReturnPct)}</td>
            <td>${row.status || '-'}</td>
            <td>${fmtTime(row.updatedAt)}</td>
          </tr>
        `;
      })
      .join('');
  }

  async function loadCopierFeedSection() {
    const rows = document.getElementById('liveCopierFeedRows');
    if (!rows) return;
    try {
      const nonce = Date.now();
      const resp = await fetch(`/api/bots/live?source=vds&_t=${nonce}`);
      const payload = await resp.json();
      if (!resp.ok || !payload.ok) throw new Error(payload.message || 'copier feed unavailable');
      const feedRows = Array.isArray(payload?.copierFeed?.rows) ? payload.copierFeed.rows : [];
      renderCopierRows(rows, feedRows, 'No copier accounts configured yet.');
    } catch (error) {
      rows.innerHTML = `<tr><td colspan="18">Copier feed error: ${error.message || 'unavailable'}</td></tr>`;
    }
  }

  async function loadLiveFeed() {
    const rowsVps = document.getElementById('liveFeedRowsVps');
    const rowsVds = document.getElementById('liveFeedRowsVds');
    const rowsJordan = document.getElementById('liveFeedRowsJordan');
    const rowsLegacy = document.getElementById('liveFeedRows');
    if (!rowsVps && !rowsVds && !rowsLegacy) return;

    try {
      const nonce = Date.now();
      const isLegacyHome = !!rowsLegacy && !rowsVps && !rowsVds;
      let vps = null;
      let vds = null;

      if (isLegacyHome) {
        const respVds = await fetch(`/api/bots/live?source=vds&_t=${nonce}`);
        vds = await respVds.json();
        if (!respVds.ok || !vds.ok) throw new Error(vds.message || 'VDS live feed unavailable');
      } else {
        const [respVps, respVds] = await Promise.all([
          fetch(`/api/bots/live?source=vps&_t=${nonce}`),
          fetch(`/api/bots/live?source=vds&_t=${nonce}`),
        ]);
        [vps, vds] = await Promise.all([respVps.json(), respVds.json()]);
        if (!respVps.ok || !vps.ok) throw new Error(vps.message || 'VPS live feed unavailable');
        if (!respVds.ok || !vds.ok) throw new Error(vds.message || 'VDS live feed unavailable');
      }

      if (!isLegacyHome) {
        setFeedHealth('vpsHealthLabel', vps.stale ? 'warn' : 'ok', `VPS: ${vps.stale ? 'STALE' : 'LIVE'} • ${vps.summary?.profilesTotal ?? 0} profiles`);
        setFeedHealth('vdsHealthLabel', vds.stale ? 'warn' : 'ok', `VDS: ${vds.stale ? 'STALE' : 'LIVE'} • ${vds.summary?.profilesTotal ?? 0} profiles`);
      }

      const vpsSummary = (vps && vps.summary) || {};
      const vdsSummary = (vds && vds.summary) || {};
      const day = document.getElementById('liveDayNet');
      const week = document.getElementById('liveWeekNet');
      const open = document.getElementById('liveOpenPnl');
      const profiles = document.getElementById('liveProfiles');
      const updated = document.getElementById('liveUpdated');
      if (day) day.textContent = money(isLegacyHome ? vdsSummary.dayNetUsd : vpsSummary.dayNetUsd);
      if (week) week.textContent = money(isLegacyHome ? vdsSummary.weekNetUsd : vpsSummary.weekNetUsd);
      if (open) {
        const vdsOpen = Number(vdsSummary.openProfitUsd || 0);
        const rowsOpen = (Array.isArray(vds.profiles) ? vds.profiles : []).reduce((a, r) => a + openPnlValue(r), 0);
        open.textContent = money(Math.abs(vdsOpen) > 0 ? vdsOpen : rowsOpen);
      }
      if (profiles) profiles.textContent = isLegacyHome ? `${vdsSummary.profilesTotal ?? 0}` : `${vpsSummary.profilesTotal ?? 0}/${vdsSummary.profilesTotal ?? 0}`;
      if (updated) updated.textContent = isLegacyHome ? `${fmtTime(vds.generatedAt)}` : `${fmtTime(vps.generatedAt)} / ${fmtTime(vds.generatedAt)}`;

      const vpsRows = (vps && Array.isArray(vps.profiles)) ? vps.profiles : [];
      const vdsRows = (vds && Array.isArray(vds.profiles)) ? vds.profiles : [];
      const preparedVps = prepareRows(vpsRows);
      const preparedVds = prepareRows(vdsRows);
      if (isLegacyHome) {
        renderLegacyHomeRows(rowsLegacy, preparedVds.main, 'No VDS live profiles yet.');
      } else {
        renderLiveRows(rowsVps, preparedVps.main, 'No VPS live profiles yet.');
        renderLiveRows(rowsVds, preparedVds.main, 'No VDS live profiles yet.');
        renderLiveRows(document.getElementById('liveFeedRowsJordan'), preparedVds.jordan, 'No JORDAN accounts live yet.');
        loadLiveCharts();
      }
    } catch (error) {
      if (rowsVps) rowsVps.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsVds) rowsVds.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsJordan) rowsJordan.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsLegacy) rowsLegacy.innerHTML = `<tr><td colspan="14">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      setFeedHealth('vpsHealthLabel', 'bad', 'VPS: OFFLINE');
      setFeedHealth('vdsHealthLabel', 'bad', 'VDS: OFFLINE');
      if (!rowsLegacy) loadLiveCharts();
    }
  }

  function wireCheckout() {
    const form = document.getElementById('checkoutForm');
    const status = document.getElementById('checkoutStatus');
    if (!form) return;

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (status) status.textContent = 'Creating your Coinbase Commerce invoice...';

      const payload = {
        name: document.getElementById('checkoutName')?.value,
        email: document.getElementById('checkoutEmail')?.value,
        plan: document.getElementById('checkoutPlan')?.value,
        accountSize: document.getElementById('checkoutAccount')?.value,
        contact: document.getElementById('checkoutContact')?.value,
      };

      try {
        const response = await fetch('/api/coinbase/charge', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });

        const result = await response.json();
        if (!response.ok || !result.hostedUrl) {
          throw new Error(result.error || 'Unable to create charge.');
        }

        window.location.href = result.hostedUrl;
      } catch (error) {
        const supportEmail = window.__supportEmail || 'goldminebotsltd@gmail.com';
        if (status) {
          status.textContent = error.message || `Checkout unavailable. Email ${supportEmail} for manual invoice.`;
        }
      }
    });
  }

  loadSupportEmail();
  loadLiveFeed();
  loadCopierFeedSection();
  wireCheckout();

  if (document.getElementById('liveFeedRowsVps') || document.getElementById('liveFeedRowsVds')) {
    setInterval(loadLiveFeed, 3000);
  }
  if (document.getElementById('liveCopierFeedRows')) {
    setInterval(loadCopierFeedSection, 5000);
  }
})();
