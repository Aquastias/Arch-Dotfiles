# Ongoing archzfs LTS hold via IgnorePkg timer

Status: done

## Parent

`.scratch/archzfs-lts-ongoing-hold/PRD.md`

## What to build

A systemd timer on the installed system that holds `linux-lts` within the
archzfs ceiling on ongoing upgrades, plus a closest-available-compatible
fallback for the install pin.

- `lib/boot/lts-hold.sh`: toggles a marked
  `IgnorePkg = linux-lts linux-lts-headers  # archzfs-lts-hold` line in
  `/etc/pacman.conf` based on the archzfs ceiling vs the newest available
  `linux-lts` (throwaway db sync). Holds at installed version; fail-safe offline;
  never touches an operator's own `IgnorePkg`.
- `archzfs-lts-hold.timer`/`.service` installed + enabled for ZFS hosts that
  selected `lts`; runtime + `archzfs-kernel.sh` + `archive.sh` staged to
  `/usr/local/lib/archzfs/`.
- Install pin gains `archzfs_pin_candidates` + candidate-trying build so a
  vanished exact version falls back to the closest available compatible one.

## Acceptance criteria

- [x] During a skew, `pacman -Syu` holds `linux-lts`/headers and upgrades
      everything else (non-blocking).
- [x] Hold clears automatically when archzfs catches up.
- [x] Timer never reinstalls the kernel; offline → hold state unchanged.
- [x] An operator's own `IgnorePkg` line survives set/clear.
- [x] Install pin falls back to the newest archive `linux-lts` <= ceiling when
      the exact version can't be fetched.
- [x] bats cover the IgnorePkg editor, `archzfs_pin_candidates`, and the
      build-repo candidate fallback.
- [ ] Verified on the existing `arch-combined` VM (forced low ceiling → held;
      real ceiling → cleared).

## Blocked by

- None - can start immediately

## Comments

- 2026-09-27 audit: 55a0be4 (lts-hold timer + boot/lts-hold.bats), 120b1ca (db
  sync writable). VM verification not recorded — left unticked.
