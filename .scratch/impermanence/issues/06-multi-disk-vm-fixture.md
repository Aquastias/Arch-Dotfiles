Status: ready-for-agent

# Multi-disk VM fixture

## Parent

`.scratch/impermanence/PRD.md`

## What to build

Add a VM integration fixture that installs an impermanent system on a multi-disk mirrored OS pool. Confirms the multi-disk layout module and the impermanence module compose correctly, that the Rollback Hook handles the mirrored pool in initramfs, and that the ESP mirror hook coexists with the pacman resnapshot hook.

Scope:

- New fixture `tests/vm/testing-multi-os-mirror-impermanent.sh` following the established VM fixture pattern (`tests/vm/_harness.sh`, the existing `testing-multi-os-mirror.sh` as the closest sibling).
- Topology: `mode=multi`, `os_pool.topology=mirror`, two virtual disks for the OS pool, no storage groups. Impermanence enabled with default `dataset` and `mount`.
- The multi-disk layout module must invoke the impermanence dataset-creation helper exactly like the single-disk module does. If this slice exposes that the helper isn't yet wired into the multi-disk layout, do that wiring as part of this slice.
- Post-install assertions (in addition to the single-disk assertions from slice 1):
  - All Rollback Datasets exist on the mirrored pool with `@blank` snapshots
  - `/persist` is mounted
  - SSH host key is identical before and after reboot
  - An unpersisted edit vanishes after reboot
  - The ESP mirror hook is still installed and functions (kernel update propagates to all ESPs); the impermanence install did not interfere
  - Pacman resnapshot hook is installed and a test package install survives reboot
- No new bats unit tests; the chroot module's behavior on multi-disk is identical to single-disk except for which layout module invokes it, and that wiring is covered by the VM fixture.

## Acceptance criteria

- [ ] `tests/vm/testing-multi-os-mirror-impermanent.sh` provisions a mirrored OS pool with impermanence enabled
- [ ] Multi-disk layout module invokes the impermanence dataset-creation helper
- [ ] All Rollback Datasets exist on the mirrored pool with `@blank` post-install
- [ ] SSH host key persists across reboot on the multi-disk install
- [ ] Unpersisted edit to `/etc` disappears after reboot
- [ ] ESP mirror hook and pacman resnapshot hook coexist (kernel update mirrors ESPs; test package install survives reboot)

## Blocked by

- `.scratch/impermanence/issues/01-core-impermanence.md`
- `.scratch/impermanence/issues/03-pacman-resnapshot-hook.md`
