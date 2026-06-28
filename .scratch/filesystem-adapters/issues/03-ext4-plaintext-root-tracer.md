# 03 — ext4 plaintext root tracer (non-ZFS root plumbing end-to-end)

Status: done
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

DONE + VM-verified 2026-06-28 (pure-ext4 install boots headless; ZFS path
regression-verified behavior-preserving). Commits: slice 1 `1a6a922`
(FS-agnostic boot path), slice 2 `82865d9` (ext4 adapter + gating).
- [x] **Non-ZFS partition planner** (`lib/layout/nonzfs/plan.sh`) — ESP+swap+root
      remainder math + floor validation + partition slots
      (`tests/layout/nonzfs-plan.bats`).
- [x] **ext4 `ROOT_CMDLINE` + `HOOKS` emitters** (`lib/layout/ext4/boot.sh`) —
      `root=UUID=…`; HOOKS with block→filesystems, no zfs/encrypt
      (`tests/layout/ext4-boot.bats`).
- [x] **zfs-presence predicate** (`install_config_any_zfs`) — gates zfs
      userland/import/guard/ISO (`tests/config/zfs-presence.bats`).
- [x] **ext4 Root Adapter** (`lib/layout/ext4/single.sh`) — implements the seam,
      publishes `LAYOUT_ROOT_CMDLINE`/`HOOKS`/`FSTAB_EXTRA`; reuses the shared
      `lib/layout/core.sh` (extracted from `zfs/common.sh`).
- [x] **install-state `root_cmdline` + `hooks`** + ZFS publishes equivalents
      (behavior-preserving) (`tests/install-state.bats`).
- [x] **FS-agnostic `bootloader-systemd-boot.sh` + `initcpio.sh`** consume
      `ROOT_CMDLINE`/`HOOKS` (`modconf`→`kmod` fixup kept).
- [x] **swap partition** (mkswap + fstab via `LAYOUT_FSTAB_EXTRA`) + zfs-presence
      gating wired across `03-install.sh`, `lib/packages/list.sh`,
      `lib/chroot/configure.sh`, and `01-bootstrap-zfs.sh`.
- [x] **VM boot-verify for non-ZFS roots** — the harness mounts the root by its
      GPT partlabel when there is no zpool (`vm/lib/seed-generator.sh`); new
      `tests/vm/profiles/single/ext4-plain.jsonc`.

## Acceptance criteria

- [x] A pure ext4 install (root + swap, no ZFS anywhere) boots headless in a VM.
- [x] The bootloader and `initcpio.sh` are filesystem-agnostic — they write the
      active Root Adapter's `ROOT_CMDLINE` + `HOOKS`; the existing ZFS path still
      emits `root=ZFS=…` and the zfs hooks unchanged (regression-verified).
- [x] Swap is a dedicated partition; zswap cmdline still applied.
- [x] zfs userland, boot-time import, ZFS Module Guard, and the archzfs ISO
      requirement are skipped when no group is ZFS, and still present when any
      group is ZFS.
- [x] bats covers the non-ZFS partition planner (ESP/swap/root plan + device
      paths) and the `ROOT_CMDLINE`/`HOOKS` emitters (ext4 + zfs, unencrypted).

## Blocked by

- `01` (schema/validation), `02` (dispatch split)
