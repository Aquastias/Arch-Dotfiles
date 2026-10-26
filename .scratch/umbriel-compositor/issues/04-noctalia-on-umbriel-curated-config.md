# 04: Noctalia on Umbriel + curated config

**What to build:** With `wayland_shell: noctalia`, an Umbriel login looks and
behaves like the operator's niri/Hyprland sessions.
- The shared Noctalia preset runs for Umbriel, with an empty compositor
  plugin slice.
- A curated, single-source Umbriel config (`config.toml` + `conf.d/` parts:
  look, input, autostart `noctalia`) is seeded into `/etc/skel` and
  stowable from the repo.
- It includes the Bibata Modern Ice cursor, colours through Noctalia's
  existing `umbriel` template, click-to-focus, the clipboard keep-alive and
  xdg user dirs.
- No output config, since resolution is autodetected.
- Seeding must work even though Umbriel's packages land in the later AUR
  pass.
- Umbriel joins `arch-audit`.

Binds are NOT this ticket (05). Keep upstream's bind section out or minimal.

**Blocked by:** 03

**Status:** done

- [x] Adapter bats: curated config seeded under noctalia, nothing under
      `none`/stock
- [x] Stow bats cover the Umbriel config
- [x] `umbriel config validate` accepts the shipped config
- [x] VM Audit Run of `arch-audit`: Umbriel session passes Noctalia, Qt
      theming, xdg dirs, clipboard and portal checks

Spec: ../PRD.md · ADR 0094, 0095, 0097, 0107, 0159
