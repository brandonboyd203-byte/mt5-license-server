(function () {
  function initPwaInstall() {
    const head = document.head;
    const addMeta = (name, content) => {
      if (!head || head.querySelector(`meta[name="${name}"]`)) return;
      const node = document.createElement('meta');
      node.name = name;
      node.content = content;
      head.appendChild(node);
    };
    const addLink = (rel, href) => {
      if (!head || head.querySelector(`link[rel="${rel}"]`)) return;
      const node = document.createElement('link');
      node.rel = rel;
      node.href = href;
      head.appendChild(node);
    };

    addMeta('theme-color', '#08101f');
    addLink('manifest', '/manifest.webmanifest');
    addLink('apple-touch-icon', '/app-icon.svg');
    addLink('icon', '/app-icon.svg');

    let deferredPrompt = null;
    const isIos = /iphone|ipad|ipod/i.test(window.navigator.userAgent || '');
    const isStandalone = (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
      || window.navigator.standalone === true;
    const navActions = document.querySelector('.nav-actions');
    let installButton = null;

    const ensureInstallButton = () => {
      if (!navActions) return null;
      if (installButton) return installButton;
      installButton = document.createElement('button');
      installButton.type = 'button';
      installButton.className = 'btn btn-outline install-btn';
      installButton.textContent = isIos && !isStandalone ? 'Add to Home Screen' : 'Install App';
      installButton.addEventListener('click', async () => {
        if (isIos && !isStandalone) {
          window.alert('On iPhone or iPad, tap Share in Safari and then choose "Add to Home Screen" to install Goldmine Bots.');
          return;
        }
        if (!deferredPrompt) return;
        deferredPrompt.prompt();
        try {
          await deferredPrompt.userChoice;
        } catch (_) {}
        deferredPrompt = null;
        installButton.classList.remove('is-visible');
      });
      navActions.insertBefore(installButton, navActions.firstChild);
      return installButton;
    };

    const showInstallButton = () => {
      const button = ensureInstallButton();
      if (!button) return;
      button.classList.add('is-visible');
    };

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js').catch(() => undefined);
    }

    window.addEventListener('beforeinstallprompt', (event) => {
      event.preventDefault();
      deferredPrompt = event;
      showInstallButton();
    });

    window.addEventListener('appinstalled', () => {
      deferredPrompt = null;
      if (installButton) installButton.classList.remove('is-visible');
    });

    if (isIos && !isStandalone) {
      showInstallButton();
    }
  }

  initPwaInstall();

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
        const bot = jordanDisplayName({ profileLabel: a.profileLabel, profile: a.profile, client: a.profileLabel }) || a.profileLabel || a.profile || 'Best Bot #1';
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
        const bot = jordanDisplayName({ profileLabel: b.profileLabel, profile: b.profile, client: b.profileLabel }) || b.profileLabel || b.profile || 'Best Bot #2';
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

  function dayPnlDisplayValue(row) {
    const dayNet = Number(row?.dayNetUsd);
    const open = openPnlValue(row);
    if (Number.isFinite(dayNet)) {
      if (Math.abs(dayNet) < 0.01 && Number.isFinite(open) && Math.abs(open) > 0.01) {
        return Number((dayNet + open).toFixed(2));
      }
      return dayNet;
    }
    if (Number.isFinite(open)) return open;
    return 0;
  }

  function rowDayReturnPct(row) {
    const direct = Number(row?.dayReturnPct);
    if (Number.isFinite(direct) && Math.abs(direct) > 0.0001) return direct;
    const dayStart = Number(row?.dayStartEquity ?? row?.dayStartBalance ?? row?.dayBaseline);
    const dayNet = dayPnlDisplayValue(row);
    if (Number.isFinite(dayStart) && dayStart > 0 && Number.isFinite(dayNet)) {
      return Number(((100 * dayNet) / dayStart).toFixed(2));
    }
    return Number.isFinite(direct) ? direct : null;
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
    const accountName = String(row?.accountName || '').toUpperCase();
    const profile = String(row?.profile || '').toUpperCase();
    return name.includes('JORDAN')
      || name.includes('CHRIS')
      || name.includes('BRANDON')
      || name.includes('SEAN')
      || name.includes('SARAH')
      || client.includes('CHRIS')
      || client.includes('BRANDON')
      || client.includes('JORDAN')
      || client.includes('SEAN')
      || client.includes('SARAH')
      || accountName.includes('CHRIS')
      || accountName.includes('BRANDON')
      || accountName.includes('JORDAN')
      || accountName.includes('SEAN')
      || profile.includes('JORDAN4')
      || profile.includes('SARAH');
  }

  function normalizedLabel(value) {
    return String(value || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  }

  function isAllowedMainBotRow(row) {
    const key = normalizedLabel(profileName(row));
    if (!(key.startsWith('BLUEPRINT') || key.startsWith('NEXUS'))) return false;
    if (key.includes('TF')) return false;
    if (key.includes('SETUP')) return false;
    if (key === 'SELLBLUEPRINT') return false;
    return true;
  }

  function isActiveJordanRow(row) {
    const key = [
      normalizedLabel(profileName(row)),
      normalizedLabel(row?.client),
      normalizedLabel(row?.accountName),
      normalizedLabel(row?.profile),
    ].join(' ');
    return key.includes('JORDAN')
      || key.includes('JORDAN1')
      || key.includes('JORDAN2')
      || key.includes('JORDAN3')
      || key.includes('JORDAN4')
      || key.includes('CHRIS')
      || key.includes('BRANDON')
      || key.includes('SEAN')
      || key.includes('SARAH');
  }

  function jordanDisplayName(row) {
    const key = [
      normalizedLabel(profileName(row)),
      normalizedLabel(row?.client),
      normalizedLabel(row?.accountName),
      normalizedLabel(row?.profile),
    ].join(' ');
    if (key.includes('JORDAN4') || key.includes('CHRIS')) return 'CHRIS';
    if (key.includes('JORDAN3') || key.includes('SARAH') || key.includes('BRANDON')) return 'BRANDON';
    if (key.includes('JORDAN2') || key.includes('SEAN')) return 'SEAN';
    if (key.includes('JORDAN1') || key.includes('JORDAN')) return 'JORDAN';
    return row?.profileLabel || row?.profile || '-';
  }

  function isHiddenWebsiteLiveRow(row, source = 'vds') {
    const name = profileName(row).toUpperCase();
    if (!name) return false;
    if (source === 'vds') {
      if (name.includes('DOMINION')) return true;
      if (name.includes('SURGE')) return true;
      if (name.includes('EDGE')) return true;
      if (name.includes('FRESH')) return true;
    }
    if (name.includes('BRAND_NEW')) return true;
    if (name.includes('COPIER_NEW')) return true;
    if (name.includes('COPIER_CLEAN')) return true;
    if (name.includes('TF_SETUP')) return true;
    if (name.includes('BLUEPRINT_TF_')) return true;
    if (name.includes('BLUEPRINT TF')) return true;
    return false;
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

  function prepareRows(rows, source = 'vds') {
    const filtered = (Array.isArray(rows) ? rows : [])
      .filter((r) => !isBaseOrPresetRow(r))
      .filter((r) => !isHiddenWebsiteLiveRow(r, source));
    const jordan = sortRowsByBotOrder(
      filtered
        .filter((r) => isJordanRow(r))
        .filter((r) => isActiveJordanRow(r)),
    );
    const main = sortRowsByBotOrder(
      filtered
        .filter((r) => !isJordanRow(r))
        .filter((r) => isAllowedMainBotRow(r)),
    );
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

  function isStrictLiveRow(row) {
    return String(row?.balanceSource || '').trim() === 'mt5-probe-live';
  }

  function exactMoneyCell(value, row) {
    return isStrictLiveRow(row) && Number.isFinite(Number(value))
      ? `$${Number(value).toFixed(2)}`
      : '-';
  }

  function exactSignedMoneyCell(value, row) {
    return isStrictLiveRow(row) && Number.isFinite(Number(value))
      ? money(value)
      : '-';
  }

  function exactPctCell(value, row) {
    return isStrictLiveRow(row) && Number.isFinite(Number(value))
      ? pct(value)
      : '-';
  }

  function renderLiveRows(targetEl, rows, emptyText = 'No live profiles yet.', options = {}) {
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
        const rawName = (row.profileLabel || row.profile || '-');
        const displayName = jordanDisplayName(row) || rawName;
        const displayDeposit = displayName === 'CHRIS' ? 2500 : flows.deposit;
        return `
          <tr>
            <td>${displayName}</td>
            <td>${row.account || '-'}</td>
            <td>${inferRiskPct(row)}</td>
            <td>${lev}</td>
            <td>${money(displayDeposit)}</td>
            <td>${money(flows.withdraw)}</td>
            <td>${isStrictLiveRow(row) && Number.isFinite(Number(row?.dayStartEquity ?? row?.dayStartBalance))
              ? `$${Number(row.dayStartEquity ?? row.dayStartBalance).toFixed(2)}`
              : '-'}</td>
            <td>${exactMoneyCell(row.balance, row)}</td>
            <td>${exactMoneyCell(row.equity, row)}</td>
            <td class="${numClass(openPnlValue(row))}">${exactSignedMoneyCell(openPnlValue(row), row)}</td>
            <td class="${numClass(dayPnlDisplayValue(row))}">${exactSignedMoneyCell(dayPnlDisplayValue(row), row)}</td>
            <td class="${numClass(row.totalNetUsd)}">${money(row.totalNetUsd)}</td>
            <td class="${numClass(row.totalReturnPct)}">${pct(row.totalReturnPct)}</td>
            <td class="${numClass(rowDayReturnPct(row))}">${exactPctCell(rowDayReturnPct(row), row)}</td>
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
            <td>${row.accountName || row.profileLabel || row.profile || '-'}</td>
            <td>${row.account || '-'}</td>
            <td>${inferRiskPct(row)}</td>
            <td>${lev}</td>
            <td>${exactMoneyCell(row.balance, row)}</td>
            <td>${exactMoneyCell(row.equity, row)}</td>
            <td class="${numClass(openPnlValue(row))}">${exactSignedMoneyCell(openPnlValue(row), row)}</td>
            <td class="${numClass(dayPnlDisplayValue(row))}">${exactSignedMoneyCell(dayPnlDisplayValue(row), row)}</td>
            <td class="${numClass(row.totalNetUsd)}">${money(row.totalNetUsd)}</td>
            <td class="${numClass(row.totalReturnPct)}">${pct(row.totalReturnPct)}</td>
            <td class="${numClass(rowDayReturnPct(row))}">${exactPctCell(rowDayReturnPct(row), row)}</td>
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
        const displayName = jordanDisplayName(row);
        const displayDeposit = displayName === 'CHRIS' ? 2500 : row.depositAmount;
        return `
          <tr>
            <td>${displayName}</td>
            <td>${row.account || '-'}</td>
            <td>${row.client || '-'}</td>
            <td>${row.botName || '-'}</td>
            <td>${Number.isFinite(Number(row.riskPct)) ? Number(row.riskPct).toFixed(2) : '-'}</td>
            <td>${lev}</td>
            <td>${money(displayDeposit)}</td>
            <td>${money(row.withdrawAmount)}</td>
            <td>${isStrictLiveRow(row) && Number.isFinite(Number(row?.dayStartEquity))
              ? `$${Number(row.dayStartEquity).toFixed(2)}`
              : '-'}</td>
            <td>${exactMoneyCell(row.balance, row)}</td>
            <td>${exactMoneyCell(row.equity, row)}</td>
            <td class="${numClass(row.openProfit)}">${exactSignedMoneyCell(row.openProfit, row)}</td>
            <td class="${numClass(dayPnlDisplayValue(row))}">${exactSignedMoneyCell(dayPnlDisplayValue(row), row)}</td>
            <td class="${numClass(row.dayReturnPct)}">${exactPctCell(row.dayReturnPct, row)}</td>
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
    if (!rowsVps && !rowsVds && !rowsLegacy && !rowsJordan) return;

    try {
      const nonce = Date.now();
      const isLegacyHome = !!rowsLegacy && !rowsVps && !rowsVds;
      const needsVps = !!rowsVps;
      const needsVds = !!rowsVds || !!rowsJordan || isLegacyHome;
      let vps = null;
      let vds = null;

      if (needsVps && needsVds) {
        const [respVps, respVds] = await Promise.all([
          fetch(`/api/bots/live?source=vps&_t=${nonce}`),
          fetch(`/api/bots/live?source=vds&_t=${nonce}`),
        ]);
        [vps, vds] = await Promise.all([respVps.json(), respVds.json()]);
        if (!respVps.ok || !vps.ok) throw new Error(vps.message || 'VPS live feed unavailable');
        if (!respVds.ok || !vds.ok) throw new Error(vds.message || 'VDS live feed unavailable');
      } else if (needsVps) {
        const respVps = await fetch(`/api/bots/live?source=vps&_t=${nonce}`);
        vps = await respVps.json();
        if (!respVps.ok || !vps.ok) throw new Error(vps.message || 'VPS live feed unavailable');
      } else if (needsVds) {
        const respVds = await fetch(`/api/bots/live?source=vds&_t=${nonce}`);
        vds = await respVds.json();
        if (!respVds.ok || !vds.ok) throw new Error(vds.message || 'VDS live feed unavailable');
      }

      if (!isLegacyHome && needsVps) {
        setFeedHealth('vpsHealthLabel', vps.stale ? 'warn' : 'ok', `VPS: ${vps.stale ? 'STALE' : 'LIVE'} • ${vps.summary?.profilesTotal ?? 0} profiles`);
      }
      if (!isLegacyHome && needsVds) {
        setFeedHealth('vdsHealthLabel', vds.stale ? 'warn' : 'ok', `VDS: ${vds.stale ? 'STALE' : 'LIVE'} • ${vds.summary?.profilesTotal ?? 0} profiles`);
      }

      const vpsSummary = (vps && vps.summary) || {};
      const vdsSummary = (vds && vds.summary) || {};
      const activeSummary = needsVps && !needsVds ? vpsSummary : vdsSummary;
      const day = document.getElementById('liveDayNet');
      const week = document.getElementById('liveWeekNet');
      const open = document.getElementById('liveOpenPnl');
      const profiles = document.getElementById('liveProfiles');
      const updated = document.getElementById('liveUpdated');
      if (day) day.textContent = money(activeSummary.dayNetUsd);
      if (week) week.textContent = money(activeSummary.weekNetUsd);
      if (open) {
        const activeRows = needsVps && !needsVds
          ? (Array.isArray(vps?.profiles) ? vps.profiles : [])
          : (Array.isArray(vds?.profiles) ? vds.profiles : []);
        const activeOpen = Number(activeSummary.openProfitUsd || 0);
        const rowsOpen = activeRows.reduce((a, r) => a + openPnlValue(r), 0);
        open.textContent = money(Math.abs(activeOpen) > 0 ? activeOpen : rowsOpen);
      }
      if (profiles) {
        if (needsVps && needsVds) profiles.textContent = `${vpsSummary.profilesTotal ?? 0}/${vdsSummary.profilesTotal ?? 0}`;
        else profiles.textContent = `${activeSummary.profilesTotal ?? 0}`;
      }
      if (updated) {
        if (needsVps && needsVds) updated.textContent = `${fmtTime(vps?.generatedAt)} / ${fmtTime(vds?.generatedAt)}`;
        else updated.textContent = `${fmtTime(vps?.generatedAt || vds?.generatedAt)}`;
      }

      const vpsRows = (vps && Array.isArray(vps.profiles)) ? vps.profiles : [];
      const vdsRows = (vds && Array.isArray(vds.profiles)) ? vds.profiles : [];
      const preparedVps = prepareRows(vpsRows, 'vps');
      const preparedVds = prepareRows(vdsRows, 'vds');
      const jordanProfileByAccount = new Map(
        preparedVds.jordan
          .map((r) => [String(r?.account || '').trim(), r])
          .filter(([k]) => k.length > 0),
      );
      const jordanProfileByName = new Map(
        preparedVds.jordan
          .map((r) => [normalizedLabel(profileName(r)), r])
          .filter(([k]) => k.length > 0),
      );
      const jordanFromCopier = Array.isArray(vds?.copierFeed?.rows)
        ? vds.copierFeed.rows
          .filter((r) => isActiveJordanRow(r))
          .map((r) => {
            const byAccount = jordanProfileByAccount.get(String(r?.account || '').trim());
            const byName = jordanProfileByName.get(normalizedLabel(profileName(r)));
            const base = byAccount || byName || null;
            if (!base) return r;
            const merged = { ...base, ...r };
            // Prefer copier identity fields, but keep live telemetry performance fields when copier is null.
            if (!Number.isFinite(Number(r?.openProfit)) && Number.isFinite(Number(base?.openProfit))) merged.openProfit = base.openProfit;
            if (!Number.isFinite(Number(r?.dayNetUsd)) && Number.isFinite(Number(base?.dayNetUsd))) merged.dayNetUsd = base.dayNetUsd;
            if (!Number.isFinite(Number(r?.weekNetUsd)) && Number.isFinite(Number(base?.weekNetUsd))) merged.weekNetUsd = base.weekNetUsd;
            if (!Number.isFinite(Number(r?.currentPnlWithOpen)) && Number.isFinite(Number(base?.currentPnlWithOpen))) merged.currentPnlWithOpen = base.currentPnlWithOpen;
            if (!Number.isFinite(Number(r?.totalNetUsd)) && Number.isFinite(Number(base?.totalNetUsd))) merged.totalNetUsd = base.totalNetUsd;
            if (!Number.isFinite(Number(r?.totalReturnPct)) && Number.isFinite(Number(base?.totalReturnPct))) merged.totalReturnPct = base.totalReturnPct;
            if (!Number.isFinite(Number(r?.dayReturnPct)) && Number.isFinite(Number(base?.dayReturnPct))) merged.dayReturnPct = base.dayReturnPct;
            if (!Number.isFinite(Number(r?.weekReturnPct)) && Number.isFinite(Number(base?.weekReturnPct))) merged.weekReturnPct = base.weekReturnPct;
            if (!merged?.status && base?.status) merged.status = base.status;
            if (!merged?.statusReason && base?.statusReason) merged.statusReason = base.statusReason;
            return merged;
          })
        : preparedVds.jordan;
      if (isLegacyHome) {
        renderLegacyHomeRows(rowsLegacy, preparedVds.main, 'No VDS live profiles yet.');
      } else {
        renderLiveRows(rowsVps, preparedVps.main, 'No VPS live profiles yet.');
        renderLiveRows(rowsVds, preparedVds.main, 'No VDS live profiles yet.');
        renderLiveRows(rowsJordan, jordanFromCopier, 'No active live copier accounts yet.');
        loadLiveCharts();
      }
    } catch (error) {
      if (rowsVps) rowsVps.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsVds) rowsVds.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsJordan) rowsJordan.innerHTML = `<tr><td colspan="17">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsLegacy) rowsLegacy.innerHTML = `<tr><td colspan="14">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
      if (rowsVps) setFeedHealth('vpsHealthLabel', 'bad', 'VPS: OFFLINE');
      if (rowsVds || rowsJordan || rowsLegacy) setFeedHealth('vdsHealthLabel', 'bad', 'VDS: OFFLINE');
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

  if (
    document.getElementById('liveFeedRowsVps')
    || document.getElementById('liveFeedRowsVds')
    || document.getElementById('liveFeedRowsJordan')
    || document.getElementById('liveFeedRows')
  ) {
    setInterval(loadLiveFeed, 3000);
  }
  if (document.getElementById('liveCopierFeedRows')) {
    setInterval(loadCopierFeedSection, 5000);
  }
})();
