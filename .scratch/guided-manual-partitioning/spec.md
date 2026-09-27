# Spec: Guided Manual Partitioning

Status: ready-for-agent

Relates to: ADR 0073 (guided manual partitioning disk-config kind),
CONTEXT.md → **Manual Partitioning**. Amends ADR 0036's device-less invariant;
sits beside the ADR 0034/0040/0043 layout adapters.

## Problem Statement

The installer's disk configuration is entirely declarative and pool-shaped: the
operator picks a filesystem and the installer imposes a fixed partition scheme
(`ESP + [swap] + root`, or a ZFS pool skeleton), always full-wiping the disk
first. There is no way to hand-draw the partition table — no dual-boot, no
reusing an existing partition, no custom scheme. archinstall offers exactly this
("Manual partitioning" launches `cfdisk`, then assigns mountpoints), and this
installer categorically cannot. An operator who wants to lay out the disk
themselves — even for a plain ext4 single-disk install with their own sizes — has
no path.

## Solution

Add a **Manual partitioning** on/off toggle to the **Disks** category of the
Guided Installer. Off is the installer's predefined (auto) behaviour, unchanged.
On hands the whole partition table to the operator: it launches `cfdisk` on the
chosen disk (archinstall-style), re-reads the resulting table, and lets the
operator assign each partition a mountpoint, a filesystem, and a
format-or-keep choice. The installer then formats only what was marked and mounts
per the assignment.

Manual is a deliberately **feature-light escape hatch**. Because it bypasses the
pool machinery, it disables every pool-dependent feature (ZFS/pool layouts,
encryption, impermanence, data pools/storage groups, managed swap, ESP size). A
one-time confirm **notice** names this cost when the operator turns it on, and
the disabled fields stay **shown-but-locked** on the Disks screen so the operator
sees what was traded away. It is reversible (toggle back and the pool choices
return) and, because a hand-drawn table cannot be replayed from a committed file,
**Proceed-only** — never saved to a profile, exported, or offered on the
`--profile` / unattended paths.

## User Stories

1. As an operator, I want a **Manual partitioning** toggle on the Disks screen,
   so that I can opt out of the predefined layouts and drive the partition table
   myself.
2. As an operator, I want turning Manual partitioning on to show a confirm
   notice, so that I understand which installer features I am giving up before I
   commit.
3. As an operator, I want the notice to name the exact disabled features
   (ZFS/pool layouts, encryption, impermanence, data pools, managed swap, ESP
   size), so that I am not surprised later by a missing capability.
4. As an operator, I want the disabled Disks fields to stay visible but locked
   (not hidden) while Manual is on, so that I can see what auto mode would have
   offered.
5. As an operator, I want to turn Manual partitioning back off, so that my
   earlier ZFS/encryption/impermanence choices are restored intact.
6. As an operator, I want toggling Manual on and off to never lose either side's
   configuration, so that I can compare the two approaches without redoing work.
7. As an operator, I want to pick which disk Manual partitioning targets, so that
   I control where `cfdisk` runs.
8. As an operator, I want the live install medium excluded from the target
   choices, so that I cannot accidentally partition the disk I booted from.
9. As an operator, I want the installer to launch `cfdisk` on my chosen disk, so
   that I lay out partitions with the same tool archinstall uses.
10. As an operator, I want to cut a swap partition in `cfdisk` myself, so that I
    control swap size and placement without the managed-swap machinery.
11. As an operator, I want the installer to re-read the partition table after I
    exit `cfdisk`, so that the assignment step reflects exactly what I created.
12. As an operator, I want each partition shown in an assignment table, so that I
    can decide what to do with each one.
13. As an operator, I want to assign a mountpoint to a partition (`/`,
    `/boot/efi`, `/home`, `[swap]`, or none), so that the installer mounts my
    layout the way I intend.
14. As an operator, I want to choose a filesystem for a partition I am formatting
    (ext4/xfs/btrfs/fat32), so that fresh partitions are created the way I want.
15. As an operator, I want to mark a partition format-or-keep, so that I can
    preserve existing data (e.g. a dual-boot `/home`) while formatting others.
