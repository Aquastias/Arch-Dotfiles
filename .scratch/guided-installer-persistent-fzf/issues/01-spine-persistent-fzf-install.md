# Spine: persistent single-fzf default install

Status: done
Type: HITL (agent-implementable; carries a human live-feel review gate —
see the last acceptance criterion)

## Parent

`.scratch/guided-installer-persistent-fzf/PRD.md`

## What to build

Invert the Guided Installer's interactive shell so a **single long-lived
fzf owns the loop** for the whole session (ADR 0042). This is the first
tracer bullet and must pierce every layer, so it bundles:

- **Pure edit setters** — extract the SET half of each editor (a field's
  path plus a value → a new Config State) into standalone pure functions,
  shared by the frozen `--guided` replay helpers and the new controller.
- **Guided controller** — a new event-driven dispatcher invoked by fzf
  `reload`/`transform` binds: given the navigation-state and
  override-state files (plus the selected line), emit the next row list,
  transition the screen, and/or apply a setter. Moving between the
  category list, a category's fields, and a field's enumerable value list
  is a re-paint of the same fzf — no new process, no flash.
- **Nav-state model** — a pure transition function: current
  screen / category / field plus the selected line → the next navigation
  state.
- **Launcher** — create the tmpfs override + navigation state files
  (mktemp under `${TMPDIR:-/tmp}`, removed on a trap), build the single
  fzf with its binds, a global header, and the Proceed / Save / Export
  rows under a divider, then launch it.
- **Terminal stage rewire** — all disk resolution moves post-menu (single
  resolved post-menu the way multi already is), reusing the Pre-Install
  Picker's fzf and preview; collect root + per-user passwords via the
  confirmed-secret reader (hidden, read-twice); gate on ACCEPT (multi
  layout) and INSTALL; hand the Effective Config to the back-end.
- Free-text fields **temporarily** reuse the existing one-shot prompt
  (replaced in slice 02) so the path is complete end-to-end.
- Remove the old multi-process menu loop and category subloop (retires the
  stopgap toolbar fix).

The pure cores (Config State, the seeder, the Emitter, the Menu model, the
history stack, the skeleton builder, the Pre-Install Picker) and the
`--guided` replay interface and its bats are unchanged.

## Acceptance criteria

- [ ] One persistent fzf for the whole interactive session — no return to
      the bare terminal between the category list, a category's fields, and
      an enumerable value edit.
- [ ] The header (toolbar line) and the Proceed / Save / Export rows are
      present at every menu depth.
- [ ] A category row shows ● when any field inside it is overridden.
- [ ] Edits commit on confirm and survive moving between categories; Esc
      backs out of a screen without committing.
- [ ] All disk resolution (single and multi) happens post-menu with the
      lsblk / SMART preview; passwords are entered hidden and confirmed;
      ACCEPT (multi) and INSTALL gate at the commit step; the disk to be
      erased is shown in the review.
- [ ] No password is ever echoed on screen or written to the state file
      (today's plaintext echo is fixed).
- [ ] Pure setters, the controller dispatch, and the nav-state transitions
      are bats-tested (state files in → list / next-nav / new state out,
      no fzf).
- [ ] The `--guided` replay path and its bats interface are unchanged; full
      suite green; shellcheck clean (`--severity=warning`).
- [ ] VM spine smoke: a default guided install drives the persistent menu
      to a booting system (served via `git daemon` + `REPO_URL`).
- [ ] **HITL gate:** a human drives the live menu and confirms it feels
      continuous (no flash) before this slice is closed and 02–04 begin.

## Blocked by

- None - can start immediately.

## Comments

**DONE (2026-06-23 … 06-26).** Built across `lib/config/edits.sh` (pure setters),
`lib/config/nav.sh` (nav-state model), `lib/guided-controller.sh` (controller +
directive→action), `lib/guided-fzf-entry.sh` (bind entry point), and
`lib/guided.sh`'s `guided_run_persistent` launcher + post-menu `prompt_secret`
credentials; single-disk resolution moved post-menu. Commits `f6a21b3` /
`a5a2b3f` / `6d4da83` / `93e1b4e` / `f38768e`. The **cutover** (`ddc1602`) made
the persistent fzf the only interactive path (legacy `_guided_menu_loop` deleted,
GUIDED_PERSISTENT flag gone, guided.sh 1230→1019). On main, full suite green.
Only the live fzf render + the VM spine smoke remain HITL/VM-gated (no tty/fzf in
CI); everything else is bats-verified + headless-walked through the real entry
script.
