# Spec: Guided Installer navigation affordances — debug run, visible
# actions, host/user editing, and summary previews

Status: ready-for-agent

Relevant ADRs: 0063 (guided action rows stay visible — this spec, amends 0047),
0047 (rich-chrome action-row placement + In-Menu Disk Binding), 0055 (Profiles
picker + default secret posture), 0051 (inline masked credentials + User
Editor), 0054 (root shell + encryption passphrase), 0058 (Host Core as menu
baseline / authoritative program kind), 0036 (device-less Host Profile /
Effective Config), 0042 (persistent-fzf controller).

## Problem Statement

While navigating the Guided Installer, the operator hit four friction points:

1. **Cannot exercise the menu on a normal machine.** Running `install.sh` on a
   daily-driver Arch box (only to inspect the menu) is blocked by the
   full-toolchain preflight, which tries to `pacman -Sy` install install-only
   tools (`pacstrap`, `mdadm`, `reflector`, `gptfdisk`, `cryptsetup`, …) — a
   root operation the operator does not want on a machine they will never
   install onto. The only way to see the menu is to boot the live CD.

2. **No visible "add user" action.** On the Users screen there is no visible row
   to create a user; it works only via an undiscoverable `^A` shortcut. The same
   is true of every other in-menu action (add package, add sysctl, remove, Back)
   and of the host side.

3. **Editing a host's users is not obvious.** The operator expects to select a
   host, then choose from predefined users (e.g. `aquastias`) or create a new
   one — with creation opening an editor for shell, groups, etc. The capability
   exists but is hidden by (2) and is not framed as "this host's users".

4. **No summary panels.** There is no at-a-glance view of what a user or a host
   holds. Hovering a user should show its shell/groups; selecting a host/profile
   should show a full tree of what that machine installs (users, options,
   security, impermanence, …).

## Solution

From the operator's perspective:

- **A `--debug` run.** `install.sh --debug` launches any front-end for
  inspection/authoring only: it skips the install-toolchain preflight (only the
  front-end tools `jq`+`fzf` are ensured, so the menu still opens) and never
  installs — the numbered phases (bootstrap/wipe/install) do not run, so no disk
  is touched. The guided menu, its previews, the `--profile` disk picker, and
  Save/Export all still work. Plain `install.sh` on the live CD stays fully
  guarded. The flag is global (honoured by every front-end).

- **Every action is a visible row again.** In rich chrome, `＋ Create user`,
  `＋ Add package`, `＋ Add sysctl`, `＋ Add SSH key`, `✗ remove …`, and `← Back`
  render as list rows exactly as they did on older fzf; the `^A`/`^X`/`Esc`
  keybindings remain as accelerators. This reverses the hidden-actions half of
  ADR 0047 (ADR 0063).

- **Select a host, edit its users.** The `Profiles ▸` picker is always present
  (even with no committed profiles) and leads with a `＋ New host (start blank)`
  row. Picking a committed profile seeds the machine; its users appear on the
  now-legible Users screen where predefined users toggle on/off and `＋ Create
  user` opens the User Editor (shell, groups, sudo, …).

- **Root collapses to one row.** The Users screen shows a single
  `root — <shell> · pw <tag>` row that opens a **Root Editor** (password +
  shell), symmetric with the per-user editor — replacing the two separate
  `root password` / `root shell` rows.

- **Summary previews.** Hovering a user shows a full panel (shell, sudo, groups,
  programs, git, SSH keys). Hovering a host/profile shows a **deep tree** of
  the machine down to its leaves (hostname; users → shell·groups; options incl.
  encryption and impermanence; environment; security; backup; disks).

## User Stories

1. As an operator on my daily-driver Arch box, I want to launch the guided menu
   without being asked to install install-only tooling, so that I can inspect
   the menu without polluting my system.
2. As an operator running `--debug`, I want the numbered install phases to never
   run, so that no disk is ever touched during inspection.
3. As an operator running `--debug`, I want the menu, previews, and disk picker
   to still function, so that inspection is faithful to the real thing.
4. As an operator running `--debug`, I want Save Profile and Export Config to
   still write their artifacts, so that I can author a profile from a non-target
   box.
5. As an operator, I want `--debug` to work regardless of front-end (bare
   guided, `--profile`, positional config), so that I do not have to remember
   which invocation supports it.
6. As an operator on the live CD, I want plain `install.sh` (no `--debug`) to
   remain fully preflight-guarded, so that a real install never fails mid-wipe
   on a missing tool.
7. As an operator, I want a visible `＋ Create user` row on the Users screen, so
   that I can add a user without knowing a keyboard shortcut.
