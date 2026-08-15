# 01 — Bootloader Manifest foundation

**What to build:** A single source of truth for per-loader metadata, so adding a
bootloader later is one row instead of a new `if/elif` branch in three files.
Introduce the **Bootloader Manifest** — a pure token table keying each
`options.bootloader` value to its EFI loader path, package set, ESP-entry style,
and ZFS-support flag — and migrate the existing hardcoded `if grub/else systemd`
chains (the secondary-ESP loader path in the chroot orchestrator, the bootloader
package in the resolver, and the bootloader package in the package list) to read
from it. Wire `options.bootloader` to a closed-set validation at profile load,
sourced from the `menu_enum_options` enum as the shared SSOT, so an unknown
loader aborts with its path. This ticket keeps the legal set at `systemd-boot`
and `grub` only — no new loaders, no behaviour change — so it lands green as a
pure prefactor.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] A new Bootloader Manifest lib exposes, per loader, the EFI loader path,
      package set, ESP-entry style, and a ZFS-support flag, as pure functions.
- [ ] The secondary-ESP UEFI entry path in the orchestrator reads the loader
      path from the manifest instead of branching on the loader name.
- [ ] The package resolver and the package list both derive bootloader packages
      from the manifest instead of a `grub`-only branch.
- [ ] `options.bootloader` is validated at profile load against the
      `menu_enum_options options.bootloader` enum (the shared SSOT); an unknown
      value aborts with its dotted path.
- [ ] The legal set is unchanged (`systemd-boot`, `grub`); existing installs and
      tests behave identically.
- [ ] New bats over the manifest functions assert each loader's path, packages,
      esp-style, and zfs flag (prior art: `packages/kernel.bats`,
      `tests/grub-common.bats`); `menu-enum` and validation tests cover the
      closed-set rejection.
