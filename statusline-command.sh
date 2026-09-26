#!/usr/bin/env bash
cat | node -e "
const { execSync } = require('child_process');
const fs = require('fs');
const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  try {
    const d = JSON.parse(Buffer.concat(chunks).toString());
    const fmtK = n => {
      if (!n) return '0';
      if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
      if (n >= 1_000) return (n / 1_000).toFixed(1) + 'k';
      return n.toString();
    };
    const hhmm = t => {
      const x = new Date(t);
      return String(x.getHours()).padStart(2, '0') + ':' + String(x.getMinutes()).padStart(2, '0');
    };
    const red = s => '\x1b[31m' + s + '\x1b[0m';

    // Model: 'claude-opus-5[1m]' -> 'Opus5(high)', 'claude-opus-4-6' -> 'Opus4.6(high)'
    const mid = (d.model?.id || '').replace(/\[.*?\]/g, '');
    const effort = d.effort?.level ? '(' + d.effort.level + ')' : '';
    const modelName = (() => {
      const m = mid.match(/claude-([a-z]+)-(\d+)(?:-(\d+))?/i);
      if (m) return m[1].charAt(0).toUpperCase() + m[1].slice(1) + m[2] + (m[3] ? '.' + m[3] : '');
      return (d.model?.display_name || 'Unknown').replace(/\s*\(.*?\)/g, '').replace(/\s+/g, '');
    })() + effort;

    // Context remaining % with used/total
    const ctxSize = d.context_window?.context_window_size;
    const pct = d.context_window?.remaining_percentage;
    const ctxUsedLabel = ctxSize && pct != null
      ? fmtK(ctxSize - Math.round(ctxSize * pct / 100)) + '/' + fmtK(ctxSize)
      : '';

    // Cost (+ increase since the previous cost change, persisted per session since the payload only has the total)
    const cost = d.cost?.total_cost_usd;
    let costDelta = null;
    try {
      const sid = String(d.session_id || '').replace(/[^A-Za-z0-9_-]/g, '');
      if (sid && cost != null) {
        const sf = require('path').join(require('os').tmpdir(), 'claude-statusline-cost-' + sid + '.json');
        let st = null;
        try { st = JSON.parse(fs.readFileSync(sf, 'utf8')); } catch {}
        if (st && cost === st.cost) costDelta = st.delta;
        else {
          // No baseline yet, or the total went down (e.g. session restarted): reset without a delta
          if (st && cost > st.cost) costDelta = cost - st.cost;
          fs.writeFileSync(sf, JSON.stringify({ cost, delta: costDelta }));
        }
      }
    } catch {}
    const fmtUsd = v => v >= 0.01 ? v.toFixed(3).slice(0, -1) : v.toFixed(3);

    // Cache hit ratio (+ tokens written to cache on the last turn)
    const u = d.context_window?.current_usage;
    const cacheRead = u?.cache_read_input_tokens || 0;
    const cacheCreate = u?.cache_creation_input_tokens || 0;
    const inputTok = u?.input_tokens || 0;
    const totalInput = inputTok + cacheRead + cacheCreate;
    const cacheRatio = totalInput > 0 ? Math.round((cacheRead / totalInput) * 100) : null;

    // Walk the transcript backwards to the last user prompt.
    // Last API response time + cache expiry, from the last assistant entry.
    // TTL: 1h if the last turn wrote to the 1h cache (or wrote nothing), 5m if it only wrote to the 5m cache.
    // Last turn's effort: thinking/output tokens and API steps (one response spans several entries sharing
    // a message id, so each id counts once), and wall time (turn_duration once the turn ends, else prompt → last entry).
    let cacheLabel = '';
    let cacheCold = false;
    let cacheOnly5m = false;
    let turnLabel = '';
    try {
      const tp = d.transcript_path;
      if (tp && fs.existsSync(tp)) {
        const size = fs.statSync(tp).size;
        const len = Math.min(size, 2 * 1024 * 1024);
        const fd = fs.openSync(tp, 'r');
        const buf = Buffer.alloc(len);
        fs.readSync(fd, buf, 0, len, size - len);
        fs.closeSync(fd);
        const lines = buf.toString().split('\n');
        const ids = new Set();
        let thinkTok = 0, outTok = 0, hasThink = false, durMs = null, lastTs = null;
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i];
          if (!line.includes('\"assistant\"') && !line.includes('\"user\"') && !line.includes('\"turn_duration\"')) continue;
          let e; try { e = JSON.parse(line); } catch { continue; }
          if (e.isSidechain || !e.timestamp) continue;
          if (lastTs == null) lastTs = new Date(e.timestamp).getTime();
          if (e.type === 'system' && e.subtype === 'turn_duration') {
            if (durMs == null && !ids.size) durMs = e.durationMs;
            continue;
          }
          if (e.type === 'assistant') {
            if (!cacheLabel) {
              const cc = e.message?.usage?.cache_creation;
              const only5m = cc && (cc.ephemeral_5m_input_tokens || 0) > 0 && (cc.ephemeral_1h_input_tokens || 0) === 0;
              const ttlMs = (only5m ? 5 : 60) * 60 * 1000;
              const last = new Date(e.timestamp).getTime();
              const expiry = last + ttlMs;
              const hot = Date.now() < expiry;
              cacheCold = !hot;
              cacheOnly5m = only5m;
              cacheLabel = (hot ? '\u{1F525}' : '❄️') + hhmm(last) + '→' + hhmm(expiry) + (only5m ? '(5m)' : '');
            }
            const id = e.message?.id;
            const us = e.message?.usage;
            if (id && us && !ids.has(id)) {
              ids.add(id);
              outTok += us.output_tokens || 0;
              const t = us.output_tokens_details?.thinking_tokens;
              if (t != null) { hasThink = true; thinkTok += t; }
            }
            continue;
          }
          // A prompt typed by the user (not a tool result, injected meta text or an interrupt marker) starts the turn
          const c = e.message?.content;
          const isPrompt = e.type === 'user' && !e.isMeta && !e.interruptedMessageId
            && (typeof c === 'string' || (Array.isArray(c) && c.some(b => b.type === 'text') && !c.some(b => b.type === 'tool_result')));
          if (!isPrompt) continue;
          if (ids.size) {
            const ms = durMs != null ? durMs : lastTs - new Date(e.timestamp).getTime();
            const s = Math.max(0, Math.round(ms / 1000));
            const dur = s < 60 ? s + 's'
              : s < 3600 ? Math.floor(s / 60) + 'm' + String(s % 60).padStart(2, '0') + 's'
              : Math.floor(s / 3600) + 'h' + String(Math.floor(s % 3600 / 60)).padStart(2, '0') + 'm';
            turnLabel = '\u{1F9E0} ' + (hasThink ? fmtK(thinkTok) + '/' : '') + fmtK(outTok)
              + ' \u{F0456} ' + ids.size + ' \u{F051B} ' + dur;
          }
          break;
        }
      }
    } catch {}

    // Estimated cost of the next request once the cache has expired: rewriting the whole prefix
    // at the cache-write price (input $/MTok x 2 for the 1h TTL, x 1.25 for 5m)
    const inputPrice = (() => {
      const m = mid.match(/claude-([a-z]+)-(\d+)(?:-(\d+))?/i);
      if (!m) return null;
      const fam = m[1].toLowerCase(), ver = Number(m[2] + '.' + (m[3] || 0));
      if (fam === 'fable') return 10;
      if (fam === 'opus') return ver >= 5.5 ? 4 : ver >= 4.5 ? 5 : 15;
      if (fam === 'sonnet') return ver >= 5 ? 2 : 3;
      if (fam === 'haiku' && ver >= 4.5) return 1;
      return null;
    })();
    const recacheTok = d.prompt_cache?.recache_tokens_if_cold;
    const ttl5m = d.prompt_cache?.ttl ? d.prompt_cache.ttl === '5m' : cacheOnly5m;
    const resumeCost = inputPrice && recacheTok ? recacheTok * inputPrice * (ttl5m ? 1.25 : 2) / 1e6 : null;

    // Git branch from project cwd, with * for uncommitted changes and commits ahead/behind upstream
    let branch = '';
    const cwd = d.cwd || '';
    try {
      const st = execSync('git --no-optional-locks status --porcelain=v2 --branch', { cwd: cwd || undefined, encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).split('\n');
      let head = '', ahead = 0, behind = 0, dirty = false;
      for (const l of st) {
        if (l.startsWith('# branch.head ')) head = l.slice(14);
        else if (l.startsWith('# branch.ab ')) [ahead, behind] = l.slice(12).split(' ').map(x => Math.abs(parseInt(x, 10)));
        else if (l && !l.startsWith('#')) dirty = true;
      }
      if (head) branch = head + (dirty ? '*' : '') + (ahead ? '↑' + ahead : '') + (behind ? '↓' + behind : '');
    } catch {}

    // Lines changed this session, and plan usage limits as '5h/7d: 4%/81%' (each value red at 80% or more)
    const added = d.cost?.total_lines_added || 0;
    const removed = d.cost?.total_lines_removed || 0;
    const lims = [['five_hour', '5h'], ['seven_day', '7d']]
      .filter(([k]) => d.rate_limits?.[k]?.used_percentage != null)
      .map(([k, label]) => [label, Math.round(d.rate_limits[k].used_percentage)]);
    const limits = lims.length
      ? lims.map(([label]) => label).join('/') + ': ' + lims.map(([, p]) => p >= 80 ? red(p + '%') : p + '%').join('/')
      : '';

    // Build status line (uses Nerd Font icons)
    // Line 1: what decides spending (context, cost, cache, plan limits). Line 2: where you are and what changed.
    const parts = [modelName];
    if (pct != null) {
      const ctx = '\u{1F4CA} ' + Math.floor(pct) + '%' + (ctxUsedLabel ? '(' + ctxUsedLabel + ')' : '');
      parts.push(pct < 20 ? red(ctx) : ctx);
    }
    if (cost != null) parts.push('\u{1F4B2}' + fmtUsd(cost) + (costDelta ? '(+' + fmtUsd(costDelta) + ')' : ''));
    if (cacheRatio != null) parts.push('\u{F0AB0} ' + cacheRatio + '%' + (cacheCreate ? '(+' + fmtK(cacheCreate) + ')' : ''));
    if (cacheLabel) {
      const c = cacheLabel + (resumeCost != null ? '(~\$' + fmtUsd(resumeCost) + ')' : '');
      parts.push(cacheCold ? red(c) : c);
    }
    if (limits) parts.push('\u23F3 ' + limits);
    const parts2 = [];
    if (cwd) {
      const segs = cwd.replace(/\\\\/g, '/').split('/');
      parts2.push('\u{1F4C2} ' + segs[segs.length - 1]);
    }
    if (branch) parts2.push(' ' + branch);

    if (added || removed) parts2.push('\u{1F4DD} +' + added + '/-' + removed);
    if (turnLabel) parts2.push(turnLabel);

    process.stdout.write(parts.join(' ') + (parts2.length ? '\n' + parts2.join(' ') : ''));
  } catch { process.stdout.write(''); }
});
"
