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

  async function loadLiveFeed() {
    const rowsNode = document.getElementById('liveFeedRows');
    if (!rowsNode) return;

    try {
      const response = await fetch('/api/bots/live');
      const data = await response.json();
      if (!response.ok || !data.ok) throw new Error(data.message || 'Live feed unavailable');

      const summary = data.summary || {};
      const day = document.getElementById('liveDayNet');
      const week = document.getElementById('liveWeekNet');
      const open = document.getElementById('liveOpenPnl');
      const profiles = document.getElementById('liveProfiles');
      const updated = document.getElementById('liveUpdated');
      if (day) day.textContent = money(summary.dayNetUsd);
      if (week) week.textContent = money(summary.weekNetUsd);
      if (open) open.textContent = money(summary.openProfitUsd);
      if (profiles) profiles.textContent = String(summary.profilesTotal ?? 0);
      if (updated) updated.textContent = fmtTime(data.generatedAt);

      const rows = Array.isArray(data.profiles) ? data.profiles.slice(0, 25) : [];
      if (!rows.length) {
        rowsNode.innerHTML = '<tr><td colspan="12">No live profiles yet.</td></tr>';
        return;
      }

      rowsNode.innerHTML = rows
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
    } catch (error) {
      rowsNode.innerHTML = `<tr><td colspan="12">Live feed error: ${error.message || 'unavailable'}</td></tr>`;
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

  if (document.getElementById('liveFeedRows')) {
    setInterval(loadLiveFeed, 5000);
  }
})();
