# ADR 0029: Picker honors optional template-pinned os_pool layout

## Status
Accepted (implementation pending — tracked in
`.scratch/picker-template-pinned-layout/`). Amends ADR-0010, which
made disk mode an always-prompted, install-time choice.

## Context
ADR-0010 split the picker's two unknowns — host + disks — from the
machine properties in the Install Template, and made install *mode*
(single/mirror/raidz) an always-prompted choice. But topology is
arguably a property of the machine: a given box has a fixed disk
layout you reinstall the same way every time. The `vm/arch-secure`
template exposed the gap — it carried `mode`/`os_pool.disks` to
document "2-disk mirror," yet the picker overrode both, so the fields
were dead weight and a drift hazard (they look like `install.jsonc`
but do nothing).

Two facts stay genuinely install-time and remain prompted: which
physical disks (by-id paths are machine-specific and the live medium
must be filtered out).

## Decision
A template MAY pin OS-pool layout; the picker honors it.

- Pin trigger: `.mode` present in the merged template.
  - `mode: "single"` → pinned single (exactly 1 disk picked).
  - `mode: "multi"` → requires `os_pool.topology`; absent is a
    template error ("multi pin requires os_pool.topology").
    Redundancy is never guessed.
- Pinned multi uses topology passthrough: the picker writes
  `os_pool.topology` verbatim and validates the picked disk count
  against a min-disk table — mirror/stripe ≥2, raidz1 ≥3, raidz2 ≥4,
  none ≥2. `none` rides through to `install.sh`'s existing leftover
  flow (pick the OS disk, fold the rest into dpool).
- Disks are ALWAYS picked. Any `disk`/`os_pool.disks` in a template
  are overridden. Pinning only removes the mode prompt.
- `storage_groups[]` / `data_pools[]` stay hand-authored — out of
  picker scope, passed through verbatim as today.
- Unpinned (`.mode` absent) behaves exactly as ADR-0010: prompt mode
  (single/mirror/raidz), then disks.

The pin is expressed in config vocabulary (`mode` +
`os_pool.topology`), keeping the template "same shape as
`install.jsonc`" rather than adding a picker-only field.

## Considered alternatives
**Dedicated `picker.mode` field (picker vocab).** A clearly
picker-only key, stripped before writing `install.jsonc` — crispest
separation, reuses the existing 3-token validator unchanged. Rejected
to keep templates one shape (`install.jsonc`) and to allow pinning
stripe/raidz2/none, which the 3-token assembler can't express.

**Restrict pins to single/mirror/raidz1.** Smallest change, but adds
no expressivity over merely skipping the prompt; stripe/raidz2 hosts
stay un-pickable.

**Auto-suggest topology from disk count.** Convenient, but silently
picks a redundancy/failure-domain policy (4 disks: raidz1 vs raidz2)
that belongs explicit in a committed template.

**Keep mode always-prompted; strip dead fields only.** The original
cleanup. Rejected because topology really is a machine property for
fixed hardware, and re-deciding it every reinstall is the wrong
friction — the same argument ADR-0010 used for bootloader/DE.

## Consequences
- The picker gains a pinned path that bypasses its single/mirror/
  raidz token machinery; `picker_validate_layout` grows a topology→
  min-disk table covering stripe/raidz2/none.
- `[e]dit` on the review screen re-enters at disks only when pinned
  (mode stays pinned); the picker prints a one-line notice naming the
  pinned mode/topology before the disk pick.
- Templates may legitimately carry `mode` + `os_pool.topology`;
  REFERENCE's "layout is never in the template" rule narrows to
  "*disks* are never in the template."
- `vm/arch-secure` becomes a real pinned-mirror host: `mode: "multi"`
  + `os_pool.topology: "mirror"`, disks dropped.
- Until implemented, the picker still prompts and overrides; the
  pinned fields in a committed template are inert (documented here).
