# Claude Code Status Line

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows useful session info at a glance.

Requires a [Nerd Font](https://www.nerdfonts.com/) for some icons.

## Screenshot

```
Opus5(high) 📊 72%(56.0k/200k) 💲2.18(+0.12) 󰪰 99%(+1.2k) 🔥10:42→11:42(~$0.85)
📂 current_dir  main*↑2 +120/-35 ⏳5h 42% 7d 18%
```

## What it shows

| Icon | Metric | Description |
|------|--------|-------------|
| | Model | Model name, version and reasoning effort (e.g. `Opus5(high)`, `Opus4.6(high)`) |
| 📊 | Context | Remaining %, used/total tokens. Red below 20% |
| 💲 | Cost | Total session cost in USD, and how much it rose at the last change (`+0.12`). The previous total is kept per session in a small file in the OS temp directory, since the status line payload only carries the running total |
| 󰪰 | Cache | Prompt cache hit ratio of the last request, and tokens written to the cache by it (`+12.7k`) |
| 🔥/❄️ | Cache TTL | Time of the last API response → when its prompt cache expires. 🔥 while still hot, ❄️ (red) once expired. `(5m)` is appended when the last request only wrote to the 5-minute cache. `(~$0.85)` is the estimated cost of the first request after expiry, which has to rewrite the whole cache |
| 📂 | Folder | Current working directory name (second line) |
|  | Branch | Current git branch. `*` when there are uncommitted changes, `↑2`/`↓1` for commits ahead of/behind upstream |
| | Lines | Lines added/removed in this session (`+120/-35`), shown once non-zero |
| ⏳ | Plan limits | Usage of the 5-hour and weekly plan limits. Red at 80% or more. Shown only when Claude Code reports them (subscription plans) |

## Setup

1. Copy `statusline-command.sh` to `~/.claude/`:

   ```bash
   cp statusline-command.sh ~/.claude/statusline-command.sh
   chmod +x ~/.claude/statusline-command.sh
   ```

2. Add to `~/.claude/settings.json`:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash ~/.claude/statusline-command.sh"
     }
   }
   ```

3. Restart Claude Code.

## Requirements

- [Node.js](https://nodejs.org/) (used to parse the JSON data from stdin)
- [Nerd Font](https://www.nerdfonts.com/) in your terminal for  and 󰪰 icons
- Git (for branch detection)

## How the cache TTL label works

The status line only re-renders when the conversation updates, so an elapsed-time counter would freeze while you are idle. Instead the label shows absolute clock times: the timestamp of the last `assistant` entry in the session transcript (`transcript_path` from the status line payload) and that time plus the cache TTL. The TTL is taken from the last response's `usage.cache_creation`: 1 hour normally, 5 minutes if the request only wrote to the 5-minute cache. Reading it at a glance tells you whether resuming now will hit the cache (cheap) or rewrite the whole context (expensive), and when to run `/compact` before stepping away.

## How the resume cost is estimated

Claude Code reports `prompt_cache.recache_tokens_if_cold` (how many tokens the next request would have to write to the cache if it has expired) and `prompt_cache.ttl`. The estimate is those tokens times the model's cache-write price: the input price ×2 for the 1-hour TTL, ×1.25 for the 5-minute TTL. Input prices are hard-coded per model family in the script (Fable $10, Opus 5.5 $4, Opus 4.5–5 $5, Sonnet 5 $2, Sonnet 4.x $3, Haiku 4.5 $1 per million tokens); unknown models show no estimate. It is shown while the cache is still hot too, since the status line doesn't re-render while you are idle: read it as "what it costs to come back after the expiry time".

## License

MIT
