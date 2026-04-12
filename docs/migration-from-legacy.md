# Migration From `outlook-legacy-fontsize-shortcuts`

If you used the legacy-only repo before, move to this repo as follows.

## Files

Old setup:

- `init.lua`
- `outlook_legacy_fontsize.lua`

New setup:

- `init.lua`
- `outlook-font.lua`
- `outlook_font/`
- optional `outlook-font.json`

## Config mapping

Legacy-only config:

- `right_arrow_count`
- `delays_us`
- `timeout_seconds`
- `hotkeys.*.position`

Combined repo config:

- `mode = "legacy"` if you want to force Legacy Outlook
- `delays.timeout`, `delays.waitInterval`, `delays.activate`
- `retry.attempts`, `retry.interval`
- `hotkeys.increase`, `hotkeys.decrease`, `hotkeys.toggle`

## What changed

- You no longer need `right_arrow_count`. The combined runtime finds the legacy slider directly through Accessibility APIs instead of navigating tabs with arrow keys.
- You no longer set slider positions directly. `increase` and `decrease` move one step at a time.
- You can keep `mode = "auto"` if you switch between New Outlook and Legacy Outlook.

## Example `outlook-font.json`

```jsonc
{
  "mode": "legacy",
  "delays": {
    "timeout": 5
  },
  "hotkeys": {
    "increase": { "mods": ["ctrl", "alt", "cmd"], "key": "g" },
    "decrease": { "mods": ["ctrl", "alt", "cmd"], "key": "k" },
    "toggle": { "mods": ["ctrl", "alt", "cmd"], "key": "t" }
  }
}
```
