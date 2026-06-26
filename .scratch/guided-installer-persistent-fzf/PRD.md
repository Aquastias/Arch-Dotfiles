# Guided Installer — persistent single-fzf controller (no flash)

Status: done — all 4 slices built + merged to main + cutover complete (ddc1602);
full suite green. Only the live fzf render + a VM spine smoke remain HITL/VM-gated.

Decision of record: **ADR 0042** (Guided Installer renders through one
persistent fzf, not one fzf per pick). Builds on ADR 0039 (Guided
Installer, profile-optional front-end), 0040 (Filesystem Adapter axis),
0041 (host Security/Backup via the Primary User's paru pass), 0036
(unified profile / Effective Config). The **Guided Installer** glossary
term's meaning is unchanged; one implementation-leaning sentence in
`CONTEXT.md` ("free-text fields … drop to a typed prompt") becomes
inaccurate once free-text moves to the query line and should be trimmed
when the rewrite lands.

Glossary: Guided Installer, Configuration Categories, Config State,
Effective Config, Pre-Install Picker, Host Core, Primary User, Security &
Backup Extras, Single Entry Point.

## Problem Statement

The Guided Installer works but does not feel like one program. Selecting
anything flickers back to the bare terminal for a moment before the menu
reappears, so the operator feels like they keep leaving and re-entering
the installer. And once they drill more than one level deep — into a
category's fields — the toolbar (undo / redo / reset and the terminal
actions) disappears, stranding them without it. The surface reads as a
sequence of separate pickers rather than a single, continuous installer.

## Solution

The Guided Installer becomes **one persistent full-screen fzf** that stays
open for the whole session. Instead of spawning a fresh fzf for the top
menu, then another for a category, then another for each value edit, a
single long-lived fzf owns the loop and re-paints itself in place as the
operator navigates — into a category, into a field's value list, and back
out — with no return to the bare terminal between screens. Because there
is only one fzf, its header (the keybind toolbar) and the terminal-action
rows are present and live at every depth.

Free-text fields are typed directly into the menu's own input line and
captured in place, so even typing a hostname or a package name never
leaves the window. The genuinely sequential, deliberate steps — picking
the install disk(s), entering passwords, and the destructive
confirmations — happen once, after the menu closes, as a clean commit
stage rather than interrupting configuration.

fzf stays the only renderer: no new dependency and no compiled binary, so
the installer remains bash-only and dependency-free on the
archzfs-Compatible ISO.

## User Stories

1. As an operator, I want the menu to stay on screen between selections,
   so that I never see the bare terminal flash and never feel like I left
   the installer.
2. As an operator, I want to drill into a Configuration Category and back
   out without the screen tearing down and rebuilding, so that navigation
   feels continuous.
3. As an operator, I want to edit an enumerable field by picking from a
   list that appears in the same window, so that choosing a value doesn't
   relaunch a separate picker.
4. As an operator, I want to type a free-text value (hostname, swap/ESP
   sizes, package names, sysctl pairs, persist paths, URLs) without the
   menu disappearing, so that text entry feels part of the same surface.
5. As an operator, I want the toolbar (undo / redo / reset and the
   terminal actions) visible and working at every menu depth, so that I'm
   never stranded without it after drilling in.
6. As an operator, I want undo / redo / reset on keybindings reachable at
   any depth, so that editing history is always one keypress away.
7. As an operator, I want a category row to show a ● when I've changed
   something inside it, so that I can see what I've touched at a glance.
8. As an operator, I want my edits to commit on confirm and survive moving
   between categories, so that navigation never loses a value.
9. As an operator, I want Esc to back out of a screen without committing,
   so that I can cancel an in-progress edit safely.
10. As an operator, I want Proceed / Save / Export as clearly grouped rows
    under a divider, so that the terminal destinations stay distinct from
    the things I configure.
11. As an operator, I want to pick my install disk(s) at the commit step
    with the lsblk / SMART preview pane, so that I choose hardware
    deliberately and still see device details.
12. As an operator, I want my password entered hidden and confirmed, so
    that it never echoes on screen.
13. As an operator, I want passwords collected once at the end, just
    before install, so that the configuration phase stays seamless and
    secrets are handled in one place.
14. As an operator, I want the destructive confirmations (ACCEPT the disk
    layout, INSTALL) at the commit step, so that I confirm intent
    deliberately after configuring.
