Status: ready-for-agent

# PRD: Tests and Shell Commons Cleanup

## Problem Statement

Two long-standing hygiene issues in the test and shared-library
layer:

**Bats runtime.** `.os/tests/run.sh` runs all 31 `.bats` files
sequentially. 531 tests take ~57s on a 24-core box. One file
(`chroot-impermanence.bats`) is 30.6s alone — 54% of total wall time.
Pre-commit feedback is sluggish even though every test is
`mktemp -d`-isolated and trivially parallelizable.

**Shell Stdlib drift.** `.os/lib/shell-stdlib.sh` is sourced by every
Program Install Script via the Program Runner (see `Shell Stdlib` in
`CONTEXT.md`). It exposes 25 functions across 9 module files. Only 5
have any callers:

- `print_status` (93 calls)
- `check_root` (4)
- `send_user_notification` (4)
- `command_exists` (3)
- `package_installed` (3)

The other 20 functions (`string_contains`, `array_contains`,
`array_join`, `check_command`, `directory_exists`,
`get_desktop_env`, `is_kde`, ...) have zero callers across the whole
repo, and none of the commons modules have any bats coverage. The
result: most of the library is dead code, there is no convention
guiding when to use commons vs. inline bash, and program scripts have
no protection against silently redefining helpers locally.

**Coverage asymmetry.** `lib/layout-multi.sh` is covered by
`layout-multi.bats` (and shared assertions in `layout-common.bats`),
but its sibling `lib/layout-single.sh` (277 lines, default install
path for single-disk machines) has zero direct tests.
`lib/finalize.sh` (pool export + cleanup) is also uncovered — a
failure there strands the OS pool.

## Solution

Land four PRs in order, smallest first:

1. **Bats parallelism.** `run.sh` checks for GNU `parallel`,
   hard-fails with `sudo pacman -S parallel` if absent, otherwise
   runs `bats --jobs "$(nproc)" *.bats`. Expected drop: ~57s → ~3–5s
   on this host.

2. **Commons cleanup + ADR + audit lint + tests.** Delete the 20
   unused helpers from `.os/lib/shell/*.sh`. Keep the 9-module split:
   modules that lose every function become header-only stubs marked
   *reserved* so a future reader knows where new helpers go. Add ADR
   0011 declaring commons the default for Program Install Scripts.
   Add a new section to `tests/audit.sh` that fails if any program
   script redefines a commons-named helper locally. Add per-module
   bats tests for the 5 surviving functions.

3. **Coverage gaps.** Add `layout-single.bats` mirroring
   `layout-multi.bats`, and a tracer-bullet `finalize.bats` covering
   pool export + cleanup.

4. **(Conditional) Scenario-split** `chroot-impermanence.bats` only
   if post-PR1 measurement shows it still dominates the parallel
   wall time. Decision deferred to after PR 1 lands.

`CONTEXT.md` does not change — the existing `Shell Stdlib` glossary
entry is still accurate. The new policy (prefer commons) lives in
the ADR, not in the glossary.

## User Stories

1. As a developer running tests locally, I want the full bats suite
   to finish in seconds rather than a minute, so that I can re-run
   tests after every edit without breaking flow.
2. As a developer, I want a clear error message when GNU `parallel`
   is missing, so that I know exactly how to fix my environment
   instead of debugging a confusing bats failure.
3. As a developer writing a new Program Install Script, I want a
   small, accurate set of commons helpers, so that I can find what's
   useful without wading through 20 unused functions.
4. As a developer adding a new shared helper, I want a documented
   convention telling me to put it in `lib/shell/<module>.sh` with
   a test, so that the next person who needs it can find it.
5. As a developer reviewing a PR, I want `audit.sh` to fail when a
   program script locally redefines `print_status` (or any other
   commons-named helper), so that commons stays the single source
   of truth without manual policing.
6. As a future reader, I want empty commons modules to declare
   themselves *reserved* rather than look abandoned, so that I
   understand the file is intentional scaffolding.
