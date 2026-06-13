# tools/harden-boot.sh retrofit tool

Status: done

## Parent

PRD: Boot-path resilience on a small FAT ESP
(`.scratch/boot-path-resilience-small-esp/PRD.md`). See ADR 0038, ADR
0023.

## What to build

A bootloader-aware retrofit Tool that brings an already-installed
machine up to the hardened boot standard without a reinstall and without
repartitioning. Idempotent, with `--dry-run` to preview changes. On a
systemd-boot host it installs the hardened ESP Kernel Sync
(PostTransaction + PreTransaction) and the Stray Kernel warn hook from
the shared artifacts, reconciles per-vendor microcode and loader entries
to present files, and drops the fallback when the ESP is under ~1G. On a
GRUB host it pins the default to the Primary Kernel and re-runs the
microcode-aware config, plus the warn hook. It installs from the same
shared artifacts the installer uses (no duplicated copies).

## Acceptance criteria

- [ ] On a systemd-boot host: installs the hardened ESP Kernel Sync +
      preflight + warn hook, fixes microcode to the present vendor,
      reconciles loader entries, drops the fallback when ESP <~1G.
- [ ] On a GRUB host: pins the Primary Kernel default and applies
      per-vendor microcode + the warn hook.
- [ ] `--dry-run` reports the exact changes and mutates nothing.
- [ ] A second run is a no-op (idempotent).
- [ ] The tool never repartitions or resizes the ESP.
- [ ] The tool installs the same shared artifacts as the installer
      (single source, no drift).

## Blocked by

- Issue 02 (Per-vendor microcode)
- Issue 04 (ESP Kernel Sync PostTransaction hardening)
- Issue 05 (ESP Kernel Sync PreTransaction preflight)
- Issue 06 (Stray Kernel warn hook)
- Issue 07 (GRUB default-pin to Primary Kernel)
