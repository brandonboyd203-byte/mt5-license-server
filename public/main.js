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

      if (a) {
        if (t1) t1.textContent = a.account ? `VDS ${a.account}` : 'VDS Terminal Snapshot #1';
        i1.src = `${a.imageUrl}&_t=${Date.now()}`;
        m1.textContent = `Updated ${fmtTime(a.updatedAt)}${a.title ? ` | ${a.title}` : ''}`;
      } else {
        i1.removeAttribute('src');
        m1.textContent = 'Snapshot unavailable.';
      }

      if (b) {
        if (t2) t2.textContent = b.account ? `VDS ${b.account}` : 'VDS Terminal Snapshot #2';
        i2.src = `${b.imageUrl}&_t=${Date.now()}`;
        m2.textContent = `Updated ${fmtTime(b.updatedAt)}${b.title ? ` | ${b.title}` : ''}`;
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

  function renderLiveRows(targetEl, rows, emptyText = 'No live profiles yet.') {
    if (!targetEl) return;
    const list = Array.isArray(rows) ? rows.slice(0, 25) : [];
    if (!list.length) {
      targetEl.innerHTML = `<tr><td colspan="12">${emptyText}</td></tr>`;
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
            <td>${row.riskPct ?? '-'}</td>
            <td>${lev}</td>
            <td>$${Number(row.balance || 0).toFixed(2)}</td>
            <td>$${Number(row.equity || 0).toFixed(2)}</td>
            <td class="${numClass(row.openProfit)}">${money(row.openProfit)}</td>
            <td class="${numClass(row.dayNetUsd)}">${money(row.dayNetUsd)}</td>
            <td class="${numClass(row.dayReturnPct)}">${pct(row.dayReturnPct)}</td>
            <td class="${numClass(row.weekNetUsd)}">${money(row.weekNetUsd)}</td>
            <td class="${numClass(row.weekReturnPct)}">${pct(row.weekReturnPct)}</td>
            <td title="${row.statusReason || ''}">${row.status || '-'}</td>
          </tr>
        `;
      })
      .join('');
  }

  async function loadLiveFeed() {
    const rowsVps = document.getElementById('liveFeedRowsVps');
    const rowsVds = document.getElementById('liveFeedRowsVds');
    if (!rowsVps && !rowsVds) return;

    try {
      const [respVps, respVds] = await Promise.all([
        fetch('/api/bots/live?source=vps'),
        fetch('/api/bots/live?source=vds'),
      ]);
      const [vps, vds] = await Promise.all([respVps.json(), respVds.json()]);
      if (!respVps.ok || !vps.ok) throw new Error(vps.message || 'VPS live feed unavailable');
      if (!respVds.ok || !vds.ok) throw new Error(vds.message || 'VDS live feed unavailable');

      setFeedHealth('vpsHealthLabel', vps.stale ? 'warn' : 'ok', `VPS: ${vps.stale ? 'STALE' : 'LIVE'} • ${vps.summary?.profilesTotal ?? 0} profiles`);
      setFeedHealth('vdsHealthLabel', vds.stale ? 'warn' : 'ok', `VDS: ${vds.stale ? 'STALE' : 'LIVE'} • ${vds.summary?.profilesTotal ?? 0} profiles`);

      const summary = vps.summary || {};
      const day = document.getElementById('liveDayNet');
      const week = document.getElementById('liveWeekNet');
      const open = document.getElementById('liveOpenPnl');
      const profiles = document.getElementById('liveProfiles');
      const updated = document.getElementById('liveUpdated');
      if (day) day.textContent = money(summary.dayNetUsd);
      if (week) week.textContent = money(summary.weekNetUsd);
      if (open) open.textContent = money(summary.openProfitUsd);
      if (profiles) profiles.textContent = `${vps.summary?.profilesTotal ?? 0}/${vds.summary?.profilesTotal ?? 0}`;
      if (updated) updated.textContent = `${fmtTime(vps.generatedAt)} / ${fmtTime(vds.generatedAt)}`;

      const vpsRows = Array.isArray(vps.profiles) ? vps.profiles : [];
      const vdsRows = Array.isArray(vds.profiles) ? vds.profiles : [];
      renderLiveRows(rowsVps, vpsRows, 'No VPS live profiles yet.');
      renderLiveRows(rowsVds, vdsRows, 'No VDS live profiles yet.');
      loadLiveCharts();
    } catch (error) {
      if (rowsVps) rowsVps.innerHTML = `<tr><td colspan="12">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsVds) rowsVds.innerHTML = `<tr><td colspan="12">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      setFeedHealth('vpsHealthLabel', 'bad', 'VPS: OFFLINE');
      setFeedHealth('vdsHealthLabel', 'bad', 'VDS: OFFLINE');
      loadLiveCharts();
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
  wireCheckout();

  if (document.getElementById('liveFeedRowsVps') || document.getElementById('liveFeedRowsVds')) {
    setInterval(loadLiveFeed, 3000);
  }
})();
