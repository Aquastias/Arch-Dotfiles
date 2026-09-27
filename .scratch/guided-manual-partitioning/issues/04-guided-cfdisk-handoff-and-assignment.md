# 04 — Guided cfdisk hand-off + assignment sub-screen (interactive authoring)

**What to build:** The interactive heart of Manual Partitioning. Under the Disks
category, once manual is on, the operator picks a target disk, the installer
launches `cfdisk` on it, re-reads the resulting table, and presents an assignment
sub-screen where each partition is given a mountpoint, a filesystem, and a
format-or-keep choice. The assignment is written to Config State as `partitions[]`
and Proceed installs it via the manual adapter. Manual offers no Save Profile or
Export.

**Blocked by:** 02, 03.

**Status:** done

- [x] The operator picks the target disk; the live install medium is excluded
      via the shared Live-Medium Detector.
- [x] The installer launches `cfdisk` on the chosen disk, then re-reads the
      partition table (`lsblk`) on exit.
- [x] Each partition renders as an assignment row: mountpoint (`/`, `/boot/efi`,
      `/home`, `[swap]`, or none), filesystem (ext4/xfs/btrfs/fat32), and
      format-or-keep.
- [x] ESP (`ef00`) and swap (`8200`) partitions pre-fill their mountpoint from
      the partition type; the operator can override.
- [x] The assignment writes `partitions[]` into Config State; Proceed assembles
      the Effective Config and installs via the 02 adapter.
- [x] Manual exposes **no Save Profile and no Export** action; the assignment is
      transient and never reaches a committed or exported artifact (ADR 0036).
- [x] The pure parts of the assignment flow (row model, type pre-fill, Config
      State write) are covered in bats; the `cfdisk`/`lsblk` steps are exercised
      in the VM case (ticket 05).

## Comments

- 2026-09-27 audit: 962cab1, c485ed0, 98704f1, 742f4e8
  (guided/manual-terminal.bats).
