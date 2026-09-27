# ADR 0144: Persist Mount units live in /usr/lib; /root is not rolled back

## Status
Accepted — implemented (`.installer/lib/impermanence-common.sh`,
`lib/chroot/impermanence.sh`, `tools/impermanence.sh`). Amends ADR 0008 (the
Payload layer and the Rollback Dataset list) and ADR 0044 (the btrfs subvol
list, which is derived from the same list).

## Context
A VM with impermanence enabled (`arch-combined-sops-impermanence`) showed two
Persist Mounts that never mounted at boot:

- **Persist Extensions.** ADR 0008 put their units and `wants` links under
  `/persist/etc/systemd/system`, and a bootstrap bind exposes that directory
  over `/etc/systemd/system`. That bind is itself a `local-fs.target` mount.
  PID 1 plans the boot transaction before the bind exists, so it only sees the
  rolled-back `/etc/systemd/system` from `@blank`. The result is that an
  extension unit, even when enabled, is never started at boot. `tools/
  impermanence.sh add` also never linked the unit into a target. The
  installer already works around the same limit for service enablements by
  mirroring them onto `/usr/lib` (`_impermanence_relocate_enablements`).
- **`/root`.** `/root` was both a Rollback Dataset (`rpool/ROOT/root`, or the
  `@root` subvol on btrfs) and a Curated Persist Default. Both mounts target
  `/root`, so both are named `root.mount`. On ZFS the generated unit from
  `zfs-mount-generator` takes priority over the curated bind in `/usr/lib`, so
  `/root` rolled back every boot and `/persist/root` was never mounted.
  Everything under `/root` was lost, including `/root/quarantine`, which made
  `clamav-clamonacc` fail.

## Decision
- **All Persist Mount units and their `local-fs.target.wants` links are
  written to `/usr/lib/systemd/system`**, extensions as well as curated
  defaults. `/usr` is on the root dataset, is never rolled back, and is
  visible from the moment PID 1 starts. The extension tmpfiles entries stay
  on `/persist/etc/tmpfiles.d`, because `systemd-tmpfiles-setup` runs after
  `local-fs.target`, when the bind is already in place. `persist_unapply`
  also removes old units and links left under `/persist/etc/systemd/system`.
  `status` uses the curated manifest to tell curated units from extensions.
- **`/root` is removed from the Rollback Datasets.** It stays a Curated
  Persist Default, so it now lives on the root dataset with the curated bind
  on top, and there is only one `root.mount`. The rolled-back set is `/etc`,
  `/opt`, `/srv` and `/usr/local`.
- **`systemd-machine-id-commit.service` is skipped when `/etc/machine-id` is a
  persist bind.** A drop-in in `/usr/lib` adds the condition
  `ConditionPathIsMountPoint=!/etc/machine-id`. The ID is already frozen in
  `@blank`, so there is nothing to commit, and the stock unit failed on every
  boot.

## Consequences
- ADR 0008 rejected putting "all persist config in `/usr/lib`" because the
  config would then be baked into a snapshot. That concern does not apply:
  `/usr` is not a Rollback Dataset, so adding an extension needs no
  re-snapshot. Extension units now sit next to package-owned units in
  `/usr/lib`, which is the same trade-off the curated units already make.
- Hosts installed before this change keep their broken extension units until
  someone runs `impermanence.sh remove` and then `add` for each path. Their
  `/root` stays a rolled-back dataset until the host is reinstalled, because
  impermanence is set up at install time only (ADR 0008).
- Tools that edit `/etc` on an impermanence guest must re-take `@blank`, or
  the edit is lost on reboot. `vm-agent` runs
  `/usr/lib/impermanence/resnapshot.sh` after it changes autologin.
