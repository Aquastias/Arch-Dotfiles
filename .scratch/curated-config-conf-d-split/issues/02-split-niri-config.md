# 02 — Split the niri config into `conf.d/`

**What to build:** `.config/niri/config.kdl` becomes a pure manifest — a header
comment plus ordered `include "conf.d/NAME.kdl"` lines — and every setting moves
into the seven parallel part-files under `.config/niri/conf.d/`: `environment`
(cursor + `environment{}`), `input`, `appearance` (`hotkey-overlay` + `layout`),
`autostart` (the two `spawn-at-startup`), `keybinds`, `media` (volume/brightness/
playerctl hardware keys), `rules` (the corner-radius `window-rule` — niri models
rounding as a rule). The split is a pure move: no binding, rule, env, spawn, or
look value changes, and the shared keybind vocabulary (ADR 0096) is untouched.
The niri staging in `chroot.sh` and the niri fixtures/asserts in the tests
follow the tree; a fresh niri box seeds and boots the split config identically
(ADR 0107). Hyprland is not touched here and keeps shipping its single file.

**Blocked by:** 01 — the seed must already tolerate a `conf.d/` tree.

**Status:** ready-for-agent

- [ ] `config.kdl` contains only a header comment and the ordered `include`
      lines (order: environment, input, appearance, autostart, keybinds, media,
      rules); no settings remain in it.
- [ ] The seven `conf.d/*.kdl` part-files carry the moved content verbatim, each
      with a compact header keeping the non-obvious *why* + its `(ADR NNNN)`
      anchor; the corner-radius rule lives in `rules.kdl`.
- [ ] `keybinds.kdl` and `media.kdl` each hold a `binds{}` block with disjoint
      keys, so niri's per-key include merge is lossless.
- [ ] `chroot.sh` stages `.config/niri/conf.d/` alongside `config.kdl`; the
      `noctalia_preset_install` call seeds the whole niri tree to skel.
- [ ] `niri-adapter.bats` fixtures/asserts and the niri content greps in
      `noctalia-stow.bats` re-point at the part-file that now holds each
      construct (autostart, cursor, binds); Hyprland asserts unchanged.
- [ ] `niri validate` passes on the manifest + includes as one config; a fresh
      niri box boots the curated look with no behavior change.