15. As an operator, I want the disk I'll erase shown in the review before
    INSTALL, so that I can confirm the target deliberately.
16. As an operator, I want a full default install to work through the new
    menu from the very first slice, so that the rewrite delivers a usable
    installer incrementally rather than in one big bang.
17. As a maintainer, I want fzf to remain the only renderer (no new
    dependency, no compiled binary), so that the installer stays bash-only
    and always runs on the ISO without fetching extra tools.
18. As a maintainer, I want the pure cores (Config State, the seeder, the
    Emitter, the Menu model, the history stack, the skeleton builder, the
    Pre-Install Picker) unchanged, so that their existing bats coverage
    still applies to what actually runs.
19. As a maintainer, I want the headless `--guided` replay path and its
    bats interface unchanged, so that the rewrite is interactive-rendering-
    only, not a rewrite of the tested cores.
20. As a maintainer, I want the SET half of each editor extracted into
    pure setters shared by the replay helpers and the controller, so that
    the path/value writes have one tested implementation.
21. As a maintainer, I want the controller's dispatch testable by feeding
    it state files (no fzf, no tty), so that the interactive logic is
    unit-tested without a live terminal.
22. As a maintainer, I want the interactive override map held in a tmpfs
    file created with mktemp and cleaned on a trap, so that fzf
    bind-children can share mutable state and nothing is left behind.
