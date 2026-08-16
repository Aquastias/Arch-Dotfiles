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
| `mkfs.fat` 'No such file' — unstable by-id symlink | `commons-part-name.bats` | ✓ |
| ERR trap trips on airootfs/copytoram boot | `live-medium.bats`, `wipe-probe.bats` | ✓ |
| Live-medium not excluded / stdout unclean in wipe | `wipe-live-medium.bats`, `wipe-prior-install-state.bats` | ✓ |
| `@blank` rollback wrongly no-ops over `/etc` | `impermanence-common.bats` | ✓ |
| `persist-<esc>.mount` `Where=` ≠ escaped unit name | `impermanence-common.bats`, `chroot/mount-unit-validate.bats` | ✓ |
| mkinitcpio HOOKS ordering (modprobe before root mount) | `chroot/initcpio-validate.bats` | ✓ |
| fstab syntax / field errors | `chroot/fstab-lint.bats` | ✓ |
| user units invalid (`systemd-analyze verify --user`) | `profiles/user-units-validate.bats` | ✓ |
| `jq` `getpath // empty` swallows `false` | `config/guided-state.bats` | ✓ |
| emitter merges Host Core twice | `config/guided-emit.bats` | ✓ |
| `print_summary` unbound var — every fs×topology cell, `set -u` | `matrix/print-summary-setu.bats` (exhaustive) + `layout/layout-record.bats` (accessors) | |
| leftover-pool predicate unbound var (single mode) | `zfs/pool-owners.bats` | ✓ |
| 2026-05-31: `linux-headers` pulled from mirror/archive | `zfs/zfs-module.bats` | ✓ |
| pool records bare `/dev/sdX` kernel name (reorder-fragile) | `zfs/zfs-pools.bats` | ✓ |
| archzfs version substring mismatch | `packages/iso-resolver.bats` | |
| any menu-reachable storage combo fails to assemble | `matrix/matrix-assembly.bats` (Tier-1 exhaustive) | |

The root-level guards (`live-medium`, `wipe-probe`, `wipe-live-medium`,
`wipe-prior-install-state`, `commons-part-name`) are folded into `--fast`
via `run.sh`'s `FAST_ROOT` set.

## VM-only (irreducible — a real boot is the only oracle)

| Bug class | Guarding test (Tier 2) |
| --- | --- |
| busybox initramfs mounts only btrfs `@` subvol | VM boot-verify (`matrix.sh`) |
| firstboot service hang | `vm/seed-generator.bats` asserts the emit; hang itself is VM |
| multi-disk device rename (`/dev/sdX` reorder) breaks import | `vm/vm-reorder-disks.bats`, `vm/vm-pool-verify.bats` |
| `zpool export rpool` left pool imported on reboot | `vm/seed-generator.bats` (emit) + VM boot |
| encrypted-boot passphrase unlock over serial | Console Answerer (`matrix.sh`, ADR 0046) |
| `switch_root` / initramfs handoff | VM boot only |

## Closed — exhaustive `set -u` summary sweep

`matrix/print-summary-setu.bats` now renders the real `print_summary`
under `set -u` for **every** base fs×topology cell (derived live from the
generator), a standalone-data-pool cell, and a model-backed none+leftover
branch — asserting no `unbound variable`. This converts the unbound-var
class from few-fixture to exhaustive, unprivileged, always-on, and it has
teeth (a mutation injecting an unbound var trips it). The btrfs-multi shape
ADR 0048 named is covered.

## Known gap — the next validator worth writing

The generation-time artifacts other than the summary — **fstab, mount
units, initcpio HOOKS** — still run through their real validators
(`systemd-analyze verify`, `mkinitcpio -n`, fstab lint) only on the
fixtures in the validator tier, not across *every* cell. `print_summary`
now sweeps exhaustively; these do not.

**Proposed slice:** in the Tier-1 cell loop, feed each cell's generated
fstab / mount units / initcpio through the existing `validators.bash`
helpers (`validators_fstab_lint`, `validators_verify_unit`,
`validators_mkinitcpio_build`), so the generation-time class is exhaustive
too. Larger than the summary sweep because those generators need `/boot`
and mount context per cell; scoped here rather than rushed.
