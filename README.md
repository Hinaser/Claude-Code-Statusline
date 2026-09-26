# Claude Code Status Line

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows useful session info at a glance.

Requires a [Nerd Font](https://www.nerdfonts.com/) for some icons.

## Screenshot

```
Opus5(high) 📊 72%(56.0k/200k) 💲2.18(+0.12) 󰪰 99%(+1.2k) 🔥10:42→11:42 📂 current_dir  main
```

## What it shows

| Icon | Metric | Description |
|------|--------|-------------|
| | Model | Model name, version and reasoning effort (e.g. `Opus5(high)`, `Opus4.6(high)`) |
| 📊 | Context | Remaining %, used/total tokens |
| 💲 | Cost | Total session cost in USD, and how much it rose at the last change (`+0.12`). The previous total is kept per session in a small file in the OS temp directory, since the status line payload only carries the running total |
| 󰪰 | Cache | Prompt cache hit ratio of the last request, and tokens written to the cache by it (`+12.7k`) |
| 🔥/❄️ | Cache TTL | Time of the last API response → when its prompt cache expires. 🔥 while still hot, ❄️ once expired. `(5m)` is appended when the last request only wrote to the 5-minute cache |
| 📂 | Folder | Current working directory name |
|  | Branch | Current git branch |

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

## License

MIT
