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

## Acceptance criteria

- [ ] Bare `install.sh` launches the guided fzf menu; `--profile` and
      positional `<config-file>` seams behave exactly as before.
- [ ] Menu shows the Host / Users split; System ▸ hostname is editable;
      Disks ▸ filesystem = ZFS ▸ single-disk resolves a disk via the
      Pre-Install Picker with its preview pane.
- [ ] Proceed assembles a tmpfs Effective Config merged over Host Core
      and runs `01 → 02 → 03`; the review screen lists target + WIPE
      disks and requires a typed `INSTALL`.
- [ ] `generate_template` and the bare-default `install.jsonc` are
      removed; missing config on the non-guided path fails with an
      actionable message.
- [ ] The VM seed passes its Effective Config positionally; the existing
      VM suite and bats suite are green.
- [ ] bats cover Config State (get/set/unset + emit), Menu model (rows
      for the covered fields), and Emitter (state → Effective Config),
      asserting JSON output, never internal structure.
- [ ] VM smoke: a guided single-disk ZFS install boots.

## Blocked by

None - can start immediately.
