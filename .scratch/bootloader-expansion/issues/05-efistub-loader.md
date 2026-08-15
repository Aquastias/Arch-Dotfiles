# 05 — efistub loader

**What to build:** Let an operator pick `efistub` and have the machine boot
directly through UEFI with no loader binary. The adapter registers one
`efibootmgr` entry per selected kernel plus a fallback entry, each pointing at the
ESP-mirrored kernel with `initrd=` and the root cmdline as load-options, and
orders BootOrder so the Primary Kernel boots by default. Because efistub has no
self-contained loader binary, the entry rendering lives in a **shared emit
helper** — keyed off the Bootloader Manifest's `esp_style` — that BOTH the primary
registration and the multi-disk secondary-ESP loop call, so each secondary ESP
gets the same per-kernel entries (kernel + initrd + cmdline) and the two can never
drift. Add the manifest row (loader path = the kernel image, no extra package
beyond `efibootmgr`, esp-style = efistub), the enum + Guided radiolist option, and
the VM matrix axis entry.

**Blocked by:** 01 — Bootloader Manifest foundation.

**Status:** ready-for-agent

- [ ] `efistub` is a legal `options.bootloader` value, offered in the Guided
      radiolist and accepted from a committed Host Profile.
- [ ] The efistub adapter registers a UEFI entry per selected kernel + a fallback
      entry, each carrying `initrd=` and the correct root cmdline (ZFS and
      non-ZFS); BootOrder defaults to the Primary Kernel.
- [ ] A single shared emit helper renders efistub entries and is called by both
      the primary registration and the secondary-ESP loop; on a multi-disk
      layout every secondary ESP carries the same per-kernel entries.
- [ ] A manifest row declares efistub's loader path (the kernel image), empty
      extra package set, esp-style, and ZFS support.
- [ ] The emit helper is a pure, unit-tested function covering multi-kernel and
      the load-options.
- [ ] The VM matrix boots an efistub install end-to-end with a multi-kernel
      selection.
