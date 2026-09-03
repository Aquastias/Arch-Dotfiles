# Spec: Full-suite green + change-targeted test runs

Status: ready-for-agent

Anchored by **ADR 0103** (builds on ADR 0046/0048/0078). Uses the
[[Change-Targeted Run]], [[Broad-Blast Path]], [[Install-Correctness Core]],
[[Combination Matrix]], and [[VM Harness]] glossary terms.

## Problem Statement

Two things slow me down when I (or an agent) touch this repo. First, the full
test suite (`run.sh --full`) is **not green** — 18 tests fail — so I can't trust
a full run as a signal, and the failures hide in files outside the `--fast`
gate, so they rotted unnoticed while the install-correctness gate stayed green.
Second, there is **no way to run only the tests for the code I just changed**:
below the fixed `--fast` set, my only option is the whole 195-file / ~827-test
suite, which is slow for a one-line edit. I want the full suite green, redundant
tests gone, and a fast run that targets just the tests affected by a change —
whether the change came from a human or an agent.

## Solution

Three sequenced pieces, all on the existing bats runner. **(1)** Restore
`run.sh --full` to green on an unprivileged dev box by repairing the 18
drifted tests — they mock their externals and fail from test-harness/SUT drift,
not product bugs. **(2)** Add a [[Change-Targeted Run]] (`run.sh --changed`)
that runs only the tests mapped to the changed source, fail-safe by design and
always unioning the [[Install-Correctness Core]]. **(3)** A bounded redundancy
pass that removes only true duplicates and fully-superseded fixtures. The result:
a trustworthy green full suite plus a fast, correct, change-scoped run for the
edit loop.

## User Stories

1. As a developer, I want `run.sh --full` to exit 0 on my unprivileged dev box,
   so that a full run is a trustworthy signal.
2. As a developer, I want the 18 failing tests fixed by repairing the tests to
   the current code, so that real coverage is restored rather than deleted.
3. As a developer, I want the failing tests to keep mocking their externals
   (AUR helper, age, mount, zpool), so that they still run without root, real
   binaries, or a network.
4. As a maintainer, I want a test that only fails for a genuine product bug, so
   that "red" always means something is actually broken.
5. As an agent, I want to run only the tests for the files I changed, so that my
   edit-verify loop is seconds, not minutes.
6. As a developer, I want `run.sh --changed` to derive "what changed" from
   `git diff`, so that I don't hand-list files.
7. As a developer mid-change, I want `--changed` to default to my uncommitted +
   staged work versus `HEAD`, so that it reflects work in progress.
8. As a developer, I want new untracked source files to be picked up by
   `--changed` too, so that a brand-new module's tests still run.
9. As a developer preparing to push, I want to pass a base ref to `--changed`,
   so that it can scope to everything since the branch point.
10. As a developer, I want a changed `lib/<x>/` file to run `tests/<x>/`, so
    that the mapping follows the directory mirror I already rely on.
11. As a developer, I want changes to root/`tools/` scripts (with no mirrored
    test dir) to map to their tests via an explicit table, so that they aren't
    silently skipped.
12. As a developer, I want a change to a [[Broad-Blast Path]] (shared helper,
    fixture, the runner itself) to widen to `--full`, so that a wide-impact edit
    never runs a too-narrow subset.
13. As a developer, I want an unmapped or unknown changed path to also widen to
    `--full`, so that missing coverage fails safe rather than silently.
14. As a developer, I want `--changed` to always include the
    [[Install-Correctness Core]] (the `--fast` set), so that no change can
    bypass the catalogued bug-class guards.
15. As a developer, I want `--changed` to run at directory granularity, so that
    the mapping is simple and provably safe even where tests aren't 1:1 with
    source files.
16. As a developer, I want `--changed` to print which files it selected and why
    it widened (if it did), so that I can trust and debug the selection.
17. As a developer, I want `--changed` to be a no-op-safe run when nothing
    relevant changed (still running the core), so that it never errors on an
    empty diff.
18. As a maintainer, I want the selection logic to be a pure function of the
    changed-path list, so that it is unit-testable without invoking git or bats.
19. As a maintainer, I want the source→test map and broad-blast list kept in one
    place, so that adding a new source area is a one-line change.
20. As a maintainer, I want `--fast` to remain the pre-push safety gate, so that
    `--changed` augments rather than replaces install-correctness coverage.
21. As a maintainer, I want redundant tests removed only when a successor fully
    covers them, so that no bug-class in the regression catalog loses its guard.
22. As a maintainer, I want true duplicate-assertion tests consolidated, so that
    the suite shrinks without losing meaning.
23. As a maintainer, I want the regression catalog and a short "how to run
    tests" note updated, so that the green bar and the run modes are documented.
24. As a developer, I want the VM/[[Combination Matrix]] tier to remain
    out-of-band (it needs `/dev/kvm`), so that "full-suite green" is an
    achievable unprivileged bar.

## Implementation Decisions

