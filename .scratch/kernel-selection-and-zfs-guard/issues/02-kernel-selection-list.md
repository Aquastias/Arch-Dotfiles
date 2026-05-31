Status: done

# Kernel Selection flavour-token list + primary-kernel bridge

## Parent

`.scratch/kernel-selection-and-zfs-guard/PRD.md` (ADR 0024).

## What to build

Make `options.kernel` a first-class Kernel Selection: it accepts a
single flavour token or a list of them. Tokens map through one table
to a kernel package plus matching headers — `lts`→`linux-lts`,
`default`→`linux`, `zen`→`linux-zen`, `hardened`→`linux-hardened`.
Every selected kernel is installed; `zfs-dkms` and `zfs-utils` are
added exactly once regardless of kernel count. An unknown token
aborts at config load.

The first token is the Primary Kernel. Install-state exposes the
scalar `KERNEL` (primary, for back-compat) alongside `KERNELS` (the
full list). The initramfs preset/fallback name and the bootloader
default boot entry are derived from the Primary Kernel token,
handling all four flavours. `mkinitcpio -P` keeps building every
installed kernel's preset; the custom fallback-preset injection and
bootloader default remain Primary-Kernel-only for now (interim,
until full multi-kernel preset wiring).

Scalar configs behave exactly as today. All hosts remain `lts`, so
the list path ships exercised only by tests.

## Acceptance criteria

- [x] `options.kernel` accepts a single token or a list; both
      normalise to an ordered list with primary = first.
- [x] `install_config_kernel` returns the primary; a new
      `install_config_kernels` returns the full list; an unknown
      token aborts at config load. Covered by `install-config.bats`.
- [x] The token map (`lts`/`default`/`zen`/`hardened` → kernel pkg +
      `-headers`) is a single table.
- [x] `collect_packages` emits each selected kernel and its headers,
      with `zfs-dkms` exactly once; `packages.bats` covers scalar
      `lts` (unchanged) and a two-token list (installs both).
- [x] Install-state carries scalar `KERNEL` (primary) and array
      `KERNELS`.
- [x] Initramfs preset and bootloader default are derived from the
      primary token, including `zen`/`hardened`.
- [x] `mkinitcpio -P` still builds every installed kernel's preset;
      custom fallback injection stays primary-only.
- [x] No host config hardcodes kernel packages; the installed kernel
      set is owned solely by `options.kernel`.

## Comments

Implemented via TDD. New `lib/kernel.sh` is the single token table
(`kernel_pkg`/`kernel_headers_pkg`/`kernel_is_valid_token`), staged into the
chroot alongside `install-state.sh` so host and chroot share one mapping.
- `install_config_kernels` (string|array→ordered list, default `lts`, aborts
  on unknown token) + `install_config_kernel` (primary = first); `kernel`
  dropped from the schema table and hand-written as a special.
- `collect_packages` loops the list via the table; `zfs-dkms`/`zfs-utils`
  once.
- install-state schema gains `KERNELS` (array); writer emits it; `KERNEL`
  stays the scalar primary.
- `initcpio.sh` + `bootloader-systemd-boot.sh` derive preset/vmlinuz/title
  from `kernel_pkg "$KERNEL"` (now covers `zen`/`hardened`); `mkinitcpio -P`
  unchanged; custom fallback stays primary-only.
Tests: new `kernel.bats` (4) + extensions to install-config/packages/
install-state; every install-state fixture gains the now-required `kernels`
field. Full suite 657/657 green; shellcheck clean. Host configs hardcode no
kernels (audit 81/81). CONTEXT.md already documents the terms.

## Blocked by

- `.scratch/kernel-selection-and-zfs-guard/issues/01-zfs-module-guard.md`
  (the guard lands first as the safety net before non-`lts`
  selection becomes possible).
