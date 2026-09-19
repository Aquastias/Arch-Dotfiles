# Pin target linux-lts to the archzfs LTS ceiling

Status: ready-for-agent

## Parent

`.scratch/archzfs-lts-ceiling-pin/PRD.md`

## What to build

The full end-to-end fix for the intermittent target DKMS `BIO_MAX_PAGES`
failure. Before pacstrap, resolve the archzfs LTS ceiling and pin the target's
`linux-lts` + `linux-lts-headers` to the newest patchlevel at or below it, so
`zfs-dkms` never builds against a kernel newer than the ZFS source supports.

New deep module `lib/packages/archzfs-kernel.sh` — the single owner of "which
`linux-lts` is archzfs-safe":

- `archzfs_lts_ceiling` → newest archzfs-supported `linux-lts` major.minor,
  parsed from `zfs-linux-lts-*` release assets (the 6.x lts series — distinct
  from the ISO resolver's `zfs-linux-*` default-kernel ceiling). Honors a
  forced-skew override env var. Test seam `_archzfs_fetch_lts_assets`, mirroring
  `_iso_resolver_fetch_archzfs_kernels`.
- `archzfs_pick_lts_version <ceiling> <candidates>` → pure: newest patchlevel at
  or below the ceiling, numeric comparison.
- `archzfs_resolve_lts_pin` → prints `linux-lts=<v> linux-lts-headers=<v>`, or
  nothing (degrade) when no ceiling resolves.

Wiring: `list.sh` swaps the bare `linux-lts` / `linux-lts-headers` tokens
(produced from the Kernel Selection table for the `lts` token) for the pinned
pair when `archzfs_resolve_lts_pin` returns one. When the mirror's `linux-lts`
exceeds the ceiling, pre-seed the exact version from the archive via the shared
helper (issue 01). Emit a `warn` naming the mirror version, the pinned version,
and the archzfs-ceiling reason when the kernel is held back; stay quiet when
mirror == ceiling. When the resolver degrades, keep the bare tokens — exactly
today's behavior. Scope: `lts` token only; non-lts flavours and the live-ISO
bootstrap path are untouched. The ZFS Module Guard is retained unchanged as the
backstop.

## Acceptance criteria

- [ ] `lib/packages/archzfs-kernel.sh` exists with the interface above; the LTS
      ceiling is parsed from `zfs-linux-lts-*`, not `zfs-linux-*`.
- [ ] When the mirror's `linux-lts` is at or below the ceiling, the collected
      package set is byte-identical to today (no-op pin, no warn).
- [ ] When the mirror exceeds the ceiling, the pinned pair replaces the bare
      tokens, the exact version is pre-seeded from the archive, and a held-back
      `warn` is logged naming both versions + the reason.
- [ ] When the archzfs lookup is unreachable or yields no ceiling, the package
      set keeps the bare tokens; the install proceeds unpinned (no hard-abort).
- [ ] `linux-lts` and `linux-lts-headers` are always pinned to the same version.
- [ ] A forced-skew override env var injects a fake-low ceiling.
- [ ] Non-lts flavours are never rewritten; the bootstrap path is unchanged.
- [ ] bats cover: `archzfs_pick_lts_version` (newest-≤-ceiling, equal-to-ceiling,
      none when all exceed, numeric ordering so `6.9 < 6.18`); `archzfs_lts_ceiling`
      parse via seam + override precedence; `archzfs_resolve_lts_pin` success and
      degradation; and `list.sh` wiring (pin replaces tokens on success, bare
      tokens survive on degrade, non-lts untouched).

## Blocked by

- `.scratch/archzfs-lts-ceiling-pin/issues/01-shared-archive-fetch-helper.md`