- **Green is `run.sh --full` exiting 0 unprivileged** (~827 always-on tests).
  The VM/matrix tier (needs `/dev/kvm`) stays out-of-band and is not part of the
  green bar (ADR 0103).
- **Repair-first for the 18.** Root cause is test-harness/SUT drift: the tests
  mock externals but their isolation outgrew the SUT (e.g. an isolated PATH that
  provides only some of the coreutils the script now calls, or a stub the script
  outgrew). Fix the harness to match the current SUT; change the SUT only if a
  genuine bug surfaces; delete a test only if it is truly obsolete. Failing
  areas: AUR-helper resolution, secrets load, pool export/finalize, pkglist
  round-trip.
- **New run mode `--changed [<ref>]`** on the existing runner. Default diff is
  working-tree + staged versus `HEAD`, including untracked files; an optional
  `<ref>` diffs against a base. It resolves changed paths to a test-file set and
  runs that set unioned with the [[Install-Correctness Core]].
- **Selection is a pure function** — input: the list of changed paths; output:
  the set of test files to run. No git call, no bats invocation inside it. The
  `--changed` mode is a thin wrapper: it computes the diff, calls the pure
  function, and runs the result. This mirrors the repo's existing pure resolvers
  (e.g. the Runner AUR resolver).
- **Mapping rules**, in order: (1) a changed `lib/<x>/…` (or other mirrored
  source dir) → the mirrored `tests/<x>/` directory; (2) a changed root/`tools/`
  script → its test(s) via an explicit map; (3) a changed [[Broad-Blast Path]]
  (shared helper, `tests/fixtures/*`, the runner) → widen to `--full`; (4) any
  unmapped/unknown changed path → widen to `--full` (fail-safe). The result is
  always unioned with the `--fast` set; directory granularity throughout.
- **Single source of truth** for the map + broad-blast list lives with the
  runner (inline data it reads), so a new source area is one edit; an unmapped
  new source path fails safe to `--full` until mapped.
- **`--fast` unchanged** as the pre-push safety gate; `--changed` is the
  edit-loop / agent tool. A pre-push hook, if ever added, runs the union.
- **Bounded redundancy pass, last.** Remove only true duplicate-assertion pairs
  and fixtures fully superseded by an exhaustive/property successor (the
  catalog's "few-fixture → exhaustive" cases); consolidate rather than delete
  when unsure; keep every unique bug-class the regression catalog guards.
- **Docs:** ADR 0103 (already written); glossary terms (already written); a
  light regression-catalog note + a short "how to run tests" note added when the
  mode lands.

## Testing Decisions

A good test here asserts **external behaviour** — for the selection logic, "given
these changed paths, exactly these test files (or `--full`) are selected" — not
the internal shape of the mapping. It must not shell out to `git` or run `bats`.

- **One new seam — the pure selection function**, tested by a new bats file.
  Cases: a mirrored source dir maps to its test dir; a root/`tools` script maps
  via the explicit table; a broad-blast path widens to `--full`; an unmapped
  path widens to `--full`; the result always contains the `--fast` core; an
  empty change still yields the core; multiple changed paths union and dedupe.
  **Prior art:** `profiles/profiles-aur.bats` tests the pure
  `_profiles_resolve_aur` resolver exactly this way (feed inputs, assert the
  resolved set, externals never run).
- **Green restoration needs no new seam** — the 18 repaired `.bats` files are
  their own verification (they go red→green), run via the existing runner.
- **Redundancy needs no new seam** — the guard that coverage isn't lost is the
  still-green suite plus the regression catalog's bug-class rows.

## Out of Scope

- **The VM / [[Combination Matrix]] tier.** It needs `/dev/kvm`; it stays
  out-of-band and is not part of the "green" bar or of `--changed`.
- **File-level test↔source linking.** Directory granularity is the chosen
  mapping; a per-file link (naming convention or grepping references) is not
  built now.
- **Replacing `--fast` with `--changed`.** `--changed` augments; it does not
  become the gate.
- **A full 195-file redundancy audit.** Only the bounded, catalogued-supersession
  + obvious-duplicate pass is in scope.
- **A committed git hook.** Optional and explicitly deferred; the mode is usable
  by hand and by agents without it.
- **Rewriting install-correctness coverage.** The `--fast` set's membership is
  unchanged; `--changed` only unions it.

## Further Notes

- The 18 failures are all in the always-on tier and all unprivileged-fixable, so
  restoring green requires no VM, root, or network.
- Because targeting only ever *narrows* when provably safe (and otherwise runs
  `--full`), a mistake in the map costs time, never coverage.
- Natural execution order is three slices: green → targeting → redundancy; the
  targeting and redundancy slices assume a green baseline.
- One caveat carried from design: only the AUR-helper failure was root-caused to
  the exact drifted call (an isolated PATH missing a coreutil); the other three
  clusters are the same class but their precise drifted call is confirmed at
  implementation time.
