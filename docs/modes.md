# Outlook Modes

`outlook-fontsize-shortcuts` supports two Outlook UI variants through one runtime module.

## `auto`

Default mode. The script first tries the `Settings...` menu used by New Outlook, then falls back to the `Preferences...` menu used by Legacy Outlook.

Use this unless Outlook consistently exposes only one UI on your Mac.

## `new`

Forces the New Outlook path:

- opens `Outlook -> Settings...`
- selects the `General` tile
- looks for the `Text display size` controls
- clicks the larger or smaller button

Use this when you want predictable behavior and already know that Outlook is running in New Outlook mode.

## `legacy`

Forces the Legacy Outlook path:

- opens `Outlook -> Preferences...`
- finds the font-size slider via Accessibility APIs
- moves the slider by one step toward smaller or larger text

Use this when you want to skip autodetection or when Outlook exposes only the legacy Preferences window.

## Why there is no second legacy runtime

The old `outlook_legacy_fontsize.lua` implementation relied on keypress navigation and `right_arrow_count` tuning. The combined repo keeps a single AX-driven runtime instead:

- less duplicated code
- one install path
- one test surface
- no need to maintain two independent Hammerspoon modules