7. As a developer touching the layout interface, I want
   `layout-single.sh` to be covered by tests at parity with
   `layout-multi.sh`, so that single-disk installs (the most common
   install path) are protected by the same safety net.
8. As an operator finishing an install, I want `finalize.sh` to
   have at least tracer-bullet coverage, so that a regression that
   leaves the OS pool imported can't ship silently.
9. As a developer running `bats --jobs $(nproc)`, I want each test
   to remain hermetic via `mktemp -d`, so that parallelism doesn't
   introduce ordering flakes.
10. As a maintainer, I want commons cleanup, ADR, audit lint, and
    new tests to land in one reviewable PR, so that the policy and
    the deletions can't drift apart between merges.
11. As a developer reading ADR 0011, I want to understand which
    code is in scope (Program Install Scripts) and which is not
    (`lib/`, `tools/`), so that I don't accidentally start
    refactoring chroot scripts under the wrong rule.
12. As a developer writing tests for commons, I want the test files
    named `commons-<module>.bats`, so that they don't collide with
    the existing `packages.bats` (which covers `lib/packages.sh`,
    not `lib/shell/packages.sh`).
13. As a developer skeptical that PR 4 (scenario-splitting
    `chroot-impermanence.bats`) is needed, I want a measurement gate
    after PR 1, so that the test restructuring only lands if the
    parallel run still has a real bottleneck.

## Implementation Decisions

### Bats parallelism (PR 1)

- `tests/run.sh` checks `command -v parallel` and exits non-zero with
  the install hint when absent. Symmetric with how the script already
  auto-vendors bats-core on first run.
- Uses `bats --jobs "$(nproc)"`. No cap. Tests are tmpfs-bound and
  short; saturating cores is the cheapest path to the floor.
- No environment override. If a developer later wants tuning, add
  `BATS_JOBS=` then.

### Commons cleanup (PR 2)

- Deleted from `.os/lib/shell/`: `string_contains`,
  `string_multiline_contains`, `string_to_uppercase`,
  `string_strip_prefix`, `string_strip_suffix`,
  `string_is_empty_or_null`, `string_substr`, `array_contains`,
  `array_split`, `array_join`, `array_prepend`, `check_command`,
  `command_output_contains`, `check_directory`, `directory_exists`,
  `get_desktop_env`, `is_hyprland`, `is_kde`,
  `make_env_bash_scripts_executable`, `make_executable_and_run`.
- Surviving: `print_status`, `check_root`, `send_user_notification`,
  `command_exists`, `package_installed`.
- The 9-module split (`strings.sh`, `arrays.sh`, `commands.sh`,
  `directories.sh`, `environments.sh`, `notifications.sh`,
  `output.sh`, `packages.sh`, `permissions.sh`) is preserved on
  disk. `shell-stdlib.sh` still sources all nine. Empty modules
  keep the shebang + the existing header line + a `# Reserved for
  future <domain> helpers — add functions here, add tests in
  commons-<domain>.bats.` line.
- New ADR `docs/adr/0011-shell-commons-as-default.md`. Scope:
  `.os/programs/*/install.sh` only. Rule: prefer commons when a
  helper exists; land new shared helpers in
  `lib/shell/<module>.sh` with a matching test; do not redefine
  commons-named helpers locally. `lib/` and `tools/` are explicitly
  out of scope.
- New section in `.os/tests/audit.sh` (section 12, after the
  existing 11) that greps every `programs/*/install.sh` for a local
  redefinition of any surviving commons helper name and fails the
  audit if one is found.
- No changes to `CONTEXT.md`. The `Shell Stdlib` glossary entry is
  still accurate.

### Coverage gaps (PR 3)

- `layout-single.bats` mirrors `layout-multi.bats`: same fixture
  pattern, same stubbing approach for `zfs`/`zpool`/`sgdisk`, same
  assertion style against `LAYOUT_*` outputs.
- `finalize.bats` is a tracer-bullet test, not exhaustive: stub
  `zpool`/`umount`, run the finalize flow, assert that pool export
  is called for both pools when present.

