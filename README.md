# Claude Code Status Line

A custom status line for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that shows useful session info at a glance.

Requires a [Nerd Font](https://www.nerdfonts.com/) for some icons.

## Screenshot

```
Opus 4.6 📊 72%(56.0k/200k) 💲2.181 Δ +96/-30  3m39s 󰪰 99% 📂 current_dir  main
```

## What it shows

| Icon | Metric | Description |
|------|--------|-------------|
| | Model | Model name and version (e.g. `Opus 4.6`) |
| 📊 | Context | Remaining %, used/total tokens |
| 💲 | Cost | Total session cost in USD |
| Δ | Changes | Lines added/removed this session |
|  | Duration | Time spent waiting for API responses |
| 󰪰 | Cache | Prompt cache hit ratio (last request) |
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
- [Nerd Font](https://www.nerdfonts.com/) in your terminal for ,  and 󰪰 icons
- Git (for branch detection)

## License

MIT
