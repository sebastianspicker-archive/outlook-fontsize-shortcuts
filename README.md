# outlook-fontsize-shortcuts

Keyboard shortcuts for changing text display size in Outlook for Mac, with support for both New and Legacy Outlook via Hammerspoon.

| Shortcut | Action |
|----------|--------|
| `Ctrl+Alt+Cmd+G` | Increase text size |
| `Ctrl+Alt+Cmd+K` | Decrease text size |
| `Ctrl+Alt+Cmd+T` | Toggle between increase and decrease |

Use it to avoid digging through Outlook settings every time you want larger or smaller interface text.

## Supported Outlook modes

- `auto`: default; tries New Outlook first, then falls back to Legacy Outlook
- `new`: forces the `Outlook -> Settings...` path
- `legacy`: forces the `Outlook -> Preferences...` path

More on the behavior of each mode: [docs/modes.md](docs/modes.md)

## Prerequisites

- macOS
- Outlook for Mac installed and signed in
- [Hammerspoon](https://www.hammerspoon.org/)
- Accessibility permission for Hammerspoon in `System Settings -> Privacy & Security -> Accessibility`

Install Hammerspoon with Homebrew if needed:

```bash
brew install hammerspoon
```

## Install

```bash
git clone https://github.com/<owner>/outlook-fontsize-shortcuts.git
cd outlook-fontsize-shortcuts
cp init.lua outlook-font.lua ~/.hammerspoon/
cp -R outlook_font ~/.hammerspoon/
cp outlook-font.json ~/.hammerspoon/outlook-font.json
```

If you already have `~/.hammerspoon/init.lua`, merge this repo's `init.lua` changes instead of overwriting the file.

Reload Hammerspoon with `Ctrl+Alt+Cmd+R` or from its menubar icon.

## Usage

Default shortcuts:

- `Ctrl+Alt+Cmd+G`: increase text size
- `Ctrl+Alt+Cmd+K`: decrease text size
- `Ctrl+Alt+Cmd+T`: toggle between increase and decrease

You can also use the Hammerspoon menubar item for mouse-driven control.

## Configuration

Edit `~/.hammerspoon/outlook-font.json` if you want to override defaults.

```jsonc
{
  "mode": "auto",
  "delays": {
    "timeout": 3
  },
  "retry": {
    "attempts": 2,
    "interval": 0.2
  },
  "hotkeys": {
    "increase": { "mods": ["ctrl", "alt", "cmd"], "key": "g" },
    "decrease": { "mods": ["ctrl", "alt", "cmd"], "key": "k" },
    "toggle": { "mods": ["ctrl", "alt", "cmd"], "key": "t" }
  }
}
```

If you are moving from an older legacy-only setup, see [docs/migration-from-legacy.md](docs/migration-from-legacy.md).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Hotkeys do nothing | Confirm Hammerspoon is running, then re-check Accessibility permissions and reload the config. |
| Timeout waiting for the Outlook window | Increase `delays.timeout` in `outlook-font.json`. |
| Wrong Outlook path is selected | Set `"mode": "new"` or `"mode": "legacy"` explicitly. |
| Legacy behavior used to rely on `right_arrow_count` | This repo no longer uses that setting; see the migration guide. |
| Buttons or slider are not found | Outlook's UI probably changed. Inspect it with Accessibility Inspector and adjust the selectors. |

## Development

```bash
make tools
make check
```

Individual commands:

- `make fmt-check`
- `make lint`
- `make test`

## Security

See [SECURITY.md](SECURITY.md).
