# XDG user dirs generated on wl-roots sessions (incl. Projects)

---
Status: accepted. Extends the [[Wayland Shell Companion]] preset (ADR 0090/0107).
---

`~/Desktop`, `~/Downloads`, `~/Documents`, … appear under KDE but **not** under
niri/Hyprland. Root cause: `xdg-user-dirs` **is** installed fleet-wide (confirmed
in both niri and KDE VM logs), but the folders are created by
`xdg-user-dirs-update`, which ships only as an **XDG autostart**
(`/etc/xdg/autostart/xdg-user-dirs.desktop`). Plasma processes `/etc/xdg/
autostart/`; niri and Hyprland do **not** (they run only their own
`spawn-at-startup`/`exec`), so the update never runs and no folders materialise.
The gap is a **missing invocation**, not a missing package. We also want a
non-standard **`Projects`** folder.

## Decision

Ship a small seeded script `~/.local/bin/noctalia-xdg-user-dirs` and call it from
the **compositor autostart**, where the gap is — beside `noctalia --daemon` and
the Live Theme Bridge (ADR 0107 `conf.d/autostart.*`):

- **niri** — a `spawn-at-startup` in `conf.d/autostart.kdl`.
- **Hyprland** — an `exec_cmd` in `conf.d/autostart.lua`.

The script runs `xdg-user-dirs-update` — which, for a user with no
`~/.config/user-dirs.dirs` yet, reads the stock English `/etc/xdg/
user-dirs.defaults` and creates the **full standard set** — then `mkdir -p
"$HOME/Projects"` and appends a **non-standard `XDG_PROJECTS_DIR="$HOME/Projects"`**
line to the generated `user-dirs.dirs` (update manages only the well-known set, so
Projects is created and declared explicitly). It is a **stowed dotfile** and rides
the [[Wayland Shell Companion]] preset's existing `.local/bin/noctalia-*` skel
seed, so no new seed leg is needed.

Because it runs **at login as the user**, it reaches **existing and new users
alike** — no per-`$HOME` seed is required (the preset is skel-only, ADR 0095) and
`/etc/skel` timing relative to user creation is irrelevant. Idempotent: safe on
every login. Scope is **compositor-only**: KDE already creates the folders via
`/etc/xdg/autostart/`, and the script is launched only from the compositor
sessions (ADR 0107).

## Considered options

- **A systemd-user unit** running the update session-agnostically — rejected: it
  would not reliably reach Hyprland (`start-hyprland`, not the uwsm/systemd
  session — ADR 0070), the same reason the theme bridge is compositor-autostarted
  (ADR 0116).
- **Symlink `xdg-user-dirs.desktop` into the compositor autostart dir** — rejected:
  niri/Hyprland don't consume `/etc/xdg/autostart/` at all, so there is no such
  dir to populate; a native `spawn-at-startup`/`exec` is the idiom.
- **Model `Projects` as a well-known XDG dir** — impossible: `xdg-user-dirs` only
  manages the fixed freedesktop set; a custom `XDG_PROJECTS_DIR` + explicit
  `mkdir` is the honest representation.

## Consequences

- niri/Hyprland sessions get the standard XDG folders and `~/Projects` on login,
  idempotently (the update and `mkdir -p` are no-ops once created).
- New surface: one stowed `noctalia-xdg-user-dirs` script (riding the preset's
  `.local/bin/noctalia-*` skel seed) and two autostart lines (one per
  compositor), guarded by `noctalia-stow.bats`.
- Standard dir names follow the session locale (stock `xdg-user-dirs-update`
  behavior); on this English fleet they are the English set. Deterministic
  English names regardless of locale would need a seeded `user-dirs.dirs` — not
  done, as the fleet is English.
