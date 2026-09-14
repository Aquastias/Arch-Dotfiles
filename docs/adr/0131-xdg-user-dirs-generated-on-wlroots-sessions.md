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

Run the update from the **compositor autostart**, where the gap is — beside
`noctalia --daemon` and the Live Theme Bridge (ADR 0107 `conf.d/autostart.*`):

- **niri** — a `spawn-at-startup` in `conf.d/autostart.kdl`.
- **Hyprland** — an `exec` in `conf.d/autostart.lua`.

Both run `xdg-user-dirs-update` (creates the well-known set from `user-dirs.dirs`)
then `mkdir -p "$HOME/Projects"`. The preset seeds `/etc/skel/.config/
user-dirs.dirs` with the **full standard set** in explicit English paths (so the
names are deterministic, not locale-derived) plus a **non-standard
`XDG_PROJECTS_DIR="$HOME/Projects"`** line, so tools that resolve XDG user dirs
can find Projects. `xdg-user-dirs-update` manages only the well-known set, so the
folder itself is created by the explicit `mkdir` — `XDG_PROJECTS_DIR` is
declarative only.

Scope is **compositor-only**: KDE already creates the folders via
`/etc/xdg/autostart/`, so re-running under Plasma is unnecessary; the autostart is
launched only from the compositor sessions (ADR 0107).

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
- New preset surface: two autostart lines (one per compositor) and a seeded
  `user-dirs.dirs`, guarded by the preset's bats suite.
