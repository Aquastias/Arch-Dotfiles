# Installer test realism: an unprivileged validator tier + curated VM smoke

Close the gap between "bats is green" and "the install boots" by adding a
new **unprivileged validator tier** that runs the real config generators
and checks their output with real validators (`systemd-analyze verify`,
`mkinitcpio -n`, fstab lint), and by promoting a small **curated VM smoke
set** to an on-demand `matrix.sh smoke` subcommand. Do *not* build a
loopback create-tier or a ZFS micro-VM shim.

Builds on ADR 0046 (combination-matrix two-tier install testing) and ADR
0035 (profile-driven VM Harness). Reuses the Console Answerer and the
`matrix.sh gen/emit/run` machinery from ADR 0046.

## Context

The bats suite (1829 tests, ~159 s wall on 24 cores) sources the real
`lib/*.sh` but stubs the external device tools (`zpool`, `zfs`, `mkfs`,
`cryptsetup`, `sgdisk`) and asserts on `$CALLS` — the *sequence of
commands emitted*, not on whether the emitted artifact is correct. The
bug history shows this misses two classes and reliably catches a third:

- **Create-time** (`sgdisk`/`mkfs`/`zpool create` args): straight-line,
  historically reliable, and already exercised on every VM install.
- **Generation-time** (fstab, mount units, initcpio HOOKS, systemd
  units): has bitten — e.g. `persist-<esc>.mount` rejected by systemd
  because `Where=` did not match the escaped unit name, invisible to
  bats because bats mocks systemd. `mkinitcpio` HOOKS ordering
  (modprobe-before-root-mount) is the same shape.
- **Boot-time** (initramfs / `switch_root` / firstboot): only a real
  boot manifests these (busybox btrfs mounts only `@`, firstboot hang,
  `print_summary` unbound var on btrfs multi).

The stubbed unit tier is appropriate for create-time and for pure logic,
but nothing runs the *real* generators through the *real* validators, and
the boot-time oracle (the VM tier) is HITL, so it rarely runs.

## Considered Options

- **(a)** Loopback create-tier — run real `sgdisk`/`mkfs`/`cryptsetup`/
  `zpool` against sparse loop files. Rejected. Needs root + loop + (for
  ZFS) a `zfs.ko` the host lacks; targets the create-time class that is
  historically reliable and already covered by every VM install. High
  privileged plumbing, low marginal bug-yield.
- **(b)** ZFS micro-VM create shim — a booted archzfs env running just
  the create path. Rejected for the same reason plus its own harness.
- **(c)** Expand to a full unattended matrix — rejected as scope; ADR
  0046 already defines the pairwise VM tier. A *curated* subset that
  actually runs on demand beats a full one that does not.
- **(d)** Unprivileged validator tier + curated VM smoke, and delete the
  overlapping `$CALLS` assertions the validators now cover for real.
  Chosen. Targets exactly the two classes that slip through, at the
  cheapest oracle each admits.

## Decision

**Two escaped classes, two cheapest oracles.**

**Validator tier — generation-time, unprivileged, always-on.** Run the
real generators and validate their *output*, not their argv:

| Artifact | Generator | Validator |
| --- | --- | --- |
| mount units | `imp_write_mount_unit` | `systemd-analyze verify` |
| initcpio HOOKS | `lib/chroot/initcpio.sh` | `mkinitcpio -n` + order asserts |
| fstab | `write_fstab` / `*_fstab_line` | fstab syntax/field lint |
| boot + user units | loader + user units | `systemd-analyze verify --user` |

All four validators are on-host and need no privilege. Each validator
slice **trims the overlapping `$CALLS` / raw-output assertions** it now
checks for real, keeping only the pure-logic unit tests (sizing math,
branch selection, arg construction) the validators do not exercise.

**VM smoke — boot-time, on-demand.** A new `matrix.sh smoke` subcommand
runs a small curated cell set (single-zfs, multi-mirror, impermanence,
encrypted-single via the Console Answerer) headless through the existing
ADR 0046 emit/run seam. On-demand only (manual or the agent's detached
`systemd-run`), not pre-push. The full pairwise matrix and its records
are unchanged.

**Config-speed, tests-only.** The wall-time long pole is the guided TUI
config tests (`guided-controller`/`shell`/`menu`), whose cost is per-test
re-sourcing plus `jq` forks in `state`/`nav`/`edits`/`menu`. Source the
libs once per file via `setup_file` + `export -f` and dedupe redundant
`run` calls. Soft target ~110-120 s wall. Batching the `jq` forks in the
production lib (which also speeds the live guided TUI) is a **deferred
follow-up**, gated on measuring what tests-only alone buys.

## Consequences

- The `persist-*.mount` / `Where`-mismatch and HOOKS-ordering bug classes
  become checked properties on every bats run, unprivileged, with no VM.
- "Fewer stubs" is met by *replacing* argv-sequence assertions with
  real-artifact validation where it catches real bugs — not by deleting
  fast tests. The always-on gate stays unprivileged and fast.
- No loopback/ZFS-shim harness is built or maintained; create-time
  coverage stays where it already is (the VM install). If a create-time
  regression ever slips, the curated VM smoke and full matrix catch it.
- The boot-time oracle now has a low-friction entry point (`matrix.sh
  smoke`), so it runs during normal work instead of only at HITL time.
- The config-speed work carries no realism cost; the residual `jq`-fork
  cost (and the live-TUI latency it also represents) is deferred, not
  hidden.
