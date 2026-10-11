# 01: Matrix cell zfs-single-plain runs out of disk during AUR builds

**What to build:** `matrix.sh run zfs-single-plain` installs the full
`eterniox` fleet profile (KDE, gaming, dev, AUR) onto a 40G VM disk. On
2026-10-10 the install died in the Runner's paru pass: `No space left on
device` from line 8786 of the installer log (pacman db, then the
`ani-cli-git` clone), so finalize never ran. Not caused by code changes in
that run (readability pilot touched summary/finalize/03-install outline only).
Either size the matrix disks for the fleet profile or install a slimmer
profile in boot-smoke cells.

**Blocked by:** None (can start immediately)

**Status:** needs-triage

- [ ] Root cause: what fills the 40G (package cache, paru build dirs, ARC?)
- [ ] zfs-single-plain installs and boot-verifies green

## Comments

2026-10-11: `zfs-single-plain` installed and boot-verified green (INSTALLER-EXIT-0,
FIRSTBOOT-OK) on a 100 GiB disk with 10 GiB RAM / 4 vCPU (run via
`vm.sh --testing --verify-boot --recreate` on the emitted cell profile, with
`MATRIX_DISK_GIB=100 VM_RAM_MB=10240 VM_VCPUS=4`). The qcow2 ended at ~27 GiB
allocated after the AUR pass (libcef/qt6ct builds), so 40 GiB leaves too little
headroom for build dirs + cache. Also found: `matrix_run` never passes
`--recreate`, so a stale domain from an earlier run is reused with its old
RAM/vCPU/disk size and env overrides silently do nothing. Suggest raising the
`MATRIX_DISK_GIB` default (e.g. 80) and recreating matrix domains each run.
