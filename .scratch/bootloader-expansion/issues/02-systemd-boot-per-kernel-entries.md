# 02 — systemd-boot per-kernel entries

**What to build:** Make systemd-boot boot **every** selected kernel, not only the
Primary Kernel. Today the adapter pins a single Primary-only entry
(`arch-zfs.conf`); instead iterate the ordered `KERNELS` array already present in
install-state and emit a default entry plus a fallback entry per kernel, with
per-kbase filenames, while pinning the loader's default selection to the Primary
Kernel (element 0). Extract the entry rendering into a pure, testable emit
function. The ESP Kernel Sync mechanism stays entry-driven and unchanged, so it
now mirrors all referenced kernels while still excluding a Stray Kernel. An
operator who selects, say, `lts` and `zen` can boot either, with `lts` (Primary)
as the default. (grub already boots all installed kernels via `grub-mkconfig`
with GRUB_DEFAULT pinned to the Primary — no change needed there.)

**Blocked by:** 01 — Bootloader Manifest foundation.

**Status:** ready-for-agent

- [ ] systemd-boot emits a default + fallback loader entry for each kernel in the
      Kernel Selection, with per-kbase entry filenames (the `arch-zfs.conf`
      hardcode is gone).
- [ ] The loader default boots the Primary Kernel regardless of kernel version
      ordering.
- [ ] Entry rendering is a pure function, unit-tested without the chroot copy /
      register steps (LIB_ONLY-style guard).
- [ ] `esp-kernel-sync` tests are extended to prove entries referencing several
      kernels mirror all of them, and a Stray Kernel still gets no entry and is
      never mirrored.
- [ ] A multi-kernel selection boots each selected kernel end-to-end in a VM.
