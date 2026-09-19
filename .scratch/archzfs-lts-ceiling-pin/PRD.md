# PRD: Pin target linux-lts to the archzfs LTS ceiling

Status: ready-for-agent

Anchored by [[ADR 0137]] (Target linux-lts pinned to the archzfs LTS ceiling),
extending [[ADR 0023]] (archzfs-Compatible ISO) and [[ADR 0024]] (Kernel
Selection + ZFS Module Guard). Introduces the **archzfs LTS Ceiling** term
(CONTEXT.md).

## Problem Statement

Recreating the `arch-combined` VM sometimes aborts partway through the install:

```
[ERROR] No ZFS kernel module was built for: linux-lts.
  archzfs could not build zfs-dkms against this/these kernel(s)...
[install.sh] aborted at line 378.
```

The underlying compile failure in the target:

```
vdev_disk.c:688: error: 'BIO_MAX_PAGES' undeclared
make[6]: *** [os/linux/zfs/vdev_disk.o] Error 1
```

with `linux-lts 6.18.52-1`, `zfs-dkms 2.4.4-1`, `zfs-utils 2.4.4-3`.

The failure is intermittent — it does not appear most of the time. The operator
needs it to stop happening, and the fix must not change anything for the
installs that already succeed.

## Solution

The target install pulls `zfs-dkms` and DKMS-builds ZFS against whatever
`linux-lts` pacstrap installs from the always-current Arch core mirror.
archzfs's ZFS source lags on its own release cadence. When the mirror's
`linux-lts` minor version outruns what the ZFS source supports, the DKMS build
fails to compile. It is a version race: most installs catch a compatible
moment; occasionally the kernel has jumped ahead. The ZFS Module Guard catches
the bad build but only after pacstrap, and only as a report — the target kernel
was never constrained.

ADR 0023 already treats archzfs's prebuilt-kernel list as a reliable proxy for
"the current ZFS source compiles against this kernel", and uses it to pick the
live-ISO kernel. This PRD extends that proxy to the *target*: before pacstrap,
pin `linux-lts` (and its headers) to the newest patchlevel at or below the
archzfs LTS ceiling. When the mirror already matches the ceiling the pin is a
no-op and the happy path is byte-identical. When the mirror has moved ahead,
the exact compatible version is pre-seeded from `archive.archlinux.org`. If the
archzfs lookup is unreachable, the install proceeds unpinned exactly as today
and the ZFS Module Guard remains the backstop.

## User Stories

1. As an operator recreating the `arch-combined` VM, I want the install to
   complete even when the mirror's `linux-lts` has outrun archzfs, so that the
   intermittent DKMS `BIO_MAX_PAGES` failure stops aborting my installs.
2. As an operator, I want installs that already succeed today to behave
   identically, so that the fix introduces no new risk on the happy path.
3. As an operator, I want the installer to pin `linux-lts` to the newest
   archzfs-safe patchlevel, so that I still get the freshest kernel that ZFS
   can actually build against.
4. As an operator, I want the target's `linux-lts` and `linux-lts-headers`
   pinned to the same version, so that DKMS never builds against mismatched
   headers.
5. As an operator on a machine whose mirror `linux-lts` exceeds the ceiling, I
   want the exact compatible version fetched from the Arch Linux Archive, so
   that pacstrap can install a kernel the mirror no longer carries.
6. As an operator reading `install.log`, I want a clear `warn` when the kernel
   is held back — naming the mirror version, the pinned version, and the
   archzfs-ceiling reason — so that a held-back kernel is never a silent
   surprise.
7. As an operator on the happy path (mirror == ceiling), I want no extra noise,
   so that a normal install log looks unchanged.
8. As an operator whose network cannot reach the archzfs lookup, I want the
   install to proceed unpinned rather than hard-abort, so that a flaky lookup
   never breaks an install that would otherwise succeed.
9. As an operator, I want the ZFS Module Guard to remain the backstop for the
   degraded (unpinned) path and for non-lts flavours, so that a genuinely
   unbuildable kernel is still caught early and explicitly.
10. As an operator selecting a non-lts kernel flavour, I want its behavior
    unchanged (unpinned + guarded), so that this fix stays scoped to the `lts`
    token it targets.
11. As an operator whose live-ISO/bootstrap path already works, I want it
    untouched, so that the ADR-0023-protected bootstrap keeps its own ceiling.
12. As a maintainer, I want the "which linux-lts is archzfs-safe" knowledge in
    one owner module, so that the ISO ceiling and the LTS ceiling stay cleanly
    separate and independently testable.
13. As a maintainer, I want the archive-fetch logic shared between the
    bootstrap headers path and the new pin path, so that there is one
    implementation to reason about.
14. As a maintainer, I want a forced-skew seam, so that the VM acceptance stays
    a real regression test after archzfs catches up and the natural skew
    disappears.
15. As a maintainer, I want deterministic bats coverage of the ceiling parse,
    the pin selection, and the graceful degradation, so that the regression
    surface is locked without depending on a live race.
16. As a maintainer, I want a full `arch-combined` VM recreation to complete
    successfully as the acceptance gate, so that the fix is proven to change
    what pacstrap installs, not just what a unit test asserts.

## Implementation Decisions

