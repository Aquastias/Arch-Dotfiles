# Filesystem Adapter axis — generalize the installer beyond ZFS

The installer reserves a **Filesystem Adapter** seam so it can later support
btrfs, ext4, and xfs alongside ZFS *without a schema migration*. A top-level
`filesystem` discriminator (default `zfs`) selects the adapter; the current
mode-keyed Layout Module (`lib/layout/<mode>.sh`) becomes the ZFS adapter and
dispatch generalizes to a filesystem-keyed seam. Only ZFS is implemented now —
the discriminator, an additive `options.encryption_method`, and the fs-keyed
dispatch are landed up front because the closed-schema + accessors + VM-seed
lockstep is the expensive thing to migrate later.

## Considered Options

- **(a)** Stay ZFS-only; add filesystems later with a full schema migration —
  rejected (the migration is the costly, lockstep-breaking part).
- **(b)** Reserve the seam + schema now, build ZFS only — **chosen**.
- **(c)** Implement btrfs/ext4/xfs/LUKS now — rejected (huge scope, not needed
  yet).

## Schema decisions (minimal, additive — no migration now or later for ZFS)

- Top-level `filesystem` scalar, default `zfs`. Existing ZFS layout fields stay
  flat at root; future filesystems add their own namespaced fields, gated by a
  `lib/config/validation.sh` contract check ("fields set must match
  `filesystem`"). The closed-schema validator just enumerates paths; the
  discriminator semantics live in the contract seam, as elsewhere.
- `options.encryption` stays a bool (= enabled). `options.encryption_method`
  added (`native` | `luks`), default derived from `filesystem` (zfs→native,
  else→luks). Purely additive — the existing bool reader is untouched.

## Consequences

- The Guided Installer's Disks section is **filesystem-first**: pick filesystem,
  then FS-specific authoring. Only ZFS is active; btrfs/ext4/xfs are
  reserved/disabled menu entries.
- Encryption is FS-aware (ZFS→native AES default; non-ZFS→LUKS).
- Impermanence and the Bootloader Adapter's `root=` are filesystem-conditional;
  ext4/xfs offer no Impermanence (no native snapshots).
- Generalizing dispatch to `lib/layout/<fs>/<mode>.sh` will relocate the ZFS
  layout files into a `zfs/` subdir — the BASH_SOURCE root-sibling foldering
  hazard; handled when filesystem #2 lands.
- Independent of ADR 0039; the Guided Installer simply branches its Disks step on
  the `filesystem` discriminator.
