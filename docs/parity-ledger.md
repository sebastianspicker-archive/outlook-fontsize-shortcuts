# Parity Ledger

Source repos:

- `99_archived_outlook-for-mac-fontsize-shortcuts`
- `99_archived_outlook-legacy-fontsize-shortcuts`

Canonical base:

- `99_archived_outlook-for-mac-fontsize-shortcuts`

Imported from legacy-only repo:

- `SECURITY.md` policy surface
- simpler migration guidance for legacy users
- explicit documentation of the old `right_arrow_count` model
- extra tests for forced `new` and `legacy` mode selection

Intentionally not imported:

- `outlook_legacy_fontsize.lua` as a second runtime module
- legacy-only `init.lua` instructions
- separate hotkey position model

Reason:

The newer repo already contains the stronger runtime and broader test surface. Keeping one module is the simplest way to reduce repo count without maintaining parallel automation paths.
