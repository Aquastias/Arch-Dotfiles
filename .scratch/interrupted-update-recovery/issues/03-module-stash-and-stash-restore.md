# 03: Module Stash + Stash Restore

Status: done

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

- [x] Bats: stash plan (changed selected kernels only, no strays)
- [x] Bats: restore only when modules missing and stash present
- [x] Bats: stash dropped after a successful sync
- [x] Stash survives an Impermanence boot-time rollback
- [x] VM (01 recipe): interrupted swap now boots to the normal target;
      re-running pacman completes the update and drops the stash
- [x] Retrofit installs it on all five loaders

## Comments

- Code + bats done. The stash is a hard-linked copy under
  `/usr/lib/modules/.stash` (root dataset: outside every Rollback Dataset,
  mounted before any module loads). The restore unit is enabled from the
  vendor `sysinit.target.wants`, never `/etc`. The ESP Kernel Sync drops the
  stash after a successful run, removing restored trees no package owns.
- After a Stash Restore, `pacman -Syu` alone does nothing (the database
  already lists the new kernel); finishing needs a reinstall of the kernel
  package(s). Ticket 04's notice must say `sudo pacman -S <kernel>`.
- Open: the VM check (needs ticket 01).
