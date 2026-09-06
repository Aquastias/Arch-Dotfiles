# 05 — Stock compositor adapters

**What to build:** With `environment.stock` on, a niri or Hyprland install is a
bare compositor + session with nothing seeded — no Noctalia [[Wayland Shell
Companion]], no seeded configs or keybinds. `stock` forces the existing
`wayland_shell: none` path (ADR 0097). (ADR 0112, compositor half.)

**Blocked by:** 03 (`environment.stock` foundation — the env var this reads).

**Status:** ready-for-agent

- [ ] The niri and Hyprland adapters read `ENVIRONMENT_STOCK`; when set, they
      install the compositor + session file only and seed nothing (the
      `wayland_shell: none` behaviour), regardless of the resolved
      `wayland_shell` value.
- [ ] When `ENVIRONMENT_STOCK` is unset/false, behaviour is the full
      Noctalia-seeded install (no regression), including the Meta+X keybind from
      ticket 01.
- [ ] Compositor seed-root tests (`NIRI_SEED_ROOT`/`HYPR_SEED_ROOT`) assert that
      under stock nothing is seeded into skel.
