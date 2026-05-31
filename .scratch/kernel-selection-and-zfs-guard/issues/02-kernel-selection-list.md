Status: ready-for-agent

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

- [ ] `options.kernel` accepts a single token or a list; both
      normalise to an ordered list with primary = first.
- [ ] `install_config_kernel` returns the primary; a new
      `install_config_kernels` returns the full list; an unknown
      token aborts at config load. Covered by `install-config.bats`.
- [ ] The token map (`lts`/`default`/`zen`/`hardened` → kernel pkg +
      `-headers`) is a single table.
- [ ] `collect_packages` emits each selected kernel and its headers,
      with `zfs-dkms` exactly once; `packages.bats` covers scalar
      `lts` (unchanged) and a two-token list (installs both).
- [ ] Install-state carries scalar `KERNEL` (primary) and array
      `KERNELS`.
- [ ] Initramfs preset and bootloader default are derived from the
      primary token, including `zen`/`hardened`.
- [ ] `mkinitcpio -P` still builds every installed kernel's preset;
      custom fallback injection stays primary-only.
- [ ] No host config hardcodes kernel packages; the installed kernel
      set is owned solely by `options.kernel`.

## Blocked by

- `.scratch/kernel-selection-and-zfs-guard/issues/01-zfs-module-guard.md`
  (the guard lands first as the safety net before non-`lts`
  selection becomes possible).