### Conditional restructuring (PR 4)

- Only opened if the parallel run from PR 1 still spends >5s on
  `chroot-impermanence.bats`. Decision is data-driven, not
  upfront.
- If opened: split the 73 tests into ~4–6 `.bats` files by scenario
  (disabled, enabled-default, enabled+persist-dirs,
  enabled+persist-files, ...). Each file runs `impermanence_apply`
  once in `setup_file()`; per-test assertions read the shared
  `$CALLS` log set up by the file-level setup.

### Sequencing

- PRs 1, 2, 3 are independent and can land in any order. The
  recommended order minimizes diff size at each merge boundary.
- PR 4 is gated on PR 1 measurement.

## Testing Decisions

A good test here exercises **observable behavior at the module
boundary**: input env vars and arguments go in, output text or
calls-log lines come out, side-effect files exist with the right
contents. Tests do not assert on internal helper names, variable
names, or sourcing order.

### New tests

- `commons-output.bats` — `print_status` with each level and
  `custom` color path; output captures verified to contain the
  prefix and the message.
- `commons-permissions.bats` — `check_root` under `EUID=0` and
  `EUID=1000`; assert exit code, not log output.
- `commons-commands.bats` — `command_exists` for a known-present
  command (`bash`) and a known-absent one.
- `commons-packages.bats` — `package_installed` with `pacman` stub
  on `$PATH` returning 0 or 1; assert pass-through exit codes.
- `commons-notifications.bats` — `send_user_notification` with
  `notify-send` stub; assert argv passed.
- `layout-single.bats` — mirror of `layout-multi.bats`: every
  function in the layout interface (`layout_plan`,
  `layout_partition`, `layout_create_pools`, `layout_mount_esp`)
  gets tracer-bullet plus scenario tests.
- `finalize.bats` — stub `zpool`, run finalize, assert export
  called for `LAYOUT_OS_POOL_NAME` and (when set)
  `LAYOUT_DATA_POOL_NAME`.

### Prior art

- `layout-multi.bats`, `layout-common.bats` — model for the new
  `layout-single.bats`.
- `chroot-impermanence.bats` — model for stubbing `zfs`/`zpool` and
  asserting against a `$CALLS` log.
- `picker.bats` — model for per-test `mktemp -d` isolation while
  sourcing a single library file.
- `tests/audit.sh` — model for the new duplicate-commons grep
  check; pattern matches the existing 11 sections.

### Modules to test

Confirmed in conversation: per-module commons tests now (one per
non-empty surviving module), plus `layout-single` and `finalize`
gap-fills. No tests for `lib/globals.sh` — it's constants only and
not worth covering.

## Out of Scope

- Refactoring `lib/*.sh` or `tools/*.sh` to source the Shell
  Stdlib. They have their own ad-hoc `info/warn/error/section`
  helpers (visible in `chroot-impermanence.bats`'s test stubs).
  Unifying that is a separate, larger effort.
- Adding new commons functions speculatively. New helpers land
  only when a real second caller demands them, per ADR 0011.
- Linting for ad-hoc color escapes (`\033[`) in program scripts.
  Catching that requires a fragile grep with high false positives;
  code review handles it.
- Auto-installing `parallel` from `run.sh`. Hard-fail with an
  install hint instead — tests run as a non-root user and a sudo
  prompt mid-test is awkward.
- `CONTEXT.md` edits. No glossary terms change.

## Further Notes

- Bats baseline measured 2026-05-23: 531 tests, ~57s sequential,
  `chroot-impermanence.bats` 30.6s of that. PR 1 should be
  re-measured immediately after merge so the PR 4 gate has fresh
  data.
- No CI exists in this repo today. All checks run locally; the
  `.github/workflows` paths visible under
  `.os/tests/bats/.github/` belong to the vendored bats-core
  submodule, not this project.
- The new ADR will be numbered 0011 (current highest is 0010 —
  pre-install-picker).
- Issue files (PR-sized) will be created under
  `.scratch/tests-and-commons-cleanup/issues/` once this PRD is
  approved.
