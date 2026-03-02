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

  async function loadLiveCharts(rows) {
    const t1 = document.getElementById('liveChartTitle1');
    const t2 = document.getElementById('liveChartTitle2');
    const c1 = document.getElementById('liveChartCanvas1');
    const c2 = document.getElementById('liveChartCanvas2');
    const m1 = document.getElementById('liveChartMeta1');
    const m2 = document.getElementById('liveChartMeta2');
    if (!c1 || !c2 || !m1 || !m2) return;

    const top = Array.isArray(rows) ? rows.slice(0, 2) : [];
    const symbols = top.map(resolveLiveSymbol);
    while (symbols.length < 2) symbols.push(symbols.length === 0 ? 'XAUUSD' : 'XAGUSD');
    const [s1, s2] = symbols;
    if (t1) t1.textContent = `${s1} M5`;
    if (t2) t2.textContent = `${s2} M5`;

    try {
      const q = new URLSearchParams({ symbols: `${s1},${s2}`, limit: '180', source: 'vds' });
      const response = await fetch(`/api/bots/charts?${q.toString()}`);
      const data = await response.json();
      if (!response.ok || !data.ok) throw new Error(data.message || 'Live chart feed unavailable');
      const map = (Array.isArray(data.charts) ? data.charts : []).reduce((acc, r) => {
        acc[String(r?.symbol || '').toUpperCase()] = r;
        return acc;
      }, {});
      const a = map[s1] || { candles: [], updatedAt: null, lastPrice: null };
      const b = map[s2] || { candles: [], updatedAt: null, lastPrice: null };
      drawLiveCandles(c1, a.candles || []);
      drawLiveCandles(c2, b.candles || []);
      m1.textContent = `Updated ${fmtTime(a.updatedAt)} | Last ${Number.isFinite(n(a.lastPrice, NaN)) ? Number(a.lastPrice).toFixed(3) : '-'} | Bars ${(a.candles || []).length}`;
      m2.textContent = `Updated ${fmtTime(b.updatedAt)} | Last ${Number.isFinite(n(b.lastPrice, NaN)) ? Number(b.lastPrice).toFixed(3) : '-'} | Bars ${(b.candles || []).length}`;
    } catch (error) {
      drawLiveCandles(c1, []);
      drawLiveCandles(c2, []);
      m1.textContent = `Chart feed unavailable: ${error.message || 'unavailable'}`;
      m2.textContent = `Chart feed unavailable: ${error.message || 'unavailable'}`;
    }
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
      loadLiveCharts(vdsRows);
    } catch (error) {
      if (rowsVps) rowsVps.innerHTML = `<tr><td colspan="12">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsVds) rowsVds.innerHTML = `<tr><td colspan="12">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      loadLiveCharts([]);
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
    setInterval(loadLiveFeed, 5000);
  }
})();
