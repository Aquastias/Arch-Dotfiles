# Picker: template-pinned os_pool layout

Status: done

See ADR 0029. Lets an Install Template pin OS-pool layout so the
Pre-Install Picker skips its mode prompt and honors the pinned
topology, while disks stay operator-picked.

## Motivation
Topology is a property of fixed hardware; re-prompting it every
reinstall is the wrong friction (ADR-0010's own argument for
bootloader/DE). `vm/arch-secure` carried dead `mode`/`os_pool.disks`
fields the picker overrode — a drift hazard.

## Resolved design (grill session)
- Pin trigger: `.mode` present in the merged template.
- `single` → 1 disk. `multi` → requires `os_pool.topology` (absent =
  error). Topology passthrough + min-disk count check: mirror/stripe
  ≥2, raidz1 ≥3, raidz2 ≥4, none ≥2.
- Disks always picked; template disks overridden.
- `storage_groups[]` / `data_pools[]` out of scope (verbatim as
  today).
- Unpinned = ADR-0010 behavior unchanged.
- Pin expressed in config vocab (`mode` + `os_pool.topology`).

## Out of scope
- Expanding the unpinned prompt beyond single/mirror/raidz.
- Pinning `storage_groups[]` / `data_pools[]` disks.

## Issues
- `issues/01-honor-pinned-os-pool-layout.md`
