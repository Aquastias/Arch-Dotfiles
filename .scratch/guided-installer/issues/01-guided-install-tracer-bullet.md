# Tracer bullet: bare `install.sh` → guided single-disk ZFS install

Status: ready-for-agent

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

The thinnest end-to-end path: running bare `install.sh` (no `--profile`,
no positional config) launches the **Guided Installer** — an fzf menu
that builds an install over a sparse **Config State** and installs.

Scope is the minimum to install a single-disk ZFS box: a main menu split
**Host** / **Users**; **System ▸ hostname** (typed); **Disks ▸
filesystem = ZFS ▸ single-disk** (reusing the Pre-Install Picker for disk
selection + lsblk/SMART preview); and the **Proceed** terminal action,
which assembles a tmpfs **Effective Config** (merged over Host Core) and
hands it to the existing `01 → 02 → 03` back-end behind a review screen
that lists the target and the disks to be WIPED with a typed `INSTALL`
confirmation.

`generate_template` and the bare-default `install.jsonc` fallback are
removed; the non-guided missing-config path errors clearly. The VM seed
switches to passing its Effective Config **positionally** so the existing
VM suite stays green.

The pure core ships at the scope this slice exercises: **Config State**
(get/set/unset over a sparse override map + emit), **Menu model** (rows
for the covered fields), **Emitter** (state → Effective Config) — all
JSON-in/JSON-out, no TTY. The fzf shell is the thin impure layer.

The fzf shell (`lib/guided.sh`) holds **no logic** — it renders
`menu_rows`, dispatches to Config State, resolves disks via the picker,
assembles via the Emitter, and runs the terminal action. Its **only**
selection primitives are `guided_select` / `guided_prompt`: fzf (and a
typed prompt for free-text) interactively, but under `--guided <answers>`
they replay scripted answers from a file — the seam that lets a headless
harness drive the menu. `--guided` is the replay flag only; an operator
launches the menu with bare `install.sh`. The seam ships here; the
headless VM driver that uses it is `01b`.

Consent is a **single** gate: the review screen's typed `INSTALL` (read
through `guided_prompt`, so the replay file supplies it too). Proceed then
runs `01 → 02 → 03` **`--unattended`** so the back-end's own gates (02's
`WIPE`, 03's `Proceed?`, the root-password prompt) don't re-ask. Root
defaults to `12345` for this slice (the documented throwaway convention),
forward-compatible with issue 07's TUI passwords.

## Acceptance criteria

- [x] Bare `install.sh` launches the guided fzf menu; `--profile` and
      positional `<config-file>` seams behave exactly as before. The shell
      selects only through `guided_select` / `guided_prompt`; `--guided
      <answers>` replays them from a file (no inline fzf calls).
- [ ] Menu shows the Host / Users split; System ▸ hostname is editable;
      Disks ▸ filesystem = ZFS ▸ single-disk resolves a disk via the
      Pre-Install Picker with its preview pane.
- [x] Proceed assembles a tmpfs Effective Config merged over Host Core;
      the review screen lists target + WIPE disks and requires a typed
      `INSTALL` (the sole consent gate), then runs `01 → 02 → 03`
      **`--unattended`** so the back-end gates don't re-prompt (root
      defaults to `12345`).
- [x] `generate_template` and the bare-default `install.jsonc` are
      removed; missing config on the non-guided path fails with an
      actionable message.
- [x] The VM seed passes its Effective Config positionally
      (`flow-test`, `flow-persistent`, `seed-generator` + its bats
      assertion); the existing VM suite and bats suite are green.
- [x] bats cover Config State (get/set/unset + emit), Menu model (rows
      for the covered fields), and Emitter (state → Effective Config),
      asserting JSON output, never internal structure.
      (`tests/config/guided-state.bats`, `guided-emit.bats`,
      `guided-menu.bats` — 11 tests.)
- [x] VM smoke: a guided single-disk ZFS install boots — the **menu-driven**
      path (`vm.sh --guided`, via `01b`) installed + booted on real KVM
      (`INSTALLER-EXIT-0` → `FIRSTBOOT-OK`), exercising the replay seam →
      `guided_build` → Effective Config → `01→02→03`.

## Progress

Pure cores + the impure shell/entry are built and committed; the full
bats + VM suites are green (1065 tests). What remains:

- **Interactive menu is linear, not the re-entrant split menu.**
  `guided_build` drives a straight-line flow (hostname → single-disk pick
  → review → `INSTALL`) and assembles the correct Effective Config. The
  Host / Users split *model* exists (`menu_rows`), but the shell does not
  yet render a navigable split menu — that nav is the remaining 01 work
  (and dovetails with issue 02's non-destructive navigation).
- **VM smoke: DONE (menu-driven, via 01b).** `vm.sh --guided --profile
  single/guided --verify-boot` drove the guided menu headlessly on real KVM
  to `===INSTALLER-EXIT-0===` → ZFS root import → `===FIRSTBOOT-OK===`. The
  run flushed out two bugs bats had missed (review→stdout config corruption;
  missing required `system.locale`/`timezone`), both fixed with faithful
  regression guards. See `01b`.

## Blocked by

None - can start immediately.
