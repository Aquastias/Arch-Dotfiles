# btrfs impermanence mirrors the per-path rollback model, not full-root-wipe

When btrfs becomes a root filesystem (ADR 0043), its impermanence reuses the
existing ZFS design — a **partial, per-path rollback** of a curated set of
subtrees (`etc/opt/root/srv/usrlocal`) plus a bind-mounted Persist overlay and a
PostTransaction re-snapshot — rather than the canonical btrfs "erase your
darlings" that wipes the *entire* root subvolume to a blank snapshot every boot.

## Considered Options

- **(a)** Classic full-root-wipe: one `@` subvol reset to `@blank` each boot,
  everything else persisted explicitly — rejected. Different semantics from the
  ZFS design (`/usr` must be persisted or re-baked differently), and it would
  mean maintaining two divergent impermanence architectures.
- **(b)** Mirror the ZFS per-path design — **chosen**. The impermanence code is
  already factored into an FS-agnostic layer (`impermanence-common.sh`: curated
  lists, the `persist_*` bind-mount verbs, the manifest, the PostTransaction
  re-snapshot pacman hook) and an FS-specific layer (dataset create/snapshot/
  rollback, the `zfs-rollback` initramfs hook, `After=zfs-mount.service`
  ordering). btrfs slots in by swapping **only** the FS-specific layer.

## Decisions

- The Rollback Datasets become **rollback subvolumes**; the same curated path
  list drives both.
- Three primitives go FS-conditional: create-subvol (`btrfs subvolume create`),
  snapshot-blank (`btrfs subvolume snapshot -r … @blank`), and the boot rollback
  (initramfs hook does `subvolume delete` + recreate from `@blank` per path,
  failing closed to an emergency shell if a `@blank` is missing — matching the
  ZFS hook's contract).
- Persist `.mount` units order `After=` the btrfs root mount instead of
  `zfs-mount.service`; the bind mounts themselves are already FS-agnostic.
- Everything else — `CURATED_FILES`/`CURATED_DIRS`, the move-vs-copy curated
  split, the bootstrap mounts, the manifest, the re-snapshot pacman hook — is
  reused verbatim.

## Consequences

- Impermanence is supported on ZFS **and** btrfs roots only; ext4/xfs (no
  snapshots) never offer it, and the Guided Installer enforces this.
