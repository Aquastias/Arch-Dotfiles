# 02 — Desktop-aware `auto` display manager (ADR 0091)

**What to build:** As the operator, when I leave `environment.display_manager` at
`auto`, the installer picks the greeter that matches my session family: greetd +
tuigreet for a KDE-free non-empty desktop set (Hyprland and/or niri), SDDM when
the set contains KDE, and none when there is no desktop. It stays a smart default
I can always override — never a hard lock. This supersedes the shipped
fleet-wide-`auto`→SDDM behaviour and closes the drift against ADR 0069's stated
intent, extending it to niri. It also changes existing KDE-free Hyprland profiles
that omit the key (greetd instead of SDDM).

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `auto` resolves to `greetd` for a KDE-free non-empty desktop set (Hyprland
      and/or niri), `sddm` when the set contains `kde`, `none` when empty.
- [ ] Explicit `greetd`/`sddm` still pass through unchanged; the DM remains an
      overridable operator choice (no menu lock).
- [ ] The rule lives in both the config-load resolution and the Package Resolver
      and is asserted **identical** in each — a change to one that misses the
      other is caught (prior art: the existing DM `auto` and GPU `auto` cases).
- [ ] The resolver's display-manager derived set reports the greeter matching the
      desktop-aware `auto` result.
