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

    // Cost
    const cost = d.cost?.total_cost_usd;

    // Cache hit ratio (+ tokens written to cache on the last turn)
    const u = d.context_window?.current_usage;
    const cacheRead = u?.cache_read_input_tokens || 0;
    const cacheCreate = u?.cache_creation_input_tokens || 0;
    const inputTok = u?.input_tokens || 0;
    const totalInput = inputTok + cacheRead + cacheCreate;
    const cacheRatio = totalInput > 0 ? Math.round((cacheRead / totalInput) * 100) : null;

    // Last API response time + cache expiry, from the transcript's last assistant entry.
    // TTL: 1h if the last turn wrote to the 1h cache (or wrote nothing), 5m if it only wrote to the 5m cache.
    let cacheLabel = '';
    try {
      const tp = d.transcript_path;
      if (tp && fs.existsSync(tp)) {
        const size = fs.statSync(tp).size;
        const len = Math.min(size, 512 * 1024);
        const fd = fs.openSync(tp, 'r');
        const buf = Buffer.alloc(len);
        fs.readSync(fd, buf, 0, len, size - len);
        fs.closeSync(fd);
        const lines = buf.toString().split('\n');
        for (let i = lines.length - 1; i >= 0; i--) {
          const line = lines[i];
          if (!line.includes('\"assistant\"')) continue;
          let e; try { e = JSON.parse(line); } catch { continue; }
          if (e.type !== 'assistant' || !e.timestamp) continue;
          const cc = e.message?.usage?.cache_creation;
          const only5m = cc && (cc.ephemeral_5m_input_tokens || 0) > 0 && (cc.ephemeral_1h_input_tokens || 0) === 0;
          const ttlMs = (only5m ? 5 : 60) * 60 * 1000;
          const last = new Date(e.timestamp).getTime();
          const expiry = last + ttlMs;
          const hot = Date.now() < expiry;
          cacheLabel = (hot ? '\u{1F525}' : '❄️') + hhmm(last) + '→' + hhmm(expiry) + (only5m ? '(5m)' : '');
          break;
        }
      }
    } catch {}

    // Git branch from project cwd
    let branch = '';
    const cwd = d.cwd || '';
    try {
      branch = execSync('git --no-optional-locks rev-parse --abbrev-ref HEAD', { cwd: cwd || undefined, encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).trim();
    } catch {}

    // Build status line (uses Nerd Font icons)
    const parts = [modelName];
    if (pct != null) parts.push('\u{1F4CA} ' + Math.floor(pct) + '%' + (ctxUsedLabel ? '(' + ctxUsedLabel + ')' : ''));
    if (cost != null) parts.push('\u{1F4B2}' + cost.toFixed(3).slice(0, -1));
    if (cacheRatio != null) parts.push('\u{F0AB0} ' + cacheRatio + '%' + (cacheCreate ? '(+' + fmtK(cacheCreate) + ')' : ''));
    if (cacheLabel) parts.push(cacheLabel);
    if (cwd) {
      const segs = cwd.replace(/\\\\/g, '/').split('/');
      parts.push('\u{1F4C2} ' + segs[segs.length - 1]);
    }
    if (branch) parts.push(' ' + branch);

    process.stdout.write(parts.join(' '));
  } catch { process.stdout.write(''); }
});
"