16. As an operator, I want ESP partitions (type `ef00`) and swap partitions
    (type `8200`) to pre-fill their assignment from the partition type, so that I
    do less manual work for the obvious cases.
17. As an operator, I want partitions I leave unassigned to be ignored, so that
    extra partitions on the disk are neither touched nor mounted.
18. As an operator, I want the installer to reject a layout without exactly one
    root (`/`), so that I cannot start an install that has nowhere to put the OS.
19. As an operator, I want the installer to reject a layout without exactly one
    FAT32 ESP at `/boot/efi`, so that the bootloader has a valid target.
20. As an operator, I want a clear, actionable error when validation fails
    (missing root, missing/invalid ESP, duplicate `/`), so that I know what to
    fix.
21. As an operator, I want a manual layout to Proceed to a real install, so that
    the hand-drawn table actually results in a booting system.
22. As an operator, I want a manual install to boot afterwards, so that the
    escape hatch produces a usable machine, not just a mounted tree.
23. As an operator, I want Manual partitioning to be unavailable on the
    `--profile` Pre-Install Picker and the unattended `install.sh <config-file>`
    path, so that reproducible installs stay declarative.
24. As an operator, I want Manual partitioning to offer no Save Profile or Export,
    so that I am not misled into thinking a hand-drawn table can be committed.
25. As a maintainer, I want the manual partition assignment to never reach a
    committed or exported artifact, so that ADR 0036's device-less invariant
    holds.
26. As a maintainer, I want the auto (pool skeleton) path to be entirely
    unchanged when Manual is off, so that the new feature carries no regression
    risk for existing installs.
27. As a maintainer, I want the "assignment → format/mount plan" logic to be a
    pure, headless-testable module, so that the contract is verified without a VM.
28. As a maintainer, I want a single VM case exercising a real manual install end
    to end, so that the disk-touching path is proven to boot.

## Implementation Decisions

- **`disk_config` kind discriminator (schema).** Disk configuration becomes a
  discriminated kind: `auto` (today's pool skeleton — `mode`, `os_pool`,
  `storage_groups[]`, `data_pools[]`, unchanged and the default) vs `manual` (a
  flat `partitions[]` list). The back-end dispatches on the kind the way the
  layout dispatch keys on filesystem today. This joins the closed host schema;
  the `auto` shape is the default when the kind is absent, so existing configs
  are untouched.
- **`partitions[]` shape.** Each entry carries `device`, `mountpoint`
  (`/`, `/boot/efi`, `/home`, `[swap]`, or empty/none), `fs`
  (ext4/xfs/btrfs/fat32), and `format` (boolean: mkfs vs keep). Populated by the
  Guided Installer from the operator's `cfdisk` session + assignment step;
  transient, never committed or exported.
- **New pure module: manual layout planner/validator.** Mirrors the non-ZFS
  planner (`nonzfs/plan.sh`): consumes `partitions[]`, validates it (exactly one
  `/`, exactly one FAT32 `/boot/efi`; ESP/swap recognised by type), and emits the
  format+mount plan the executor consumes. Pure — no disk access. Errors are
  actionable and name the offending condition.
- **New Root Layout Adapter: manual.** A back-end adapter, dispatched when
  `disk_config.kind == manual`, that consumes the plan: `mkfs` only where
  `format` is true, mount every assigned partition at its mountpoint under
  `MOUNT_ROOT`, `mkswap` + swapon any `[swap]` partition, and publish the
  filesystem-blind boot record. It does **not** whole-disk wipe — the operator's
  `cfdisk` session already owns the table; only marked partitions are formatted.
- **Layout dispatch.** `dispatch.sh` gains a kind branch: `manual` sources the
  manual adapter; every other path stays filesystem × mode as today.
- **Guided front-end: cfdisk hand-off.** A partitions sub-screen under Disks:
  pick target disk (live medium excluded via the existing Live-Medium Detector) →
  launch `cfdisk` → re-read the table (`lsblk`) → render the assignment table.
  ESP (`ef00`) and swap (`8200`) pre-fill their mountpoint from partition type.
