# PRD: Installer test realism + speed

Status: ready-for-agent
Category: enhancement

ADR: `docs/adr/0048-installer-test-realism-tiers.md`

## Problem Statement

The maintainer runs the `.os/tests/` bats suite (1829 tests, ~159 s wall
on 24 cores) and sees green, then a live install breaks anyway. The suite
sources the real `lib/*.sh` but stubs the external device tools and
asserts on `$CALLS` — the *sequence of commands emitted*, not on whether
the emitted artifact is correct. The bugs that actually reach a live
install fall into two classes the suite does not see, and one it already
covers:

- **Create-time** (`sgdisk`/`mkfs`/`zpool create` args) — straight-line,
  historically reliable, and already exercised by every VM install.
- **Generation-time** (fstab, mount units, initcpio HOOKS, systemd
  units) — has bitten: `persist-<esc>.mount` was rejected by systemd
  because `Where=` did not match the escaped unit name, invisible to bats
  because bats mocks systemd; `mkinitcpio` HOOKS ordering
  (modprobe-before-root-mount) is the same shape. Nothing runs the real
  generators through the real validators.
- **Boot-time** (initramfs / `switch_root` / firstboot) — busybox btrfs
  mounts only `@`, firstboot hang, `print_summary` unbound var on btrfs
  multi. The VM oracle for these exists (ADR 0046) but is HITL, so it
  rarely runs.

Separately, the maintainer waits on a suite whose wall-time long pole is
the guided TUI config tests, whose cost is per-test re-sourcing plus `jq`
forks — not disk work.

## Solution

Add a new **unprivileged validator tier** that runs the real config
generators and checks their *output* with real validators, and promote a
small **curated VM smoke set** to an on-demand `matrix.sh smoke`
subcommand — targeting exactly the two escaped bug classes at the cheapest
oracle each admits. Separately, speed the config hotspots with a
tests-only change. The maintainer keeps an always-on, unprivileged, faster
gate that now catches the generation-time class, plus a low-friction entry
point for the boot-time oracle. No loopback create-tier or ZFS micro-VM
shim is built (ADR 0048 rejects them: create-time is reliable and already
covered by VM installs).

Three tracks:

1. **Validator tier** (unprivileged, always-on) — real generators →
   `systemd-analyze verify` (mount + boot/user units), `mkinitcpio -n`
   (initcpio HOOKS), fstab lint. Each slice trims the overlapping `$CALLS`
   assertions it now covers for real.
2. **Config speed** (tests-only) — `setup_file` + `export -f` source-once
   on the guided hotspots; soft target ~110-120 s. Lib `jq`-batching
   deferred.
3. **VM smoke** (on-demand) — `matrix.sh smoke` over a curated cell set
   through the ADR 0046 emit/run seam + Console Answerer.

## User Stories

1. As a maintainer, I want the real mount-unit generator validated with
   `systemd-analyze verify`, so the `Where`-mismatch class fails a bats
   run instead of a boot.
2. As a maintainer, I want a regression test that fails on the historical
   `persist-<esc>.mount` bug and passes on its fix, so that exact class
   can never silently return.
3. As a maintainer, I want the real `mkinitcpio.conf` output checked with
   `mkinitcpio -n`, so a malformed initcpio config is caught unprivileged.
4. As a maintainer, I want explicit HOOKS-order assertions per filesystem
   (zfs, btrfs, xfs, ext4, encrypt), so the modprobe-before-root-mount
   ordering class is caught.
5. As a maintainer, I want the real `write_fstab` output linted for field
   count, option sanity, and duplicate/plausible mountpoints, so a
   malformed fstab is caught before boot.
6. As a maintainer, I want systemd-boot loader entries validated for
   required keys and the serial-console cmdline injection, so bootloader
   wiring is checked for real.
7. As a maintainer, I want resolved user units validated with
   `systemd-analyze verify --user`, so user-service wiring is checked.
8. As a maintainer, I want a single shared validator harness that runs a
   generator into a tmpdir and shells out to a validator, so each slice
   reuses one seam instead of re-implementing setup.
9. As a maintainer, I want the harness to SKIP (never fail) when a
   validator binary is absent, so the suite still runs green on a minimal
   host, mirroring `audit.sh`.
10. As a maintainer, I want each validator slice to delete the `$CALLS` /
    raw-output assertions it now covers for real, so the suite has fewer
    stubs without losing coverage.
11. As a maintainer, I want the pure-logic unit tests (sizing math, branch
    selection, arg construction) kept, so fast branch coverage the
    validators do not exercise is preserved.
12. As a maintainer, I want the guided config tests to source their lib
    modules once per file instead of once per test, so the suite's
    wall-time long pole shrinks with no realism cost.
13. As a maintainer, I want the config-speed change to touch tests only,
    so no production behavior risk is taken for test speed.
14. As a maintainer, I want the before/after suite wall-time recorded, so
    the ~110-120 s soft target is measured, not assumed.
15. As a maintainer, I want a `matrix.sh smoke` subcommand that runs a
    curated boot-verify set headless, so the boot-time oracle runs during
    normal work rather than only at HITL time.
16. As a maintainer, I want the encrypted smoke cell unlocked headless via
    the Console Answerer, so encryption is boot-verified with no
    install-only carve-out.
