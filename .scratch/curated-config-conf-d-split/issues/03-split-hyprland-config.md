# 03 — Split the Hyprland config into `conf.d/`

**What to build:** `.config/hypr/hyprland.lua` becomes a pure manifest — a header
comment plus ordered `require("conf.d.NAME")` lines — and every setting moves
into the seven parallel part-files under `.config/hypr/conf.d/`: `environment`
(`hl.monitor` folded here + `hl.env` cursor/qt), `input`, `appearance`
(`general/decoration/animations/dwindle/master/misc` `hl.config` + `hl.curve` +
`hl.animation`; rounding stays in `decoration`), `autostart` (the
`hl.on("hyprland.start", …)` hook), `keybinds` (with the
`terminal`/`fileManager`/`menu`/`lock`/`mainMod` locals declared at its top —
they are used nowhere else), `media` (XF86 volume/brightness/playerctl), `rules`
(the two `hl.window_rule`). Pure move: no bind, rule, env, or look value
changes, keybind parity with niri (ADR 0096) intact. The Hyprland staging in
`chroot.sh` and the Hyprland fixtures/asserts follow the tree (ADR 0107). niri
is not touched here.

**Blocked by:** 01 — the seed must already tolerate a `conf.d/` tree.
Independent of 02; may run in parallel.

**Status:** ready-for-agent

- [ ] `hyprland.lua` contains only a header comment and the ordered `require`
      lines (order: environment, input, appearance, autostart, keybinds, media,
      rules); no settings remain in it.
- [ ] The seven `conf.d/*.lua` part-files carry the moved content verbatim, each
      with a compact `(ADR NNNN)`-anchored header; each file is self-contained
      (separate Lua scope), with the keybind locals confined to `keybinds.lua`.
- [ ] The single `hl.monitor` line lives in `environment.lua`; rounding stays in
      `appearance.lua`'s `decoration` block.
- [ ] `chroot.sh` stages `.config/hypr/conf.d/` alongside `hyprland.lua`; the
      `noctalia_preset_install` call seeds the whole Hyprland tree to skel.
- [ ] `hyprland-adapter.bats` fixtures/asserts and the Hyprland content greps in
      `noctalia-stow.bats` re-point at the part-file now holding each construct
      (autostart, cursor, IPC launcher/lock binds); niri asserts unchanged.
- [ ] `Hyprland --verify-config -c hyprland.lua` passes on the manifest +
      requires as one config; a fresh Hyprland box boots identically.
