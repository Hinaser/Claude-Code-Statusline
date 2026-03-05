#!/usr/bin/env bash
cat | node -e "
const { execSync } = require('child_process');
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
    const fmtDur = ms => {
      if (!ms) return null;
      const s = Math.floor(ms / 1000);
      if (s < 60) return s + 's';
      const m = Math.floor(s / 60);
      const rs = s % 60;
      return m + 'm' + (rs ? rs + 's' : '');
    };

    // Model: 'claude-opus-4-6' -> 'Opus 4.6'
    const mid = d.model?.id || '';
    const modelName = (() => {
      const m = mid.match(/claude-(\w+)-(\d+)-(\d+)/);
      if (m) return m[1].charAt(0).toUpperCase() + m[1].slice(1) + ' ' + m[2] + '.' + m[3];
      return d.model?.display_name || 'Unknown';
    })();

    // Context remaining % with used/total
    const ctxSize = d.context_window?.context_window_size;
    const pct = d.context_window?.remaining_percentage;
    const ctxUsedLabel = ctxSize && pct != null
      ? fmtK(ctxSize - Math.round(ctxSize * pct / 100)) + '/' + fmtK(ctxSize)
      : '';

    // Cost
    const cost = d.cost?.total_cost_usd;

    // Lines changed
    const added = d.cost?.total_lines_added;
    const removed = d.cost?.total_lines_removed;

    // API duration
    const apiMs = d.cost?.total_api_duration_ms;

    // Cache hit ratio
    const u = d.context_window?.current_usage;
    const cacheRead = u?.cache_read_input_tokens || 0;
    const cacheCreate = u?.cache_creation_input_tokens || 0;
    const inputTok = u?.input_tokens || 0;
    const totalInput = inputTok + cacheRead + cacheCreate;
    const cacheRatio = totalInput > 0 ? Math.round((cacheRead / totalInput) * 100) : null;

    // Git branch from project cwd
    let branch = '';
    const cwd = d.cwd || '';
    try {
      branch = execSync('git rev-parse --abbrev-ref HEAD', { cwd: cwd || undefined, encoding: 'utf8', stdio: ['pipe','pipe','pipe'] }).trim();
    } catch {}

    // Build status line (uses Nerd Font icons)
    const parts = [modelName];
    if (pct != null) parts.push('\u{1F4CA} ' + Math.floor(pct) + '%' + (ctxUsedLabel ? '(' + ctxUsedLabel + ')' : ''));
    if (cost != null) parts.push('\u{1F4B2}' + cost.toFixed(3));
    if (added != null || removed != null) parts.push('\u0394 +' + (added || 0) + '/-' + (removed || 0));
    if (apiMs) parts.push('\uF017 ' + fmtDur(apiMs));
    if (cacheRatio != null) parts.push('\u{F0AB0} ' + cacheRatio + '%');
    if (cwd) {
      const segs = cwd.replace(/\\\\/g, '/').split('/');
      parts.push('\u{1F4C2} ' + segs[segs.length - 1]);
    }
    if (branch) parts.push('\uE0A0 ' + branch);

    process.stdout.write(parts.join(' '));
  } catch { process.stdout.write(''); }
});
"