- **Guided menu model.** A **Manual partitioning** toggle field on the Disks
  category sets `disk_config.kind`. Turning it on fires the one-time confirm
  notice; while on, the pool-dependent Disks fields (filesystem, encryption,
  impermanence, data pools, esp size) render **shown-but-locked** — visible,
  dimmed, non-enterable. Turning it off restores them and their stored values.
  This is distinct from the existing hidden-for-ext4/xfs impermanence rule
  (ADR 0040), which hides rather than locks.
- **Accessors.** `install_config_disk_kind` and
  `install_config_partition_*` (count, device, mountpoint, fs, format) join the
  existing config-accessors module.
- **Lifecycle.** Guided-only, Proceed-only. No Save Profile, no Export, no
  presence on the `--profile` Pre-Install Picker or the unattended path. The
  assignment is transient (ADR 0036 invariant preserved).
- **Feature envelope.** Manual disables ZFS/pool layouts, encryption
  (Encryption Editor), impermanence (Impermanence Editor), data pools / storage
  groups / pool owners, managed swap (the zswap default, ADR 0045), and the
  ESP-size field. Swap is supported only as an operator-cut `cfdisk` partition
  assigned `[swap]`.

## Testing Decisions

Good tests here assert **external behaviour** — given a `partitions[]`
assignment, what plan/validation result comes out; given a toggle state, what the
menu model exposes and locks — never internal call sequences or private helpers.

- **Manual layout planner/validator (new seam, pure, bats).** The primary target.
  Table-driven cases: valid single-disk `ESP + root`; valid with `/home` +
  `[swap]`; keep-existing on a reused partition; and the rejection cases — no
  root, no ESP, ESP not FAT32, duplicate `/`. Assert the emitted plan
  (what gets formatted, what gets mounted where) and the exact error on the
  invalid cases. *Prior art:* `tests/layout/nonzfs-plan.bats`.
- **Config accessors (reused seam, pure, bats).** `disk_config.kind` resolves
  `auto` by default and `manual` when set; `partitions[]` accessors read
  device/mountpoint/fs/format and count. *Prior art:* the existing accessor bats.
- **Guided menu model (reused seam, pure/headless, bats).** The Manual toggle
  sets the kind; the dependent Disks fields report as locked while on and normal
  while off; toggling off restores stored pool-side values; the notice gate fires
  once. *Prior art:* `tests/config/guided-custom-layout.bats`,
  `tests/config/guided-disk-bind.bats`.
- **VM matrix case (reused seam, end-to-end, VM-only).** One manual case: seed a
  scripted partition table (non-interactive `sfdisk`/`sgdisk` standing in for the
  operator's `cfdisk`), assign, install, and verify the system boots. The only
  place real `mkfs`/`mount`/boot is exercised. *Prior art:* the `arch-zfs-test-*`
  VM harness + `vm/vm-pool-verify.bats`.

## Out of Scope

- **Pre-mounted configuration** (archinstall's third disk item: operator mounts
  everything under `/mnt`, installer only pacstraps). Not shipped; deferrable as a
  future second toggle (ADR 0073).
- **"Full manual"** — feeding a hand-drawn table back into ZFS pools, native
  encryption, or impermanence. That capability already exists as the declarative
  `auto` path; manual is deliberately plain.
- **Managed swap in manual** (zswap default, sizing). Swap is only an
  operator-cut partition assigned `[swap]`.
- **Saving/exporting a manual layout** — Proceed-only by design.
- **Multi-disk manual layouts as a first-class topology** — manual mounts
  whatever partitions the operator assigns; it does not model pool topology.

## Further Notes

- The confirm notice is the operator's contract: it must enumerate the disabled
  features explicitly (per user story 3), not just say "some features become
  unavailable."
- `cfdisk` launch, table re-read, `mkfs`, and `mount` are VM-verifiable only; all
  decision logic (kind schema, accessors, planner/validator, menu lock/notice
  model, dispatch branch) is covered headless in bats.
- The Combination Matrix / VM registry gains a `disk_config.kind: manual` axis
  value alongside the existing filesystem/topology axes.
