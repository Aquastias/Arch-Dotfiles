# Dolphin is seeded without the embedded Terminal panel

---
Status: accepted. Extends ADR 0111 (KDE adapter seeds captured Plasma state) and
ADR 0088 (adapter seeds first-run defaults). The operator wants no embedded
Terminal panel in Dolphin — "open folder in terminal" (the action) is enough.
Verified on the `arch-combined` VM.
---

This Dolphin build shows the **Terminal panel by default**: a freshly-launched
Dolphin with no saved state writes a `dolphinstaterc` whose `terminalDock` is
**visible** (VM-verified — removing the state file and relaunching still shows
the panel). That is unusual for upstream Dolphin, but it is the behaviour here.

Panel visibility has **no KConfig key** — not in `dolphinrc` nor any
`config.kcfg/dolphin_*` (only `LockPanels`, `ConfirmClosingTerminalRunningProgram`,
`ConfirmOpenManyTerminals` exist). It lives **only** in the base64 QMainWindow
state (`[State] State=`) in `~/.local/state/dolphinstaterc`, and the
show/hide toggle is a `QDockWidget::toggleViewAction()` that is **not** exported
to the KActionCollection D-Bus interface (only `focus_terminal_panel`,
`open_terminal`, `open_terminal_here`, `lock_panels` are). So there is no config
or D-Bus lever — the state blob is the only control surface.

## Decision

**Seed a `dolphinstaterc` whose `terminalDock` is hidden.** The blob was captured
from Dolphin itself after toggling the panel off (F4) and quitting cleanly, so it
is a byte-valid QMainWindow state — the `terminalDock` flag reads `0x08` (hidden)
instead of `0x01` (shown). `kde.sh` seeds it to
`/etc/skel/.local/state/dolphinstaterc`. Only the **generic** `State=` is seeded
(no screen-size-keyed `"<WxH> screen:"` line, which is host-bound, ADR 0111), so
it applies at any resolution — Dolphin restores the hidden flag and adapts the
rest. VM-verified: a fresh Dolphin launches with the file view, Places and
Information panels, and **no** Terminal panel.

The **`open_terminal` / `open_terminal_here` actions are untouched** — opening a
folder in a terminal (Tools menu / right-click) still works; only the docked
panel is gone, exactly the operator's ask.

## Considered options

- **A KConfig / dolphinrc key** — does not exist for panel visibility (verified);
  the QMainWindow state is the only store.
- **Toggle at runtime and rely on the persisted state** — not fleet-deliverable:
  every fresh install would still default the panel on. Seeding the state is the
  installer-time fix.
- **Hand-craft the state blob** (flip the flag byte without capturing) — rejected
  as fragile; capturing Dolphin's own output guarantees a valid blob.
- **Remove konsolepart** (the panel's backend) — rejected: konsole is a wanted
  KDE app and the panel is opt-out, not opt-in here.

## Consequences

- **Fresh KDE installs get Dolphin with no Terminal panel**; the terminal-opening
  actions remain. Applies wherever Dolphin ships (the KDE adapter).
- One vendored QMainWindow state blob in `kde.sh`. If a future Qt/Dolphin release
  changes the state format and rejects the blob, Dolphin silently reverts to its
  default (panel back on) — a harmless, self-evident regression, not a breakage.
- Seeding into `~/.local/state` (not `.config`) — precedented by ADR 0121/0109
  (noctalia state). Guarded by `kde-adapter.bats`.
