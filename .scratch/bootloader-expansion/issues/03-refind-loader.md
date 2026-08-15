# 03 — refind loader

**What to build:** Let an operator pick `refind` and have the machine boot. refind
autodetects installed kernels on the ESP, so multi-kernel comes for free — the
work is a new Bootloader Adapter that installs refind, writes a
`refind_linux.conf` carrying the root cmdline, and pins the default selection to
the Primary Kernel; a Bootloader Manifest row (loader path, `refind` package,
esp-style, supports-zfs); the enum + Guided radiolist gaining the option; and the
VM matrix `bootloader` axis gaining `refind` so it is exercised end-to-end. Works
on a ZFS root by reading the ESP-mirrored kernels, exactly like the other
ESP-mirroring loaders.

**Blocked by:** 01 — Bootloader Manifest foundation.

**Status:** ready-for-agent

- [ ] `refind` is a legal `options.bootloader` value, offered in the Guided
      radiolist and accepted from a committed Host Profile.
- [ ] The refind adapter installs refind, emits a `refind_linux.conf` with the
      correct root cmdline (ZFS and non-ZFS), and defaults to the Primary Kernel.
- [ ] A manifest row declares refind's loader path, `refind` package, esp-style,
      and ZFS support.
- [ ] The VM matrix boots a refind install end-to-end; all selected kernels are
      bootable via autodetect.
- [ ] Tests cover the manifest row, package resolution (`refind`), the enum
      entry, and the config emission.
