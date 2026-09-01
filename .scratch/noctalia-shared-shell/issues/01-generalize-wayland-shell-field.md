# 01 — Generalize `niri_shell` → `wayland_shell`

**What to build:** the shell selector becomes compositor-agnostic. Rename the
`environment.niri_shell` field to `environment.wayland_shell` everywhere it is
declared, validated, defaulted, menued, seeded, and threaded to the adapters, so
it is honored for **both** niri and Hyprland when present in the desktop set
(KDE ignores it). Values and default are unchanged (`noctalia` | `none`, default
`noctalia`). After this ticket niri behaves exactly as before; Hyprland does not
consume the field yet. This is a prefactor — it must land green with no
behavioural change.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] The config loader validates `wayland_shell` (`noctalia`/`none`, default
      `noctalia`) and rejects unknown values.
- [ ] The resolved value is exported to both the niri and Hyprland adapters
      (Hyprland receives it even though it does not act on it yet).
- [ ] The Guided menu row, its enum, the seed default, and the Host Profile
      schema key list all use `wayland_shell`.
- [ ] The install-matrix pairwise axis is renamed to `wayland_shell`.
- [ ] The VM seed generator emits `wayland_shell`.
- [ ] `environment-validation.bats`, `environment-resolution.bats`,
      `menu-enum.bats`, and `matrix-registry.bats` pass against the new name; no
      reference to `niri_shell` remains.
- [ ] niri install behaviour is unchanged (existing niri-adapter tests green).