23. As a maintainer, I want all disk resolution to happen after the menu
    closes, so that the single-select persistent fzf needn't host a
    multi-select pick (fzf's multi-select is a launch-only flag).
24. As a maintainer, I want today's plaintext password echo fixed, so that
    secrets never appear on screen or in the state file.
25. As a maintainer, I want the stopgap toolbar fix retired by the
    rewrite, so that the throwaway category subloop is removed cleanly.

## Implementation Decisions

**Control inversion.** Today bash owns the loop and calls fzf (spawn,
exit, spawn). The rewrite inverts that: one long-lived fzf owns the loop
and calls a bash *controller* through `reload`/`transform` key binds.
Navigation between the category list, a category's fields, and a field's
value list is a re-paint of the same fzf instance, not a new process —
which removes the flash and keeps the header (toolbar) and terminal-action
rows global at every depth. The pure cores are untouched; the impure shell
flips inside-out.

**Module: pure edit setters.** The SET half of each `_guided_edit_*`
editor (a field's path plus a value → a new Config State) is extracted
into standalone pure functions, JSON-in/JSON-out. Both the frozen replay
helpers and the new controller call these, so the path/value writes have a
single implementation and a single set of tests.

**Module: guided controller.** A new event-driven dispatcher invoked by
fzf binds. Given the navigation-state file and the override-state file
(plus the typed query for a text field), it decides the next screen,
emits the next list of rows, and/or applies a setter. It is the heart of
the inversion and is unit-testable by calling it with state files and
asserting the emitted list and the resulting state — no fzf required.

**Module: nav-state model.** A small pure transition function: current
screen / category / field plus the selected line → the next navigation
state. Tracks "which screen am I on" so the controller can branch (browse
categories vs browse fields vs capture a text value). May be a standalone
module or folded into the controller; tested either way.

**Module: persistent-fzf launcher.** Thin glue that creates the tmpfs
state files (mktemp under `${TMPDIR:-/tmp}`, removed on a trap), builds the
single fzf invocation with all its binds and header, and launches it. This
is the only piece that draws the live UI.

**Module: terminal stage.** After the menu closes, a linear commit stage:
resolve all install disks (single and multi alike) reusing the existing
Pre-Install Picker fzf with its preview pane, prompt for root and per-user
passwords (hidden, confirmed), gate on ACCEPT (multi layout) and INSTALL,
then hand the Effective Config to the back-end. Single-disk resolution
moves out of the menu to here.

**Free-text entry.** Free-text fields are typed into fzf's own query/input
line; a `transform` bind captures the query into the override-state file
and re-paints back to the field list. Editing never leaves the window.

**Secrets and consent.** Passwords and the typed consent gates
(ACCEPT / INSTALL) are handled in the terminal stage via the shared
confirmed-secret reader (hidden, read-twice). Passwords never touch the
query line or the override-state file, and today's plaintext echo is
fixed.

**State.** The interactive override map lives in a tier-one transient
tmpfs file (the same tier as the assembled Effective Config — created with
mktemp under `${TMPDIR:-/tmp}`, not the secrets-only tmpfs mount), with a
sibling navigation-state file, both cleaned on a trap. A file is required
because fzf bind-children are subprocesses that can't read the parent
shell's variables.

**Disk resolution is post-menu.** fzf's multi-select is a launch-only flag
with no runtime toggle, so a single-select persistent instance cannot host
the multi-disk pick. All disk resolution therefore happens in the terminal
stage; the persistent menu is config-only and carries no preview plumbing.

**Replay seam frozen.** The `--guided <answers>` keyed replay path and its
bats interface are unchanged. Interactive and headless now share the pure
cores and the extracted setters — not control flow. The new controller is
event-driven with its own tests; the live fzf draw stays smoke-only.

**Renderer.** Stay on fzf. Compiled full-screen TUIs (ratatui / bubbletea)
were rejected: a binary in the audit repo (against ADR 0036), a language
boundary forcing the pure cores to be subprocess-bridged or duplicated,
and a rewritten replay/test seam — all for polish whose only true fzf
deficit (masked password entry) is already handled in the terminal stage.

## Testing Decisions

A good test asserts external behavior through a module's public interface —
state in, JSON or a decision out — not its internals. The new logic is
JSON-in/JSON-out and has no tty, so it is bats-tested directly; the only
untestable part is the live fzf draw, exercised via the guided VM smoke.

- **Pure edit setters** — bats: each setter maps (path, value, prior
  state) to the expected new Config State; an empty/absent value no-ops.
  Prior art: `tests/config/guided-state.bats`, `guided-emit.bats`.
- **Guided controller** — bats: feed a navigation-state file + an
  override-state file + a selected line (and a query for text fields) and
  assert the emitted row list, the next navigation state, and any committed
  state change. No fzf stub needed — cleaner than today's loop tests. Prior
  art (in spirit): `tests/config/guided-shell.bats` loop-dispatch tests.
- **Nav-state model** — bats: each (current nav, selected line) →
  next nav transition, including drill-in, back-out, and entering a text
  field. Prior art: `guided-menu.bats`.
- **Terminal-stage rewire** — a few bats around the now-uniform post-menu
  disk resolution (single resolved post-menu like multi) and the
  password/consent ordering. Prior art: `guided-shell.bats` assembly tests.
- **Launcher + live draw** — smoke-only (the live fzf draw), per the
  established convention.
- **VM spine smoke** — the first slice drives a full default install
  through the persistent menu to a booting system, via the existing guided
  VM replay served by `git daemon` + `REPO_URL`. Prior art:
  `tests/vm/profiles/single/guided*.jsonc`.

## Out of Scope

- Adopting a compiled TUI toolkit (ratatui / bubbletea) or any non-fzf
  renderer — rejected per ADR 0042.
- Any change to the pure cores' contracts or the `--guided` replay
  interface — frozen by design.
- Multi-filesystem work (btrfs / ext4 / xfs / LUKS) — reserved per ADR
  0040, untouched here.
- Live-system enumeration for locale / timezone / keymap pickers beyond
  the seeded, editable rows.
- New Configuration Categories, fields, or defaults — this is a rendering /
  control-model change, not a feature addition.

## Further Notes

- A throwaway **stopgap** already shipped on branch
  `guided-persistent-fzf`: the category subloop now carries the same
  `--header`/`--expect` toolbar (commits `acd49fa` ADR + `f9b5169` fix,
  guided-shell at 88 bats). The rewrite deletes that subloop, retiring the
  stopgap.
- Suggested tracer-bullet slice order: **01 spine** — a minimal persistent
  single-fzf driving a complete default install (reload-nav over enumerable
  fields, config-only menu, post-menu disks + passwords + INSTALL, state
  file) with free-text temporarily reusing the old one-shot prompt so the
  path is end-to-end; **02** free-text via the query line; **03**
  undo / redo / reset as global binds; **04** polish (per-screen headers,
  preview-window behavior).
- When the rewrite lands, trim the `CONTEXT.md` Guided Installer sentence
  about free-text "dropping to a typed prompt" — it's an implementation
  detail that no longer holds and shouldn't be in the glossary.
