# 03 — ext4 plaintext root tracer (non-ZFS root plumbing end-to-end)

Status: ready-for-agent
Type: AFK

## Parent

`.scratch/filesystem-adapters/PRD.md`

## What to build

The first non-ZFS vertical tracer: a pure, **unencrypted** ext4 machine installs
and boots end-to-end. This establishes every shared non-ZFS-root primitive with
zero filesystem cleverness. Build the non-ZFS partition planner (`ESP + swap +
root`), the ext4 Root Layout Adapter (`mkfs.ext4`, mounts), and make the boot
path filesystem-agnostic: the Root Adapter emits a `ROOT_CMDLINE` fragment
(`root=UUID=…`) and a `HOOKS` list (`… filesystems`, no `zfs`), which the
bootloader and `initcpio.sh` now consume instead of hardcoding ZFS. Swap is a
dedicated plaintext partition sized from the existing `swap_size` logic; zswap
unchanged. Derive "any group is zfs" and gate zfs userland / boot-time import /
ZFS Module Guard / archzfs ISO requirement on it — a pure-ext4 install needs none
of them.

## Progress

Pure cores landed + bats-green (TDD), VM-gated wiring still to do:
- [x] **Non-ZFS partition planner** (`lib/layout/nonzfs/plan.sh`) — ESP+swap+root
      remainder math + floor validation (`tests/layout/nonzfs-plan.bats`).
- [x] **ext4 `ROOT_CMDLINE` + `HOOKS` emitters** (`lib/layout/ext4/boot.sh`) —
      `root=UUID=…`; HOOKS with block→filesystems, no zfs/encrypt
      (`tests/layout/ext4-boot.bats`).
- [x] **zfs-presence predicate** (`install_config_any_zfs`) — gates zfs
      userland/import/guard/ISO (`tests/config/zfs-presence.bats`).
- [ ] ext4 Root Adapter (`lib/layout/ext4/single.sh`) implementing the seam
      contract + publishing `LAYOUT_*`/`ROOT_CMDLINE`/`HOOKS` (VM-gated).
- [ ] install-state schema gains `root_cmdline` + `hooks`; ZFS adapter emits its
      equivalents (behavior-preserving) (VM-gated).
- [ ] FS-agnostic `bootloader-systemd-boot.sh` (consume `ROOT_CMDLINE`) +
      `initcpio.sh` (consume `HOOKS`) (VM-gated).
- [ ] swap partition (mkswap + fstab) + zfs-presence gating wired (VM-gated).

## Acceptance criteria

- [ ] A pure ext4 install (root + swap, no ZFS anywhere) boots headless in a VM.
- [ ] The bootloader and `initcpio.sh` are filesystem-agnostic — they write the
      active Root Adapter's `ROOT_CMDLINE` + `HOOKS`; the existing ZFS path still
      emits `root=ZFS=…` and the zfs hooks unchanged.
- [ ] Swap is a dedicated partition; zswap cmdline still applied.
- [ ] zfs userland, boot-time import, ZFS Module Guard, and the archzfs ISO
      requirement are skipped when no group is ZFS, and still present when any
      group is ZFS.
- [ ] bats covers the non-ZFS partition planner (ESP/swap/root plan + device
      paths) and the `ROOT_CMDLINE`/`HOOKS` emitters (ext4 + zfs, unencrypted).

## Blocked by

- `01` (schema/validation), `02` (dispatch split)