17. As a maintainer, I want the impermanence smoke cell asserted with
    `verify.rollback`, so ephemeral-wiped / persistent-survived is proven.
18. As a maintainer, I want the smoke driver to exit non-zero on any cell
    failure and print a per-cell PASS/FAIL/SKIP summary, so a failure is
    unambiguous.
19. As a maintainer, I want the smoke subcommand to reuse `lib/matrix/*`
    and leave the committed matrix records unchanged, so it adds no
    parallel plumbing or drift.
20. As a maintainer, I want no loopback create-tier or ZFS micro-VM shim
    introduced, so no privileged harness is built for a bug class the VM
    installs already cover.

## Implementation Decisions

### Validator harness (the deep module)

- A single shared bats helper, the one new deep module of this PRD, with a
  simple interface: run a named generator into a tmpdir, shell out to a
  validator binary, and return pass/fail — or `skip` when the binary is
  absent. It encapsulates tmpdir setup, invocation, and the
  binary-presence check behind a stable surface the four slices call
  without re-implementing setup.
- SKIP-on-absent-binary mirrors `audit.sh` semantics: a missing validator
  never fails the run, so the suite stays green on a minimal host.
- `systemd-analyze verify` runs against the generated unit file(s) in a
  standalone dir; assertions target the naming/`Where` and syntax errors
  it reports, tolerating expected "missing dependency" notes.
- `mkinitcpio -n` (dry-run, no image write) validates the generated
  config; HOOKS-order is asserted explicitly on top of it.
- fstab lint is a local check (field count, option sanity, mountpoint
  plausibility, no duplicate mountpoints) with no privileged
  `findmnt --verify` requirement.

### Generators exercised (existing, unchanged)

- `imp_write_mount_unit` / `imp_mount_after_unit` — mount units
- `lib/chroot/initcpio.sh` — HOOKS
- `write_fstab` / `_chroot_fstab_generate` / `btrfs_root_fstab` /
  `data_group_fstab_line` — fstab
- `lib/chroot/bootloader-systemd-boot.sh` — loader entries
- `_profiles_resolve_user_unit` — user units

### Trim overlap

Per validator slice, delete only the `$CALLS` / raw-string assertions the
validator now checks for real. Keep pure-logic unit tests. Net stub count
decreases per slice.

### Config speed (tests-only)

- Move the 4-6 `source` lines from per-test `setup()` into `setup_file`,
  and `export -f` the sourced functions so each test subshell sees them
  without re-sourcing. Keep per-test mutable state (tmpdir, state/nav
  files) in `setup()`.
- Dedupe redundant `run` invocations where one call can assert several
  properties.
- Targets `tests/config/guided-controller.bats`, `guided-shell.bats`,
  `guided-menu.bats` first; apply where it pays.
- Deferred (not this PRD): batch `jq` forks in
  `lib/config/{state,nav,edits,menu}.sh` — also speeds the live guided
  TUI, but is a production change gated on measuring tests-only gains.

### VM smoke

- New `smoke` subcommand on `tools/matrix.sh` reusing the ADR 0046
  `emit`/`run` seam, Console Answerer, timeout bands, and host-resource
  guard. Curated cells: single-zfs, multi-mirror, impermanence-single
  (`verify.rollback`), encrypted-single (Answerer unlock). On-demand only;
  no git-hook or CI wiring (no CI exists). Committed matrix records
  unchanged.

## Testing Decisions

- **Good tests assert external behavior, not implementation.** The
  validator slices assert on real validator *verdicts* and generated
  *artifacts* (unit naming, HOOKS order, fstab fields), never on
  `_LAYOUT_IMPL_*` internals or argv the artifact makes redundant.
- **Modules tested:**
  - The validator harness gets its own bats: SKIP when the binary is
    absent, PASS on a valid artifact, FAIL on a broken one.
  - The four generators are tested *through* the harness (mount units,
    initcpio HOOKS, fstab, boot + user units), each with at least one
    regression pinned to a historical bug where one exists
    (`persist-<esc>.mount`, modprobe-before-root-mount).
  - `matrix.sh smoke` is covered as an integration subcommand (no new lib
    helper carved out); the existing `tests/matrix/*` records/guard tests
    must still pass unchanged.
- **Prior art:** `tests/chroot/chroot-fstab.bats` and
  `tests/chroot/chroot-impermanence.bats` for the source-and-call-a-real-
  function pattern; `tests/audit.sh` for SKIP-on-absent-tooling semantics;
  `tests/vm/console-answerer.bats` and the matrix cells for the smoke
  integration shape.

## Out of Scope

- Loopback create-tier and ZFS micro-VM shim (ADR 0048 rejects).
- Batching `jq` forks in `lib/config/{state,nav,edits,menu}.sh` (deferred
  follow-up).
- Pre-push / CI wiring of the VM smoke — no CI exists; smoke stays
  on-demand.
- Expanding the full pairwise matrix or changing its committed records.

## Further Notes

- Sequencing: `01` mount-unit validator (establishes the harness) → `02`
  config speed → `03` initcpio → `04` fstab → `05` boot + user units →
  `06` `matrix.sh smoke`.
- `tests/run.sh` and `tests/shellcheck.sh` must pass throughout.
- All four validator binaries (`systemd-analyze`, `mkinitcpio`) are on the
  dev host and need no privilege; the fstab lint needs no external tool.
