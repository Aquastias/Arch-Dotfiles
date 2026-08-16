# Test speed: fork-free include guards, not setup_file; a total-CPU metric

Amends ADR 0048 (installer test realism tiers). Its "Config-speed,
tests-only" prescription — `setup_file` + `export -f` to source libs once
per file — is **retracted**: measured, it makes the suite *slower*. The
real per-source cost was fork-happy include guards, fixed by a builtin.
And on a developer box under external load, **wall time is unmeasurable**;
the acceptance metric becomes **total CPU (user+sys)**, load-independent.

## Context

ADR 0048 named the guided TUI config tests the wall-time long pole and
prescribed `setup_file` + `export -f` (source the libs once, export the
functions) with a soft target of 110-120 s, deferring production `jq`
batching. That prescription was never applied. Revisiting it with
measurement (baseline ~1956 tests, all green) showed three things:

- **`setup_file` + `export -f` is net-negative.** Applied to the worst
  file (`guided-controller.bats`, 242 tests), median parallel wall went
  **7.4 s → 11.6 s**. `export -f` serialises every function body into the
  environment, which every per-test process fork then inherits and
  copies; the env bloat costs more than the re-source it removes.
- **The real per-source cost was subshell-forking include guards.** Each
  lib guarded its idempotent load with
  `[[ "$(type -t fn)" == "function" ]]` — a `$(…)` subshell fork.
  `guided-controller.sh` had 19, and transitively pulled ~14 more libs
  with their own guards: **~34 ms per source**, ×242 tests, the long pole.
  `declare -F fn` is a builtin with identical semantics and **no fork**.
- **Wall time can't be trusted here.** The dev box runs a steady external
  load (~8-10), so every wall figure is contended. `config/` parallelism
  is only ~43% efficient on 24 cores, so CPU cuts don't map 1:1 to wall
  anyway. Total CPU (user+sys) is the one load-independent signal.

## Considered Options

- **(a)** Keep 0048's `setup_file`/`export -f` plan — rejected; measured
  slower, and the mechanism (env-serialised functions) is the cause.
- **(b)** Batch the 662 runtime `jq` forks in the hot production libs
  now — deferred. It is the largest remaining CPU lever but edits shipping
  TUI code (regression risk); gated behind measurement per 0048's Q on
  touching production code. Not needed for the safe win.
- **(c)** Replace the forking include-guard idiom with the `declare -F`
  builtin, repo-wide; adopt total CPU as the metric. Chosen.

## Decision

**Fork-free include guards.** Across `.os/lib/**` (40 files, 108 symmetric
edits), `[[ "$(type -t fn)" == "function" ]]` → `declare -F fn
>/dev/null 2>&1` (and the one negated form → `! declare -F fn …`). Same
semantics, no subshell. Measured, suite green (2579 pass / 0 fail):

| Scope | Total CPU before → after | Sys (forks) |
| --- | --- | --- |
| `config/` (fork-heaviest) | 267 s → 230 s (-14%) | 112 s → 90 s |
| full suite | 2509 s → 2384 s (-5%) | 400 s → 371 s |

The same guards run on every launch of the live installer, so this also
trims its startup, not only the tests.

**Total CPU is the acceptance metric.** The `<90 s` wall goal from 0048
stays *aspirational*, to be confirmed only on an idle box or CI. On the
dev box, progress is judged by total CPU. `setup_file`-for-sourcing is not
pursued; without env bloat there is no cheaper way to avoid bats'
per-test re-source, so source cost is at its floor.

**Runtime `jq` batching stays deferred**, revisited only if an idle-box or
CI wall measurement shows the target unmet after the safe wins.

## Consequences

- The include-guard idiom is now `declare -F`; new libs must follow it,
  not `$(type -t …)`. A repo-wide grep for `"$(type -t` should stay empty.
- 0048's config-speed target and mechanism are superseded here; its
  realism-tier decisions (validator tier, curated VM smoke) are untouched.
- No test was deleted or weakened; the change is purely a hot-idiom swap,
  so realism is unchanged and the always-on gate stays unprivileged.
- The `jq`-fork CPU (and the live-TUI latency it also represents) remains
  the known next lever, consciously deferred, not hidden.
