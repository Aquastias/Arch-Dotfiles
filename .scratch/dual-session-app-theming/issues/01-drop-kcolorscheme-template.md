# 01 — Drop the `kcolorscheme` template so KDE keeps its `kdeglobals`

**What to build:** On a combined `kde` + compositor host, a Plasma session must
stay Breeze Dark even after the operator has used a niri/Hyprland session.
Today the [[Wayland Shell Companion]] (Noctalia) merges its colors into the same
`~/.config/kdeglobals` that Plasma reads, so a compositor login repaints the
Plasma session in Catppuccin. Stop that leak by dropping the `kcolorscheme`
template from Noctalia's shared configuration fleet-wide. GTK and plain-Qt apps
are unaffected (they never read `kdeglobals`); a KDE-native app under a
compositor keeps Noctalia's base palette via the `qt` template and loses only
`KColorScheme` accent tints. Anchored by ADR 0104 (amends ADR 0102).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] `kcolorscheme` is removed from the shared Noctalia `config.toml`
      `[theme.templates] builtin_ids`; `gtk3`/`gtk4`/`qt` remain.
- [x] Noctalia no longer writes or merges `~/.config/kdeglobals` (no standalone
      `.colors` file, no kdeglobals merge post-action fires).
- [x] The `noctalia-stow.bats` drift guard asserts `config.toml` does not list
      `kcolorscheme`, so the leak cannot silently return.
- [x] The existing config.toml drift guards (enabled-list mirrors the core
      plugin set; no compositor-specific slice) stay green.

## Comments

- Done in `faadbe3` (with tickets 02/03). `noctalia-stow.bats` green (24/24);
  `config.toml` no longer lists `kcolorscheme`.
