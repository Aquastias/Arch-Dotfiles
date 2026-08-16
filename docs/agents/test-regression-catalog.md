# Test regression catalog

The auditable "won't break my install" contract (ADR 0048/0078). Each row
is a class of bug that has broken — or would break — an install, mapped to
the test that now guards it and the tier that catches it:

- **always-on** — a bats test in `run.sh` (also in `--fast` if marked ✓).
- **VM-only** — only a real install+boot manifests it (`matrix.sh`, the VM
  Harness); no unprivileged oracle exists.

Run `run.sh --fast` before a real install; the always-on rows are the
confidence it gives. The VM-only rows are the residual you accept unless
you run `matrix.sh run` on a KVM box first (`/dev/kvm` is absent on the
current dev box, so VM rows do not run locally).

## Always-on (caught without a VM)

| Bug class | Guarding test | --fast |
| --- | --- | --- |
| `mkfs.fat` 'No such file' — unstable by-id symlink | `commons-part-name.bats` | |
| ERR trap trips on airootfs/copytoram boot | `live-medium.bats`, `wipe-probe.bats` | ✓* |
| Live-medium not excluded / stdout unclean in wipe | `wipe-live-medium.bats`, `wipe-prior-install-state.bats` | ✓ |
| `@blank` rollback wrongly no-ops over `/etc` | `impermanence-common.bats` | ✓ |
| `persist-<esc>.mount` `Where=` ≠ escaped unit name | `impermanence-common.bats`, `chroot/mount-unit-validate.bats` | ✓ |
| mkinitcpio HOOKS ordering (modprobe before root mount) | `chroot/initcpio-validate.bats` | ✓ |
| fstab syntax / field errors | `chroot/fstab-lint.bats` | ✓ |
| user units invalid (`systemd-analyze verify --user`) | `profiles/user-units-validate.bats` | ✓ |
| `jq` `getpath // empty` swallows `false` | `config/guided-state.bats` | ✓ |
| emitter merges Host Core twice | `config/guided-emit.bats` | ✓ |
| `print_summary` unbound var (ZFS-multi, single, non-ZFS) | `layout/layout-record.bats` | ✓ |
| leftover-pool predicate unbound var (single mode) | `zfs/pool-owners.bats` | ✓ |
| 2026-05-31: `linux-headers` pulled from mirror/archive | `zfs/zfs-module.bats` | ✓ |
| pool records bare `/dev/sdX` kernel name (reorder-fragile) | `zfs/zfs-pools.bats` | ✓ |
| archzfs version substring mismatch | `packages/iso-resolver.bats` | |
| any menu-reachable storage combo fails to assemble | `matrix/matrix-assembly.bats` (Tier-1 exhaustive) | |

\* the ERR-trap/live-medium files live at `tests/` root, outside the
`--fast` dir set; fold them in if pre-push must cover them.

## VM-only (irreducible — a real boot is the only oracle)

| Bug class | Guarding test (Tier 2) |
| --- | --- |
| busybox initramfs mounts only btrfs `@` subvol | VM boot-verify (`matrix.sh`) |
| firstboot service hang | `vm/seed-generator.bats` asserts the emit; hang itself is VM |
| multi-disk device rename (`/dev/sdX` reorder) breaks import | `vm/vm-reorder-disks.bats`, `vm/vm-pool-verify.bats` |
| `zpool export rpool` left pool imported on reboot | `vm/seed-generator.bats` (emit) + VM boot |
| encrypted-boot passphrase unlock over serial | Console Answerer (`matrix.sh`, ADR 0046) |
| `switch_root` / initramfs handoff | VM boot only |

## Known gap — the next validator worth writing

The Tier-1 exhaustive matrix (`matrix/matrix-assembly.bats`) runs every
storage combination through `validate_install_context`, but **not** through
the real artifact generators. So the `print_summary`-class unbound-var bug
(and fstab/mount-unit/initcpio generation) is checked only on the fixtures
in `layout-record.bats` / the validator tier, not across *every* cell —
notably not btrfs-multi, the exact shape ADR 0048 named.

**Proposed slice:** extend the Tier-1 cell loop to populate the layout
model per cell (as `layout-record.bats` does for its fixtures) and run
`print_summary` — plus `write_fstab` and the mount-unit / initcpio
generators — under `set -u`, asserting no `unbound variable` and feeding
the output to the existing `validators.bash` helpers. This converts the
unbound-var and generation-time classes from few-fixture to exhaustive,
unprivileged, always-on. It is a real slice (the loop currently only
validates config; the layout model must be built per cell), not a one-line
add — scoped here rather than rushed.
