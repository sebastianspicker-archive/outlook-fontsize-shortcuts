# Outlook Modes

`outlook-fontsize-shortcuts` drives two Outlook UI variants through one runtime.

## `auto`

This is the default mode. The script first tries the `Settings...` menu used by New Outlook, then falls back to the `Preferences...` menu used by Legacy Outlook.

Use it unless Outlook consistently exposes only one UI on your Mac.

## `new`

Forces the New Outlook path:

- opens `Outlook -> Settings...`
- selects the `General` tile
- waits for the `Text display size` controls
- clicks the larger or smaller button

Use it when you want predictable behavior and know that Outlook runs as New Outlook.

## `legacy`

Forces the Legacy Outlook path:

- opens `Outlook -> Preferences...`
- finds the font-size slider via Accessibility APIs
- moves the slider one step toward smaller or larger text

Use it to skip autodetection, or when Outlook exposes only the legacy Preferences window.

## What happens on each shortcut

1. If a Settings or Preferences window is already open, it is reused in every mode. The window is recognized by its slider, its settings header or the text-size label. Otherwise the menu for the configured mode is opened.
2. The text size changes by one step, then the window is closed with `closeWindowKeystroke` (default `cmd+w`). The keystroke is only sent once a settings window was found, so it never closes a mail window.
3. In New Outlook, the `General` tile is found next to the settings header, or by its label (`generalLabels`). If neither can be pressed and the text-size controls are not already visible, the attempt fails.
4. Failures before the size actually changes are retried up to `retry.attempts` times. These include a menu that didn't open, a missing slider, General tile or buttons, and a click that Outlook rejected. Once the size has changed, or a click ended in an accessibility error that may have landed anyway, nothing is retried, so a shortcut never changes the size twice.
5. Waiting longer than `delays.timeout` for the window or the General pane ends the attempt without retrying.

The legacy-only runtime that navigated with arrow keys (`right_arrow_count`) was replaced by this single Accessibility-driven runtime; see [migration-from-legacy.md](migration-from-legacy.md).
