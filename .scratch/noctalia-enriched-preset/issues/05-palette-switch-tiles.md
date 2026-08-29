# 05 — Palette-cycle control-center tile

**What to build:** A one-click affordance that cycles between the five built-in
palettes (Rosé Pine, Catppuccin, Tokyo-Night, Gruvbox, Nord). `custom-shortcut`
is a v5 singleton whose settings seed declaratively via `[plugin_settings]`, so
the adapter seeds ONE tile ("Cycle palette") wired to a seeded script that walks
the palettes over `qs -c noctalia-shell ipc call colorScheme set <Name>`.
Palette switching itself is built-in theming — no `config-swap`.

Note (implementation finding): `custom-shortcut` cannot host five direct-select
tiles (singleton, one instance per id), and `control_center.shortcuts` is not
seeded because that array would replace the built-in Control Center defaults —
so placing the "Cycle palette" tile in the CC is a one-time user step.

**Blocked by:** 02, 03 (needs the seeded palette default and the
`custom-shortcut` plugin installed).

**Status:** ready-for-agent

- [ ] A seeded script cycles the five palettes via `colorScheme set`.
- [ ] The `custom-shortcut` tile is pre-wired to it via `[plugin_settings]`,
      only when `custom-shortcut` is enabled.
- [ ] The built-in `control_center.shortcuts` defaults are left untouched.
- [ ] No `config-swap` plugin is involved.
- [ ] `niri-adapter.bats` asserts the cycler + tile settings on, and absent off.
