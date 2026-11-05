# 03: Module Stash + Stash Restore

Status: ready-for-agent

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** an Interrupted Kernel Transaction boots normally. Before
a kernel transaction, every selected kernel whose version changes gets a
Module Stash (ZFS module included), taken before dkms removes it and kept
outside every Rollback Dataset; Stray Kernels are skipped. The stash is
dropped once the ESP Kernel Sync succeeds. At boot, the Stash Restore puts a
stash back before any module loads when the running kernel's modules are
missing, and does nothing otherwise. Installed by the installer and the
retrofit tool, on ZFS and non-ZFS roots.

**Blocked by:** 01, 02.

- [ ] Bats: stash plan (changed selected kernels only, no strays)
- [ ] Bats: restore only when modules missing and stash present
- [ ] Bats: stash dropped after a successful sync
- [ ] Stash survives an Impermanence boot-time rollback
- [ ] VM (01 recipe): interrupted swap now boots to the normal target;
      re-running pacman completes the update and drops the stash
- [ ] Retrofit installs it on all five loaders
