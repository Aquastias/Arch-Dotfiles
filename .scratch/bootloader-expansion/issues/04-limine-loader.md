# 04 — limine loader

**What to build:** Let an operator pick `limine` and have the machine boot. limine
is a config-driven loader, so the adapter generates a `limine.conf` with a
per-kernel entry plus fallback for each selected kernel (mirroring the
systemd-boot entry set), copies the limine EFI binary onto the ESP, registers its
UEFI entry, and sets the default entry to the Primary Kernel. Add a Bootloader
Manifest row (loader path, `limine` package, esp-style, supports-zfs), the enum +
Guided radiolist option, and the VM matrix `bootloader` axis entry. Works on a
ZFS root by reading the ESP-mirrored kernels.

**Blocked by:** 01 — Bootloader Manifest foundation.

**Status:** done

- [x] `limine` is a legal `options.bootloader` value, offered in the Guided
      radiolist and accepted from a committed Host Profile.
- [x] The limine adapter generates a `limine.conf` with a default + fallback
      entry per selected kernel, installs the limine EFI binary, registers the
      UEFI entry, and defaults to the Primary Kernel.
- [x] The per-kernel entry rendering is a pure, unit-tested function.
- [x] A manifest row declares limine's loader path, `limine` package, esp-style,
      and ZFS support.
- [ ] The VM matrix boots a limine install end-to-end with a multi-kernel
      selection.
- [x] Tests cover the manifest row, package resolution (`limine`), the enum
      entry, and the `limine.conf` emission.

## Comments

- 2026-09-27 audit: 363f791, 17f15b0, 4f97379 (bootloader-limine.sh, manifest
  row, bats); 6019e48 adds tests/vm/profiles/single/limine.jsonc but no recorded
  VM boot — left unticked.
