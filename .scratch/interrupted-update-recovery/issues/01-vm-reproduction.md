# 01: On-demand VM reproduction of an Interrupted Kernel Transaction

Status: done

PRD: `.scratch/interrupted-update-recovery/PRD.md`, ADR 0166.

**What to build:** a repeatable, on-demand VM test that reproduces the
field incident on the current installer: snapshot the VM, swap linux-lts to
another version, cut the transaction off after module removal but before
the initramfs build and ESP Kernel Sync finish, hard-reset, and observe the
next boot. Restores the VM afterwards. Every later slice uses it as its
end-to-end check. Follows the repo's VM memory and one-VM rules; not part of
every matrix run.

**Blocked by:** None (can start immediately).

- [x] Recipe written to `.scratch/interrupted-kernel-upgrade/repro.md`
- [x] Run on the current installer reproduces it: running kernel has no
      modules on disk, preset missing, emergency mode
- [x] VM restored to its pre-test state afterwards
- [x] Refuses to start when host memory is below the VM's RAM + 8 GiB