8. As an operator, I want every add/remove/back action to appear as a visible
   row in the menu, so that the available actions are discoverable at a glance.
9. As an operator who prefers keys, I want `^A`/`^X`/`Esc` to still perform the
   same actions, so that the visible rows do not slow me down.
10. As an operator, I want a `Profiles ▸` entry that is always visible, so that
    selecting or starting a host is a first-class step every run.
11. As an operator, I want a `＋ New host (start blank)` row in the picker, so
    that I can begin a fresh machine explicitly rather than by avoiding the
    picker.
12. As an operator choosing `＋ New host`, I want a confirmation before my
    session work is discarded, so that I do not lose edits by accident.
13. As an operator choosing `＋ New host`, I want the reset to clear everything —
    config overrides, created users and their editor forms, password/secret
    overrides, and in-menu disk bindings — so that "start blank" is truly blank.
14. As an operator, I want the `＋ New host` reset to be undoable, so that an
    accidental confirmation is recoverable.
15. As an operator seeding a committed profile, I want that host's users to
    appear pre-selected on the Users screen, so that I can see and adjust what
    the host comes with.
16. As an operator, I want to toggle predefined users (e.g. `aquastias`) on or
    off for the host, so that I can compose the host's user set from existing
    people.
17. As an operator, I want `＋ Create user` to open the User Editor (shell,
    groups, sudo, git, SSH keys, programs), so that a new user is fully
    specified in one place.
18. As an operator, I want root shown as a single account row, so that root
    reads like every other account rather than two disconnected settings.
19. As an operator, I want Enter on the root row to open a Root Editor with
    password and shell, so that both root settings live behind one consistent
    editor.
20. As an operator, I want the Root Editor's password captured masked and
    confirmed, so that it behaves like the other password fields.
21. As an operator hovering a user row, I want a side panel showing that user's
    shell, sudo, groups, programs, git identity, and SSH-key count, so that I
    can review the account without opening its editor.
22. As an operator hovering a user with committed and session edits, I want the
    panel to show the effective (core-merged, override-applied) values, so that
    it reflects what will actually install.
23. As an operator hovering a host/profile row, I want a deep tree of that
    machine, so that I understand exactly what selecting it will bring.
24. As an operator, I want the host tree to expand users to their shell and
    groups, so that I can see the people, not just their names.
25. As an operator, I want the host tree to surface options such as encryption
    and impermanence, environment, security, and backup, so that the high-stakes
    choices are visible before I commit to a profile.
26. As an operator, I want profile picker rows to stay clean (name only), so
    that the list is scannable and detail lives in the preview.
27. As an operator, I want the deep tree to reuse the same ASCII tree style as
    the disk-layout preview, so that previews feel consistent.

## Implementation Decisions

- **`--debug` is a global flag on the Single Entry Point.** Parsed alongside the
  other flags. Two effects: (a) the full-toolchain preflight is skipped —
  only the front-end tools (`jq`, and `fzf` when an interactive front-end will
  run) are ensured; (b) the install is withheld — the bootstrap/wipe/install
  phases never execute. Interactive front-ends (guided menu + previews, the
  `--profile` disk picker) still run; Save and Export still write their files.
  The name is retained despite the "skip install" (not "verbose logging")
  meaning; the meaning is documented at the flag site.

- **One pure `--debug` resolver (new seam).** The decision "given the parsed
  flags, which preflight tier applies and does this run install?" is extracted
  into a single pure function so it can be unit-tested without running the
  installer. install.sh calls it to choose the preflight token set and to decide
  whether to reach the numbered phases. The existing guided "terminal action
  that is not install" early-exit (rc 64) is the model for withholding the
  phases; `--debug` withholds them for every front-end.

- **`_ctl_action_row` becomes unconditional.** The rich-chrome gate is dropped
  so action rows always render (ADR 0063). The `^A`/`^X`/`Esc` keybindings are
  unchanged. Rich chrome otherwise (footer, breadcrumb, borders) is untouched.

- **Root row merge + Root Editor.** The Users screen renders a single
  `root — <shell> · pw <tag>` row in place of the separate `root password` and
  `root shell` rows. Enter opens a Root Editor sub-screen exposing exactly
  `password` and `shell`. Password uses the existing inline-masked,
  type-twice-confirm capture and the no-SOPS manifest's root role; shell cycles
  `/bin/bash → /bin/zsh → /bin/fish` and stores `options.root_shell` (normalised
  out at the default) — same storage as today, only the surface changes.

