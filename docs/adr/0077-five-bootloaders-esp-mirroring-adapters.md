# Five bootloaders as ESP-mirroring adapters over one manifest

Status: accepted (extends ADR 0038's ESP Kernel Sync; generalizes the Bootloader
Module / Bootloader Adapter seam)

`options.bootloader` grows from `{systemd-boot, grub}` to a **closed set** of
five — `systemd-boot`, `grub`, `efistub`, `limine`, `refind` (default
`systemd-boot`) — validated at profile load against
`menu_enum_options options.bootloader` (the existing enum SSOT, now shared by
the Guided menu and the schema), so an unknown loader aborts with its path like
any other closed-schema violation (ADR 0036). The four non-grub loaders are
**ESP-mirroring loaders**: they boot a ZFS root by reading the kernel the ESP
Kernel Sync (ADR 0038) already mirrors onto the FAT32 ESP, so ZFS parity is
free — no gating. `grub` stays the single native-ZFS special case that reads the
pool directly and needs no ESP mirror. The mirroring loaders differ only in
**entry format** — systemd loader entry, `efibootmgr` load-options,
`limine.conf`, `refind_linux.conf` — and loader-binary path. `efistub` is a
direct-UEFI boot *method*, not a loader binary: it emits one `efibootmgr` entry
per kernel + fallback, and its loader path is the kernel image itself.

The per-loader EFI loader path, package set, and ESP-entry style move into one
pure token table, `lib/boot/bootloaders.sh` (the **Bootloader Manifest**),
sourced host-side by the package resolver / list and staged into the chroot for
the orchestrator. This replaces the hardcoded `if grub/else systemd` chains in
`configure.sh` (secondary-ESP UEFI loader path), `resolver.sh`, and `list.sh`
(bootloader packages), so adding a sixth loader is one adapter file + one
manifest row, never a new branch.

The Guided Installer also gains an explicit **Abort** action row (fourth beside
Proceed / Save / Export), Esc-equivalent: it quits the menu cleanly so
`install.sh` skips the back-end. Abort is **pre-destructive only** — it fires
before any disk is touched, so there is nothing to roll back.

## Considered options

- **Gate efistub/limine/refind to non-ZFS roots** — rejected: the premise
  (weak ZFS support) is false here. ESP Kernel Sync already mirrors kernels onto
  the FAT ESP for systemd-boot, and any ESP-reading loader inherits that, so all
  four boot ZFS by construction. Gating would add a support matrix for no gain.
- **efistub via UKI** (one signed `.efi` bundling kernel+initrd+cmdline) —
  deferred: needs a mkinitcpio UKI preset and syncing the UKI instead of
  vmlinuz/initrd. The raw kernel + `initrd=` + cmdline path reuses ESP Kernel
  Sync untouched. UKI/secure-boot is a future ADR.
- **Keep the `if/elif` chains** — rejected: two loaders tolerated three
  branches (path, packages, secondary-ESP entry); five would triple them across
  three files with no shared source of truth.
- **Mid-install (destructive-phase) Abort with rollback** — rejected: unwinding
  wiped disks and half-created pools is a large, risky feature. Abort stays
  pre-destructive; the typed-`INSTALL` gate remains the last consent point
  before anything is written.
- **A separate ADR for Abort** — rejected: the action row alone is trivially
  reversible and unsurprising; only the deliberate *no* to rollback is worth
  recording, and it lives here as one line.

## Consequences

- `menu_enum_options options.bootloader` becomes the enum SSOT for **both** the
  Guided menu and profile-load validation; the two can no longer drift on the
  legal loader set.
- `lib/boot/bootloaders.sh` is a new host+chroot shared lib; it joins the set of
  files staged into the chroot alongside `kernel.sh` / `esp-kernel-sync.sh`.
- ESP Kernel Sync is no longer "systemd-boot-only" — it installs for every
  ESP-mirroring loader and is skipped only under `grub`.
- Three new Bootloader Adapters (`efistub`, `limine`, `refind`) each own their
  entry format; the secondary-ESP UEFI entry in `configure.sh` now reads the
  loader path from the manifest instead of branching on the loader name.
