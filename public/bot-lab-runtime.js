(function () {
  const API_BASES = ['', 'https://mt5-license-server-production.up.railway.app'];
  const REFRESH_MS = 10000;
  let categoryFilter = 'ALL';
  let accountSizeFilter = 'ALL';

  function el(id) {
    return document.getElementById(id);
  }

  function setText(id, value) {
    const node = el(id);
    if (node) node.textContent = value;
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function num(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }

  function money(value, withSign = true) {
    const n = num(value);
    if (n == null) return '-';
    const sign = n >= 0 ? '+' : '-';
    const text = `$${Math.abs(n).toFixed(2)}`;
    return withSign ? `${sign}${text}` : text;
  }

  function pct(value) {
    const n = num(value);
    if (n == null) return '-';
    const sign = n >= 0 ? '+' : '-';
    return `${sign}${Math.abs(n).toFixed(2)}%`;
  }

  function pf(value) {
    const n = num(value);
    return n == null ? '-' : n.toFixed(2);
  }

  function trades(value) {
    const n = num(value);
    return n == null ? '-' : String(Math.round(n));
  }

  function fmtDateTime(value) {
    if (!value) return '-';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '-';
    return d.toLocaleString('en-AU', {
      timeZone: 'Australia/Perth',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    });
  }

  function freshnessText(value) {
    if (!value) return '-';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '-';
    const diffMs = Date.now() - d.getTime();
    const diffMin = Math.max(0, Math.round(diffMs / 60000));
    if (diffMin < 1) return 'live now';
    if (diffMin === 1) return '1 min old';
    if (diffMin < 60) return `${diffMin} min old`;
    const diffHr = Math.round(diffMin / 60);
    if (diffHr === 1) return '1 hour old';
    return `${diffHr} hours old`;
  }

  function setHealth(state, text) {
    const node = el('botLabHealthLabel');
    if (!node) return;
    node.classList.remove('feed-label-ok', 'feed-label-warn', 'feed-label-bad');
    node.classList.add(state === 'bad' ? 'feed-label-bad' : state === 'ok' ? 'feed-label-ok' : 'feed-label-warn');
    node.textContent = text;
  }

  function categoryOf(row) {
    return String(
      row?.category ||
      row?.catalog?.category ||
      (String(row?.bot || '').toLowerCase().includes('silver') ? 'Silver' : 'Gold')
    );
  }

  function familyOf(row) {
    return String(row?.family || row?.strategy_family || row?.variant_raw || row?.variant || '-');
  }

  function windowOf(row) {
    if (row?.window) return String(row.window);
    if (row?.from_date && row?.to_date) return `${row.from_date} -> ${row.to_date}`;
    if (row?.fromDate && row?.toDate) return `${row.fromDate} -> ${row.toDate}`;
    return String(row?.range || '-');
  }

  function setupFacts(row) {
    const p = row?.params && typeof row.params === 'object' ? row.params : row || {};
    const parts = [];
    const risk = p.RiskPercent ?? p.risk_percent ?? p.FirstTradeRisk ?? p.BaseRiskPercent ?? p.RiskPerTrade;
    const maxRisk = p.MaxTotalRisk ?? p.OverrideMaxTotalRiskPct ?? p.RiskCapPercent;
    const sl = p.SL_Pips ?? p.SL_Pips_Gold ?? p.OverrideSLPips ?? row?.sl_pips;
    const tp1 = p.TP1_Pips ?? p.TP_Pips ?? p.OverrideQuickExitTargetPips ?? row?.tp1_pips;
    const tp2 = p.TP2_Pips ?? p.PartialClosePips ?? row?.tp2_pips;
    const tp3 = p.TP3_Pips ?? p.TP4_Pips ?? row?.tp3_pips;
    const tp4 = p.TP5_Pips ?? row?.tp4_pips;
    const trailStart = p.TrailStartPips ?? p.OverrideQuickTrailStartPips ?? p.TrailStopPips ?? row?.trail_start_pips;
    const trailDist = p.TrailDistancePips ?? p.OverrideQuickTrailLockPips ?? p.TrailStopPips ?? row?.trail_distance_pips;
    if (risk != null && risk !== '') parts.push(`Risk ${risk}%`);
    if (maxRisk != null && maxRisk !== '') parts.push(`Max risk ${maxRisk}%`);
    if (sl != null && sl !== '') parts.push(`SL ${sl}`);
    const tps = [tp1, tp2, tp3, tp4].filter((v) => v != null && v !== '');
    if (tps.length) parts.push(`TP ${tps.join('/')}`);
    if (trailStart != null || trailDist != null) parts.push(`Trail ${trailStart ?? '-'} / ${trailDist ?? '-'}`);
    return parts.join(' | ') || '-';
  }

  function accountSizeOf(row) {
    const value = num(row?.startingBalance ?? row?.deposit ?? row?.start_balance);
    return value == null ? null : Math.round(value);
  }

  function accountLabel(value) {
    if (value === 'ALL') return 'All starting balances';
    const n = num(value);
    return n == null ? 'All starting balances' : `Starting balance $${Math.round(n).toLocaleString('en-AU')}`;
  }

  function matchesCategory(row) {
    return categoryFilter === 'ALL' || categoryOf(row) === categoryFilter;
  }

  function matchesAccountSize(row) {
    if (accountSizeFilter === 'ALL') return true;
    const balance = accountSizeOf(row);
    return balance != null && balance === accountSizeFilter;
  }

  function combinedFilter(row) {
    return matchesCategory(row) && matchesAccountSize(row);
  }

  async function fetchJson(path) {
    let lastError = null;
    for (const base of API_BASES) {
      const url = `${base}${path}${path.includes('?') ? '&' : '?'}_t=${Date.now()}`;
      try {
        const resp = await fetch(url, { cache: 'no-store' });
        const payload = await resp.json();
        if (!resp.ok || !payload?.ok) {
          throw new Error(payload?.message || payload?.error || 'request failed');
        }
        return payload?.payload || payload?.data || payload;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError || new Error('request failed');
  }

  function rowsFromPayload(payload) {
    if (Array.isArray(payload?.results)) return payload.results;
    if (Array.isArray(payload?.rows)) return payload.rows;
    if (Array.isArray(payload?.runs)) return payload.runs;
    return [];
  }

  function renderCategoryFilters(allRows) {
    const node = el('botLabCategoryFilters');
    const summary = el('botLabCategorySummary');
    if (!node) return;
    const categories = ['ALL', ...Array.from(new Set(allRows.map(categoryOf).filter(Boolean))).sort()];
    node.innerHTML = categories.map((category) => {
      const count = category === 'ALL' ? allRows.length : allRows.filter((row) => categoryOf(row) === category).length;
      const active = category === categoryFilter ? ' active' : '';
      return `<button class="botlab-filter-chip${active}" type="button" data-category="${escapeHtml(category)}">${escapeHtml(category)} (${count})</button>`;
    }).join('');
    node.querySelectorAll('[data-category]').forEach((button) => {
      button.addEventListener('click', () => {
        categoryFilter = button.dataset.category || 'ALL';
        loadBotLab();
      });
    });
    if (summary) {
      summary.textContent = `Category filter: ${categoryFilter} | ${accountLabel(accountSizeFilter)} | Total tracked rows: ${allRows.length}`;
    }
  }

  function renderAccountFilterControls(allRows) {
    const presetsNode = el('botLabAccountPresets');
    const summaryNode = el('botLabAccountSummary');
    const input = el('botLabAccountSizeInput');
    const applyBtn = el('botLabAccountSizeApply');
    const resetBtn = el('botLabAccountSizeReset');
    if (!presetsNode || !summaryNode || !input || !applyBtn || !resetBtn) return;

    const balances = Array.from(new Set(allRows.map(accountSizeOf).filter((value) => value != null))).sort((a, b) => a - b);
    presetsNode.innerHTML = ['ALL'].concat(balances).map((value) => {
      const active = value === accountSizeFilter ? ' active' : '';
      const label = value === 'ALL' ? 'All balances' : `$${Number(value).toLocaleString('en-AU')}`;
      return `<button class="botlab-filter-chip${active}" type="button" data-account-size="${escapeHtml(String(value))}">${escapeHtml(label)}</button>`;
    }).join('');

    if (accountSizeFilter !== 'ALL') {
      input.value = String(accountSizeFilter);
    } else if (document.activeElement !== input) {
      input.value = '';
    }

    summaryNode.textContent = `${accountLabel(accountSizeFilter)} | Matching rows ${allRows.filter(matchesAccountSize).length}`;

    presetsNode.querySelectorAll('[data-account-size]').forEach((button) => {
      button.addEventListener('click', () => {
        const raw = button.dataset.accountSize || 'ALL';
        accountSizeFilter = raw === 'ALL' ? 'ALL' : Math.round(Number(raw));
        loadBotLab();
      });
    });

    applyBtn.onclick = () => {
      const parsed = Math.round(Number(input.value));
      accountSizeFilter = Number.isFinite(parsed) && parsed > 0 ? parsed : 'ALL';
      loadBotLab();
    };

    resetBtn.onclick = () => {
      accountSizeFilter = 'ALL';
      input.value = '';
      loadBotLab();
    };
  }

  function renderSimpleCards(id, rows, mapFn, emptyText) {
    const node = el(id);
    if (!node) return;
    if (!rows.length) {
      node.innerHTML = `<div class="muted">${escapeHtml(emptyText)}</div>`;
      return;
    }
    node.innerHTML = rows.map(mapFn).join('');
  }

  function renderDetailGrid(row) {
    const node = el('botLabDetailGrid');
    if (!node) return;
    if (!row) {
      node.innerHTML = '';
      return;
    }
    const pairs = [
      ['Bot', row.bot || '-'],
      ['Category', categoryOf(row)],
      ['Window', windowOf(row)],
      ['Start Balance', money(row.startingBalance ?? row.deposit ?? row.start_balance, false)],
      ['Final Balance', money(row.finalBalance ?? row.final_balance, false)],
      ['Net', money(row.netUsd ?? row.pnl)],
      ['Return', pct(row.returnPct ?? row.ret_pct)],
      ['Trades', trades(row.matchedCloses ?? row.trades)],
      ['Drawdown', pct(row.drawdownPct ?? row.drawdown_pct)],
      ['PF', pf(row.profitFactor ?? row.profit_factor ?? row.pf)],
      ['Family', familyOf(row)],
      ['Facts', setupFacts(row)],
    ];
    node.innerHTML = pairs.map(([label, value]) => (
      `<div class="fact-card"><div class="fact-label">${escapeHtml(label)}</div><div class="fact-value">${escapeHtml(value)}</div></div>`
    )).join('');
  }

  function renderTableRows(id, rowsHtml, emptyText, colspan) {
    const node = el(id);
    if (!node) return;
    node.innerHTML = rowsHtml.length ? rowsHtml.join('') : `<tr><td colspan="${colspan}">${escapeHtml(emptyText)}</td></tr>`;
  }

  function promotionRowMap(rows) {
    const map = new Map();
    (rows || []).forEach((row) => {
      const key = String(row?.bot || '').trim();
      if (key) map.set(key, row);
    });
    return map;
  }

  function displayResultStatus(row, sweepData) {
    const active = String(sweepData?.current_bot || '').trim().toLowerCase();
    const bot = String(row?.bot || '').trim().toLowerCase();
    if (String(sweepData?.status || '').toLowerCase() === 'running' && active && bot === active) {
      return 'RUNNING';
    }
    return row?.resultStatus || '-';
  }

  function displayResultReason(row, promotionMap, sweepData) {
    const active = String(sweepData?.current_bot || '').trim().toLowerCase();
    const bot = String(row?.bot || '').trim().toLowerCase();
    if (String(sweepData?.status || '').toLowerCase() === 'running' && active && bot === active) {
      const parts = ['Active sweep'];
      if (sweepData?.trial && sweepData?.total_trials) parts.push(`trial ${sweepData.trial}/${sweepData.total_trials}`);
      if (sweepData?.rows_completed != null) parts.push(`rows ${sweepData.rows_completed}`);
      return parts.join(' | ');
    }
    const promotion = promotionMap.get(String(row?.bot || '').trim());
    if (promotion?.reason) return promotion.reason;
    return row?.resultReason || '-';
  }

  async function loadBotLab() {
    try {
      const [latest, analysis, progress, catalog, history, schedule, sweep, discord] = await Promise.allSettled([
        fetchJson('/api/bot-lab/latest'),
        fetchJson('/api/bot-lab/analysis'),
        fetchJson('/api/bot-lab/progress'),
        fetchJson('/api/bot-lab/catalog'),
        fetchJson('/api/bot-lab/history?limit=20'),
        fetchJson('/api/bot-lab/schedule'),
        fetchJson('/api/param-sweep/status'),
        fetchJson('/api/bot-lab/discord-summary'),
      ]);

      const latestData = latest.status === 'fulfilled' ? latest.value : { results: [] };
      const analysisData = analysis.status === 'fulfilled' ? analysis.value : {};
      const progressData = progress.status === 'fulfilled' ? progress.value : {};
      const catalogData = catalog.status === 'fulfilled' ? catalog.value : {};
      const historyData = history.status === 'fulfilled' ? history.value : { results: [] };
      const scheduleData = schedule.status === 'fulfilled' ? schedule.value : {};
      const sweepData = sweep.status === 'fulfilled' ? sweep.value : {};
      const discordData = discord.status === 'fulfilled' ? discord.value : {};

      const latestRows = rowsFromPayload(latestData);
      const historyRows = rowsFromPayload(historyData);
      const bestByBot = Array.isArray(analysisData.best_by_bot) ? analysisData.best_by_bot : [];
      const promotions = Array.isArray(analysisData.promotion_candidates) ? analysisData.promotion_candidates : [];
      const validations = Array.isArray(analysisData.validation_windows) ? analysisData.validation_windows : [];
      const categoryRows = Array.isArray(progressData.categories) ? progressData.categories : [];
      const progressRows = Array.isArray(progressData.bots) ? progressData.bots : [];
      const catalogRows = Array.isArray(catalogData.rows) ? catalogData.rows : [];
      const updatedCandidates = [
        latestData.updatedAt,
        analysisData.updatedAt,
        progressData.updatedAt,
        historyData.updatedAt,
        sweepData.updatedAt,
        discordData.updatedAt,
      ].map((value) => {
        const d = value ? new Date(value) : null;
        return d && !Number.isNaN(d.getTime()) ? d : null;
      }).filter(Boolean);
      const lastUpdated = updatedCandidates.length
        ? new Date(Math.max(...updatedCandidates.map((d) => d.getTime())))
        : null;
      const allRows = []
        .concat(bestByBot)
        .concat(historyRows)
        .concat(latestRows)
        .concat(catalogRows)
        .filter((row) => row && row.bot);

      renderAccountFilterControls(allRows);
      renderCategoryFilters(allRows);

      const filteredBest = bestByBot.filter(combinedFilter);
      const filteredHistory = historyRows.filter(combinedFilter);
      const filteredLatest = latestRows.filter(combinedFilter);
      const filteredCatalog = catalogRows.filter(combinedFilter);
      const filteredPromotions = promotions.filter(combinedFilter);
      const filteredValidations = validations.filter(combinedFilter);
      const filteredProgress = progressRows.filter(combinedFilter);
      const filteredCategories = categoryFilter === 'ALL'
        ? categoryRows
        : categoryRows.filter((row) => String(row.category) === categoryFilter);
      const promotionMap = promotionRowMap(filteredPromotions);
      const activeBalanceLabel = accountLabel(accountSizeFilter);
      const activeRowCount = allRows.filter(combinedFilter).length;

      const focusRow = filteredBest[0] || filteredProgress[0] || filteredHistory[0] || filteredLatest[0] || null;
      renderDetailGrid(focusRow);
      setText('botLabFactsLine', focusRow ? `Bot ${focusRow.bot} | Window ${windowOf(focusRow)} | Start ${money(focusRow.startingBalance ?? focusRow.deposit ?? focusRow.start_balance, false)} | Final ${money(focusRow.finalBalance ?? focusRow.final_balance, false)} | Return ${pct(focusRow.returnPct ?? focusRow.ret_pct)} | Trades ${trades(focusRow.matchedCloses ?? focusRow.trades)} | DD ${pct(focusRow.drawdownPct ?? focusRow.drawdown_pct)} | ${setupFacts(focusRow)}` : `${activeBalanceLabel} | No optimizer facts match this filter yet.`);
      setText('botLabSettingsLine', focusRow ? `Selected Settings: ${setupFacts(focusRow)}` : `${activeBalanceLabel} | Waiting for matching settings data.`);

      const summary = analysisData.summary || discordData.status || {};
      setText('botLabTrackedBots', String(summary.bots_tracked ?? summary.tracked_bots ?? '-'));
      setText('botLabTestedBots', String(summary.attempted_bots ?? summary.tested_bots ?? '-'));
      setText('botLabPendingBots', String(summary.pending_bots ?? '-'));
      setText('botLabPromotionReady', String(summary.promotion_ready ?? '-'));
      setText('botLabDataUpdated', lastUpdated ? fmtDateTime(lastUpdated) : '-');
      setText('botLabDataFreshness', freshnessText(lastUpdated));

      setText('botLabBestFamily', filteredBest[0] ? familyOf(filteredBest[0]) : '-');
      setText('botLabBestRisk', filteredBest[0] ? String(filteredBest[0]?.params?.RiskPercent ?? filteredBest[0]?.risk_percent ?? '-') : '-');
      setText('botLabBestTrail', filteredBest[0] ? `${filteredBest[0]?.params?.TrailStartPips ?? filteredBest[0]?.trail_start_pips ?? '-'} / ${filteredBest[0]?.params?.TrailDistancePips ?? filteredBest[0]?.trail_distance_pips ?? '-'}` : '-');
      setText('botLabBestTp', filteredBest[0] ? [filteredBest[0]?.params?.TP1_Pips ?? filteredBest[0]?.tp1_pips, filteredBest[0]?.params?.TP2_Pips ?? filteredBest[0]?.tp2_pips, filteredBest[0]?.params?.TP3_Pips ?? filteredBest[0]?.tp3_pips, filteredBest[0]?.params?.TP4_Pips ?? filteredBest[0]?.tp4_pips].filter((v) => v != null && v !== '').join('/') || '-' : '-');
      const worstDdRow = filteredBest.slice().sort((a, b) => (num(b.drawdown_pct) ?? -999) - (num(a.drawdown_pct) ?? -999))[0];
      setText('botLabWorstDd', worstDdRow ? `${worstDdRow.bot} ${pct(worstDdRow.drawdown_pct)}` : '-');
      setText('botLabCoverage', `${summary.attempted_bots ?? new Set(bestByBot.map((row) => row.bot)).size} bots`);

      setText('botLabScheduleLine', scheduleData?.summary || scheduleData?.message || 'Schedule status unavailable');
      const lastUpdatedMs = lastUpdated ? lastUpdated.getTime() : 0;
      const stale = lastUpdatedMs ? (Date.now() - lastUpdatedMs) > (20 * 60 * 1000) : false;
      if (String(sweepData.status || '').toLowerCase() === 'running') {
        setText('botLabSweepLine', `Sweep running | Bot ${sweepData.current_bot || '-'} | Trial ${sweepData.trial || '-'} / ${sweepData.total_trials || '-'} | Rows ${sweepData.rows_completed || 0}`);
        setHealth('ok', `BOT LAB: RUNNING • ${sweepData.current_bot || '-'} • ${sweepData.rows_completed || 0} rows`);
      } else if (stale) {
        setText('botLabSweepLine', sweepData?.updatedAt ? `Last sweep update ${fmtDateTime(sweepData.updatedAt)}` : 'No active sweep');
        setHealth('warn', `BOT LAB: STALE • Last update ${freshnessText(lastUpdated)}`);
      } else {
        setText('botLabSweepLine', sweepData?.updatedAt ? `Last sweep update ${fmtDateTime(sweepData.updatedAt)}` : 'No active sweep');
        setHealth('ok', `BOT LAB: LIVE • ${activeBalanceLabel} • ${filteredBest.length} best rows • ${filteredHistory.length} history rows`);
      }

      const spotlight = filteredPromotions[0] || filteredBest[0] || null;
      setText('botLabPromotionName', spotlight ? `${spotlight.bot} ${spotlight.promote === false ? 'is not promotion ready' : 'is the current lead'}` : 'No promotion candidate yet');
      setText(
        'botLabPromotionSummary',
        spotlight
          ? `Window ${windowOf(spotlight)} | Start ${money(spotlight.startingBalance ?? spotlight.deposit ?? spotlight.start_balance, false)} | Final ${money(spotlight.finalBalance ?? spotlight.final_balance, false)} | Return ${pct(spotlight.returnPct ?? spotlight.ret_pct)} | DD ${pct(spotlight.drawdownPct ?? spotlight.drawdown_pct)} | Trades ${trades(spotlight.matchedCloses ?? spotlight.trades)} | ${setupFacts(spotlight)} | ${spotlight.reason || spotlight.resultReason || 'No promotion note'}`
          : 'Waiting for promotion analysis...'
      );

      renderSimpleCards(
        'botLabChampionCards',
        filteredBest.slice(0, 6),
        (row) => `<div class="botlab-chip-card"><strong>${escapeHtml(row.bot)}</strong><span>${escapeHtml(familyOf(row))}</span><span>${escapeHtml(pct(row.ret_pct))} | DD ${escapeHtml(pct(row.drawdown_pct))} | Trades ${escapeHtml(trades(row.trades))}</span></div>`,
        'No champion cards yet.'
      );
      renderSimpleCards(
        'botLabFailureCards',
        (analysisData.failure_summary || []).slice(0, 6),
        (row) => `<div class="botlab-chip-card"><strong>${escapeHtml(row.failure_class || 'failure')}</strong><span>${escapeHtml(String(row.failures || 0))} failures</span><span>${escapeHtml((row.bots || []).join(', ') || '-')}</span></div>`,
        'No failure audit yet.'
      );
      renderSimpleCards(
        'botLabBlockedCards',
        filteredProgress.filter((row) => {
          const status = displayResultStatus(row, sweepData);
          return status === 'PENDING' || status === 'RUNNING';
        }).slice(0, 8),
        (row) => `<div class="botlab-chip-card"><strong>${escapeHtml(row.bot)}</strong><span>${escapeHtml(displayResultReason(row, promotionMap, sweepData))}</span><span>${escapeHtml(displayResultStatus(row, sweepData))}</span></div>`,
        'No pending or blocked bots.'
      );

      renderTableRows(
        'botLabCategoryRows',
        filteredCategories.map((row) => `
          <tr>
            <td>${escapeHtml(row.category)}</td>
            <td>${escapeHtml(row.bots)}</td>
            <td>${escapeHtml(row.ready)}</td>
            <td>${escapeHtml(row.tested)}</td>
            <td>${escapeHtml(row.promotionReady)}</td>
            <td>${escapeHtml(pct(row.bestReturn))}</td>
          </tr>
        `),
        'No category summary yet.',
        6
      );

      const testedCount = filteredProgress.filter((row) => row.resultStatus === 'HAS_RESULT' || row.resultStatus === 'LIMITED_RESULT').length;
      const limitedCount = filteredProgress.filter((row) => row.resultStatus === 'LIMITED_RESULT').length;
      const readyCount = filteredProgress.filter((row) => row.resultStatus === 'HAS_RESULT').length;
      const pendingCount = filteredProgress.filter((row) => row.resultStatus === 'PENDING').length;
      const runningCount = filteredProgress.filter((row) => displayResultStatus(row, sweepData) === 'RUNNING').length;
      const blockerRows = filteredProgress
        .map((row) => ({ bot: row.bot, reason: displayResultReason(row, promotionMap, sweepData) }))
        .filter((row) => row.reason && row.reason !== '-' && !/Stored result/i.test(row.reason) && !/Completed pass/i.test(row.reason) && !/fully written/i.test(row.reason))
        .slice(0, 4)
        .map((row) => `${row.bot}: ${row.reason}`);
      setText(
        'botLabProgressSummary',
        `${activeBalanceLabel} | Matching rows ${activeRowCount} | Attempted ${testedCount}/${filteredProgress.length} | Ready ${readyCount} | Limited ${limitedCount} | Pending ${pendingCount} | Running ${runningCount} | Promotion ready ${filteredProgress.filter((row) => row.promotion === 'YES').length} | Blockers ${blockerRows.length ? blockerRows.join(' ; ') : 'none'}`
      );
      renderTableRows(
        'botLabProgressRows',
        filteredProgress.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot)}</td>
            <td>${escapeHtml(row.category)}</td>
            <td>${escapeHtml(row.ready ? 'YES' : 'NO')}</td>
            <td>${escapeHtml(displayResultStatus(row, sweepData))}</td>
            <td>${escapeHtml(displayResultReason(row, promotionMap, sweepData))}</td>
            <td>${escapeHtml(money(row.startingBalance, false))}</td>
            <td>${escapeHtml(money(row.finalBalance, false))}</td>
            <td>${escapeHtml(pct(row.bestReturn))}</td>
            <td>${escapeHtml(trades(row.bestTrades))}</td>
            <td>${escapeHtml(pct(row.bestDrawdown))}</td>
            <td>${escapeHtml(pf(row.bestProfitFactor))}</td>
            <td>${escapeHtml(row.bestWindow || '-')}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
            <td>${escapeHtml(String(row.validationRuns ?? '-'))}</td>
            <td>${escapeHtml(pct(row.bestValidation))}</td>
            <td>${escapeHtml(row.promotion || 'NO')}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No bot progress yet.' : `No bot progress found for ${activeBalanceLabel.toLowerCase()}.`,
        16
      );

      setText('botLabCatalogSummary', `${activeBalanceLabel} | ${filteredCatalog.length} catalog entries | ${filteredCatalog.filter((row) => row.optimizer_ready).length} ready`);
      renderTableRows(
        'botLabCatalogRows',
        filteredCatalog.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(row.category || '-')}</td>
            <td>${escapeHtml(row.profile || '-')}</td>
            <td>${escapeHtml(String(row.readiness || row.status || '-').toUpperCase())}</td>
            <td>${escapeHtml(row.expert || '-')}</td>
            <td>${escapeHtml(row.setfile || '-')}</td>
            <td>${escapeHtml(row.optimizer_ready ? 'YES' : 'NO')}</td>
            <td>${escapeHtml(row.note || '-')}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No bot catalog yet.' : `No catalog rows found for ${activeBalanceLabel.toLowerCase()}.`,
        8
      );

      renderTableRows(
        'botLabRows',
        filteredLatest.slice(0, 20).map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(categoryOf(row))}</td>
            <td>${escapeHtml(row.variant || row.case_id || '-')}</td>
            <td>${escapeHtml(row.status || '-')}</td>
            <td>${escapeHtml(money(row.pnl))}</td>
            <td>${escapeHtml(pct(row.ret_pct))}</td>
            <td>${escapeHtml(trades(row.trades))}</td>
            <td>${escapeHtml(pct(row.win_rate_pct))}</td>
            <td>${escapeHtml(pf(row.pf))}</td>
            <td>${escapeHtml(pct(row.drawdown_pct))}</td>
            <td>${escapeHtml(windowOf(row))}</td>
            <td>${escapeHtml(money(row.deposit, false))}</td>
            <td>${escapeHtml(money(row.final_balance, false))}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
            <td>${escapeHtml(row.fail_reason || '-')}</td>
            <td>${escapeHtml(fmtDateTime(row.updated_at || row.completed_at || analysisData.updatedAt))}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No completed latest bot test yet.' : `No completed latest bot test found for ${activeBalanceLabel.toLowerCase()}.`,
        16
      );

      const familyMap = new Map();
      filteredHistory.forEach((row) => {
        const key = familyOf(row);
        if (!familyMap.has(key)) {
          familyMap.set(key, { family: key, runs: 0, pass: 0, bestReturn: null, total: 0, count: 0, bestScore: null });
        }
        const item = familyMap.get(key);
        item.runs += 1;
        if (String(row.status || '').toUpperCase() === 'PASS') item.pass += 1;
        const ret = num(row.ret_pct);
        if (ret != null) {
          item.bestReturn = item.bestReturn == null ? ret : Math.max(item.bestReturn, ret);
          item.total += ret;
          item.count += 1;
        }
        const score = num(row.score);
        if (score != null) item.bestScore = item.bestScore == null ? score : Math.max(item.bestScore, score);
      });
      renderTableRows(
        'botLabFamilySummaryRows',
        Array.from(familyMap.values()).sort((a, b) => (b.bestScore ?? -999999) - (a.bestScore ?? -999999)).map((row) => `
          <tr>
            <td>${escapeHtml(row.family)}</td>
            <td>${escapeHtml(String(row.runs))}</td>
            <td>${escapeHtml(String(row.pass))}</td>
            <td>${escapeHtml(pct(row.bestReturn))}</td>
            <td>${escapeHtml(row.count ? pct(row.total / row.count) : '-')}</td>
            <td>${escapeHtml(row.bestScore == null ? '-' : row.bestScore.toFixed(2))}</td>
          </tr>
        `),
        'No family summary yet.',
        6
      );

      renderTableRows(
        'botLabBestByBotRows',
        filteredBest.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(categoryOf(row))}</td>
            <td>${escapeHtml(familyOf(row))}</td>
            <td>${escapeHtml(pct(row.ret_pct))}</td>
            <td>${escapeHtml(pct(row.drawdown_pct))}</td>
            <td>${escapeHtml(trades(row.trades))}</td>
            <td>${escapeHtml(pf(row.pf))}</td>
            <td>${escapeHtml(windowOf(row))}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
            <td>${escapeHtml(num(row.score) == null ? '-' : Number(row.score).toFixed(2))}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No per-bot winners yet.' : `No per-bot winners found for ${activeBalanceLabel.toLowerCase()}.`,
        10
      );

      renderTableRows(
        'botLabPromotionRows',
        filteredPromotions.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(row.promote ? 'YES' : 'NO')}</td>
            <td>${escapeHtml(row.family || '-')}</td>
            <td>${escapeHtml(pct(row.ret_pct))}</td>
            <td>${escapeHtml(pct(row.drawdown_pct))}</td>
            <td>${escapeHtml(trades(row.trades))}</td>
            <td>${escapeHtml(pf(row.pf))}</td>
            <td>${escapeHtml(row.window || '-')}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
            <td>${escapeHtml(row.reason || '-')}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No promotion candidates yet.' : `No promotion candidates found for ${activeBalanceLabel.toLowerCase()}.`,
        10
      );

      renderTableRows(
        'botLabValidationRows',
        filteredValidations.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(row.window || '-')}</td>
            <td>${escapeHtml(money(row.deposit, false))}</td>
            <td>${escapeHtml(row.strategy_family || '-')}</td>
            <td>${escapeHtml(String(row.runs ?? '-'))}</td>
            <td>${escapeHtml(String(row.pass ?? '-'))}</td>
            <td>${escapeHtml(pct(row.best_return_pct))}</td>
            <td>${escapeHtml(pct(row.avg_return_pct))}</td>
            <td>${escapeHtml(num(row.best_score) == null ? '-' : Number(row.best_score).toFixed(2))}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No validation windows yet.' : `No validation windows found for ${activeBalanceLabel.toLowerCase()}.`,
        9
      );

      renderTableRows(
        'botLabHistoryRows',
        filteredHistory.map((row) => `
          <tr>
            <td>${escapeHtml(row.bot || '-')}</td>
            <td>${escapeHtml(categoryOf(row))}</td>
            <td>${escapeHtml(row.variant || row.case_id || '-')}</td>
            <td>${escapeHtml(row.status || '-')}</td>
            <td>${escapeHtml(money(row.pnl))}</td>
            <td>${escapeHtml(pct(row.ret_pct))}</td>
            <td>${escapeHtml(trades(row.trades))}</td>
            <td>${escapeHtml(pct(row.win_rate_pct))}</td>
            <td>${escapeHtml(pf(row.pf))}</td>
            <td>${escapeHtml(pct(row.drawdown_pct))}</td>
            <td>${escapeHtml(windowOf(row))}</td>
            <td>${escapeHtml(money(row.deposit, false))}</td>
            <td>${escapeHtml(money(row.final_balance, false))}</td>
            <td title="${escapeHtml(setupFacts(row))}">${escapeHtml(setupFacts(row))}</td>
            <td>${escapeHtml(row.fail_reason || '-')}</td>
            <td>${escapeHtml(fmtDateTime(row.updated_at || row.completed_at || historyData.updatedAt))}</td>
          </tr>
        `),
        accountSizeFilter === 'ALL' ? 'No recent completed bot tests yet.' : `No recent completed bot tests found for ${activeBalanceLabel.toLowerCase()}.`,
        16
      );
    } catch (error) {
      setHealth('bad', 'BOT LAB: OFFLINE');
      setText('botLabFactsLine', `Bot Lab error: ${error.message || 'unavailable'}`);
      setText('botLabSettingsLine', 'Bot Lab runtime failed.');
      setText('botLabPromotionName', 'Promotion data unavailable');
      setText('botLabPromotionSummary', `Bot Lab error: ${error.message || 'unavailable'}`);
      renderTableRows('botLabRows', [], `Bot-lab error: ${error.message || 'unavailable'}`, 16);
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    loadBotLab();
    setInterval(loadBotLab, REFRESH_MS);
  });
})();