- **New deep module `lib/packages/archzfs-kernel.sh`** — the single source of
  "which `linux-lts` is archzfs-safe". Keeps `lib/packages/iso-resolver.sh`
  ISO-scoped. Public interface:
  - `archzfs_lts_ceiling` → newest archzfs-supported `linux-lts` major.minor,
    parsed from `zfs-linux-lts-*` release assets. Honors a forced-skew override
    env var when set. Non-zero / empty output when the lookup fails.
  - `archzfs_pick_lts_version <ceiling> <candidates>` → **pure**: given a
    ceiling major.minor and a set of candidate `linux-lts` versions, print the
    newest patchlevel at or below the ceiling.
  - `archzfs_resolve_lts_pin` → orchestration: resolve the ceiling, determine
    the pinnable version, and print `linux-lts=<v> linux-lts-headers=<v>`, or
    print nothing (degrade) when no ceiling is resolvable.
  - Test seam `_archzfs_fetch_lts_assets` (network fetch), mirroring the
    `_iso_resolver_fetch_archzfs_kernels` seam pattern.
- **Ceiling granularity: major.minor, patch-tolerant.** Pin to the newest
  patchlevel of the archzfs-supported major.minor, matching the rule the ISO
  resolver already uses. The `BIO_MAX_PAGES` break was a minor-version jump,
  which a major.minor ceiling caps.
- **The LTS ceiling is distinct from the ISO ceiling.** The ISO resolver parses
  `zfs-linux-*` (the default kernel, 7.x); the LTS lookup parses
  `zfs-linux-lts-*` (the 6.x lts series). Reusing the ISO lookup verbatim would
  pin the wrong series.
- **Extract a shared archive-fetch helper.** Pull the
  `archive.archlinux.org` package-download logic currently inside
  `lib/zfs/module.sh` into a small shared primitive (given a package name +
  exact version, fetch + install from the archive). Both the bootstrap headers
  path and the new pin path call it. One implementation, DRY.
- **Pin injection, host-side, before pacstrap.** The pin resolves before the
  package set is finalized; the bare `linux-lts` / `linux-lts-headers` tokens
  produced from the Kernel Selection table are replaced with the pinned
  `name=version` pair for the `lts` token when `archzfs_resolve_lts_pin`
  returns one. If the mirror's `linux-lts` exceeds the ceiling, the exact
  version is pre-seeded from the archive so pacstrap resolves it.
- **Graceful degradation.** When `archzfs_resolve_lts_pin` returns empty
  (lookup unreachable or no ceiling), the package set keeps the bare tokens —
  exactly today's behavior. Never hard-abort on a lookup failure.
- **Scope: `lts` token only, target only.** Other flavours stay unpinned and
  guarded, unchanged. The live-ISO/bootstrap path is untouched (already
  ADR-0023-safe).
- **Operator visibility.** When the pin holds `linux-lts` back, emit a `warn`
  naming the mirror version, the pinned version, and the archzfs-ceiling
  reason. When mirror == ceiling, stay silent (info-level at most).
- **The ZFS Module Guard is retained unchanged** as the backstop for the
  degraded path and non-lts flavours.

## Testing Decisions

Good tests here assert **external behavior** through the module's public
interface and its seams, not internal wiring. They must be deterministic — the
real bug is a live race, so tests inject the ceiling and candidate sets rather
than hitting the network. Prior art: `.installer/tests/packages/resolver.bats`
(seam-overridden archzfs/releases lookups) and
`.installer/tests/zfs/zfs-module.bats` (DKMS path with `ZFS_SRC_DIR` /
`ZFS_MODULES_DIR` overrides).

Modules covered by bats:

- **`lib/packages/archzfs-kernel.sh`**
  - `archzfs_pick_lts_version` (pure): newest patch ≤ ceiling; equal-to-ceiling
    picks; nothing when all candidates exceed the ceiling; numeric (not
    lexical) comparison so `6.9 < 6.18` and a `6.180` cannot slip under a
    `6.18` cap.
  - `archzfs_lts_ceiling` via `_archzfs_fetch_lts_assets` seam: parses
    `zfs-linux-lts-*` asset names to the newest major.minor; forced-skew
    override env var wins when set.
  - `archzfs_resolve_lts_pin`: prints the `name=version` pair on success;
    prints nothing (degrade) when the ceiling lookup fails or yields no
    candidate.
- **Shared archive-fetch helper**: version-string construction (kernel-release
  → pacman package version), archive URL layout, and the mirror-first /
  archive-fallback ordering.
- **Pin wiring in `list.sh`**: the pinned pair replaces the bare
  `linux-lts` / `linux-lts-headers` tokens in the collected package set when a
  pin resolves; the bare tokens survive unchanged when the resolver degrades;
  non-lts flavours are never rewritten.

Forced-skew seam: an env var that injects a fake-low ceiling, so the VM gate
exercises the pin path even after archzfs catches up.

VM acceptance gate: a full `arch-combined` VM recreation must complete the
install successfully. The skew is live today (mirror `linux-lts` 6.18.52 >
archzfs ceiling), so a recreation now genuinely exercises the pin.

## Out of Scope

- Any change to the live-ISO / `01-bootstrap-zfs.sh` path or its ceiling
  (already governed by ADR 0023).
- Pinning non-lts flavours (`default`, `zen`, `hardened`). They stay unpinned
  and guarded.
- Switching the target from `zfs-dkms` to a prebuilt `zfs-linux-lts` (rejected
  in ADR 0137 — would reverse ADR 0023's DKMS-everywhere stance).
- Auto-remediation / downgrade-and-retry after a failed DKMS build (rejected in
  ADR 0024 and ADR 0137).
- Changing the ZFS Module Guard's behavior or message beyond keeping it as the
  backstop.

## Further Notes

- The pin is a no-op whenever the mirror's `linux-lts` is already at or below
  the ceiling — this is the property that keeps the happy path byte-identical,
  and it is the operator's core constraint.
- The two ceilings (ISO `zfs-linux-*` vs target `zfs-linux-lts-*`) are resolved
  independently and can differ; conflating them is the main correctness trap.