- **Profiles picker is unconditional and leads with `＋ New host`.** The
  availability gate that hid the picker when no committed profiles exist is
  dropped. A `＋ New host (start blank)` row leads the list. Selecting it does a
  confirm-gated, undoable **full session reset**: Config State back to the Host
  Core baseline, plus clearing session-created users and their editor forms, the
  password/secret manifest overrides, and any in-menu disk bindings. This is
  broader than the edit-history `Reset all` (Config State only) and a distinct
  action, not an alias.

- **Profile deep-tree preview.** `guided_ctl_preview` gains, for a picker
  row, a deep ASCII tree of the resolved (Host-Core-merged) profile: hostname;
  users expanded to shell·groups; options including kernel, bootloader,
  encryption, impermanence, swap, ssh; environment (desktop/gpu); security;
  backup; and the disk skeleton. It reuses the layout-graph tree rendering style
  and replaces the current header-comment-only profile preview.

- **User detail preview.** The Users values screen joins the set that shows
  a side panel. `guided_ctl_preview` renders, for a hovered user row, the
  effective User Profile: shell, sudo, groups, programs (list/count), git
  identity if set, and SSH-key count. A session-created user shows its
  in-progress editor-form state.

- **Clean picker rows.** Profile rows keep showing only the profile name (and
  `▸`); no inline user/hostname hint is added — the deep tree covers it.

## Testing Decisions

Good tests here assert **external behavior visible in rendered output**, not
internal wiring: the presence/order of rows, the shape of a preview body, the
resulting Config State/session state after an action, and the resolver's
tier/install decision. No fzf and no tty; drive the controller's pure functions
directly, seeding the `GUIDED_STATE_FILE` / `GUIDED_NAV_FILE` /
`GUIDED_BASELINE_FILE` files as the existing guided bats do.

- **Seam A — guided controller pure functions (existing).** Prior art:
  `tests/config/guided-chrome.bats`, `guided-profiles-menu.bats`,
  `guided-users.bats`, `guided-nav.bats` (all `run guided_ctl_list` /
  `guided_ctl_enter` and assert rows).
  - `guided_ctl_list`: action rows visible under rich chrome (`＋ Create user`,
    `← Back`, etc.); the single merged `root — … · pw …` row (and absence of the
    two old rows); `＋ New host (start blank)` leading the picker; `Profiles ▸`
    present even when the hosts tree is empty.
  - `guided_ctl_preview <line>`: the deep profile tree for a picker row (assert
    the tree contains hostname, a user's shell·groups, and the
    encryption/impermanence options); the user detail panel for a Users row
    (assert shell/sudo/groups/programs lines). This preview seam is currently
    untested — a new bats file mirroring the chrome test's setup.
  - `guided_ctl_enter <line>`: Enter on the root row navigates to the Root
    Editor screen; `＋ New host` triggers the full reset (assert Config State is
    back to baseline and session user/secret/binding state is cleared, and that
    an undo restores it).

- **Seam B — the `--debug` resolver (new, pure).** Prior art:
  `tests/preflight.bats` (asserts the resolved package token set of
  `preflight_installer_tools` without root or network). Table-test the resolver:
  `--debug` yields the front-end-only tier and install-withheld; each non-debug
  front-end yields the full toolchain tier and install-proceeds. The "no disk
  touched" guarantee is asserted here (the resolver says install is withheld),
  not by executing the installer.

The rich-chrome version gate (`_ctl_fzf_rich_for_version`) and the existing
Profiles-picker and Users-screen tests must be updated to the new expectations
(visible rows under rich chrome; unconditional picker; merged root row).

## Out of Scope

- Any persistent multi-host / fleet model. Guided remains single-machine per run
  (one Effective Config, one install target); "hosts" are seed sources and Save
  Profile authors new ones.
- Changing the back-end, the Effective Config shape, or how a profile is stored
  (device-less save invariant, ADR 0036, is unchanged).
- Verbose/diagnostic logging under `--debug` — the flag only skips preflight and
  withholds the install; it does not change log verbosity.
- Editing committed `hosts/*` or `users/*` files from the menu. Edits stay
  install-scoped (ADR 0051); Save Profile stays the only write path, unchanged.
- New Root Editor capabilities beyond password + shell (root has no
  groups/sudo/programs).
- Inline at-a-glance hints on profile rows (explicitly rejected in favour of the
  preview pane).

## Further Notes

- `＋ New host` overlaps conceptually with `Reset all` but is deliberately
  broader (session-wide, not just Config State) and lives in the picker rather
  than the edit-history toolbar; both are kept.
- On a fresh repo the picker now restates the blank state (only `＋ New host` +
  `← Back`); this is accepted for a consistent entry point.
- The change amends, but does not revert, ADR 0047: In-Menu Disk Binding, the
  Free Set, and freeform layouts are untouched — only the actions-on-keybindings
  sub-decision changes (ADR 0063).
