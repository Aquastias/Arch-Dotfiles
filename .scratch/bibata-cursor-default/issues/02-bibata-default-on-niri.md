# 02 — Bibata Modern Ice default on niri

**What to build:** a fresh niri box uses Bibata Modern Ice as its cursor. The
niri adapter installs `bibata-cursor-git` (via its `aur` list) and the seeded
niri config carries the Bibata cursor theme in the compositor's native cursor
config node at size 24, with the standard default-icon path seeded for
GTK/XWayland apps.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `bibata-cursor-git` is declared in the niri adapter's `aur` list and lands
      via the paru pass when niri is selected.
- [x] The seeded niri config sets the Xcursor theme to `Bibata-Modern-Ice` at
      size 24 via the native cursor node.
- [x] `~/.icons/default` is seeded to inherit `Bibata-Modern-Ice`.
- [x] `niri-adapter.bats` asserts the cursor node and the aur declaration.

## Comments

- 2026-09-27 audit: 7598539, b436f92 (install-niri.jsonc aur, niri
  environment.kdl xcursor node, noctalia-preset.sh ~/.icons/default;
  niri-adapter.bats).
