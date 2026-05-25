Status: done

# PRD: Environment resolution is self-contained at each consumer

References: ADR 0017.

## Problem Statement

The Environment resolution module
(`lib/environment.sh`) exposes three public functions
(`validate_environment`, `resolve_gpu_packages`,
`resolve_audio_packages`) that must be called in a fixed order to
populate five globals (`ENVIRONMENT_DESKTOP`, `ENVIRONMENT_GPU`,
`GPU_PACMAN_PACKAGES`, `GPU_PARU_PACKAGES`, `AUDIO_PACKAGES`).

The sequence is invoked from exactly one site
(`validate_install_context` in the validation module); the
ordering contract is enforced by a defensive precondition check
inside `collect_packages` (in the packages module) that aborts
with "call validate_install_context() first" if the globals are
unset.

The contract is spread across three modules: environment declares
the three publics; validation calls them in sequence; packages
asserts the result. A caller extracting `collect_packages` for
reuse — or simply reading it cold — has to chase preconditions
through two other modules. The split into three publics buys
nothing today (one call site) and makes `collect_packages` hostile
to anyone who hasn't already memorised the pipeline.

## Solution

Collapse the three publics in the Environment resolution module
into one idempotent `resolve_environment()`. The old publics
become private internals
(`_resolve_env_validate`, `_resolve_env_gpu`,
`_resolve_env_audio`) called only by the wrapper. Each call to
`resolve_environment` resets the five globals and re-runs the
full pipeline.

Both `validate_install_context` (in the validation module) and
`collect_packages` (in the packages module) call
`resolve_environment` directly. The defensive precondition check
in `collect_packages` deletes — there is nothing to guard. The
"call validate_install_context() first" error message becomes
impossible to trigger.

The five globals stay separate; consumers in other modules
(`profiles.sh`, `chroot.sh`) are untouched in this refactor.

## User Stories

1. As an installer maintainer, I want `collect_packages` to be
   self-contained — call it from any context and it just works —
   so that I do not need to memorise which validation must run
   first.
2. As an installer maintainer, I want one public entry point on
   the Environment resolution module instead of three, so that
   the module's interface is a single seam.
3. As an installer maintainer, I want the defensive precondition
   block in `collect_packages` to be removed, so that there is
   no implicit ordering contract for callers to violate.
4. As an installer-test author, I want
   `resolve_environment` to be idempotent (safe to call
   repeatedly), so that I can call it inside a test without
   tearing down state from a previous call.
5. As an installer-test author, I want the per-phase test
   files (environment validation, GPU resolution, audio
   resolution) to keep working against the renamed internals,
   so that the bats coverage stays at parity with no test
   rewrites beyond the function-name rename.
6. As a future engineer reading `collect_packages`, I want the
   first line to call `resolve_environment` so that the
   environment dependency is visible in the function body, not
   hidden in a sibling module's call order.
7. As a future engineer wondering why `collect_packages` calls
   `resolve_environment` when `validate_install_context`
   already did, I want ADR 0017 to be discoverable so that the
   self-containment rationale is on record.
8. As an operator running the install, I want the resolved
   environment state (desktop, GPU, audio packages) to be
   byte-identical to today's output, so that nothing observable
   changes from my perspective.
9. As an operator running the install, I want the additional
   `lspci` call (from the second `resolve_environment`
   invocation) to be unnoticeable, so that install time is
   effectively unchanged.

## Implementation Decisions

- **New public seam** on the Environment resolution module:
  `resolve_environment()` — idempotent. Resets the five
  resolved globals (`ENVIRONMENT_DESKTOP`, `ENVIRONMENT_GPU`,
  `GPU_PACMAN_PACKAGES`, `GPU_PARU_PACKAGES`,
  `AUDIO_PACKAGES`) and re-runs the full pipeline
  (validate → GPU → audio) every call.
- **Privacy by rename**: the three current publics rename to
  underscore-prefixed internals
  (`_resolve_env_validate`, `_resolve_env_gpu`,
  `_resolve_env_audio`). Bash has no real privacy; the
  underscore is convention. They are called only from
  `resolve_environment`.
- **Validation seam**: `validate_install_context` (in the
  validation module) replaces its three-call sequence with a
  single `resolve_environment` call.
- **Packages seam**: `collect_packages` (in the packages
  module) calls `resolve_environment` as its first action.
  The defensive precondition block that asserts
  `GPU_PACMAN_PACKAGES` and `AUDIO_PACKAGES` are set is
  deleted along with its error messages.
- **Docstring updates**:
  - Environment module header drops the "Pipeline contract"
    section.
  - `collect_packages` header drops the
    "Precondition: validate_install_context() must be called
    before" paragraph and the per-source notes that mention
    `resolve_gpu_packages` / `resolve_audio_packages`.
- **Five globals stay separate**. Bash associative arrays
  cannot nest arrays; consolidation would cost clarity at every
  read site without semantic gain.
- **Untouched consumers**: `profiles.sh` (reads
  `GPU_PARU_PACKAGES`) and `chroot.sh` (passes
  `ENVIRONMENT_DESKTOP` into the chroot env) continue to trust
  that prior pipeline stages populated the globals. Extending
  the self-containment pattern to them is a separate refactor.
- **Idempotence**: each call to `resolve_environment` resets
  all five globals up front, then re-resolves. Double-calls
  produce identical state to single calls.
- **lspci auto-detection**: if `ENVIRONMENT_GPU=("auto")`,
  the function runs `lspci` and **mutates** `ENVIRONMENT_GPU`
  in place to the detected vendors. This behaviour is preserved
  — the second `resolve_environment` invocation sees the
  already-resolved array and skips the auto-detection path.

## Testing Decisions

- **What makes a good test**: drive the Environment resolution
  module through its public entry point
  (`resolve_environment`) for the integration case; drive
  individual internals (`_resolve_env_validate` etc.)
  directly for the per-phase cases since bash has no real
  privacy. Assert against the five resolved globals or against
  the `lspci`-substitution behaviour.
- **Modules to test**: the Environment resolution module
  (`lib/environment.sh`). Coverage in the packages module
  (`lib/packages.sh`) and validation module
  (`lib/validation.sh`) should regress-check via existing
  pacstrap and validate flow tests.
- **Test shape**:
  - Existing per-phase test files
    (`environment-validation.bats`,
    `gpu-resolution.bats`,
    `audio-resolution.bats`) continue to exercise the
    renamed internals directly. The only mechanical change is
    the function-name rename.
  - One new happy-path integration test for
    `resolve_environment` — set up a fixture
    `install.jsonc` with desktop + GPU declared, call the
    function once, assert all five globals populate; call
    again, assert state is identical (idempotence).
  - Existing tests in `packages.bats` that exercised the
    defensive precondition block must be removed (the block
    is gone).
- **Prior art**: `tests/environment-validation.bats` and
  friends already drive the module with fixtures + stubbed
  `lspci`. The new integration test reuses the same
  infrastructure.
- **Coverage parity**: every assertion currently in the four
  test files is preserved (per-phase ones via the rename;
  integration via the new test).

## Out of Scope

- Extending the self-containment pattern to `profiles.sh`
  (`GPU_PARU_PACKAGES` consumer) and `chroot.sh`
  (`ENVIRONMENT_DESKTOP` consumer). Noted in ADR 0017 as a
  follow-up.
- Consolidating the five globals into one associative array or
  any other structure. Rejected during grilling — bash can't
  nest arrays in assoc arrays.
- Changing the Environment Config schema, the `lspci`
  detection rules, or the GPU vendor → package mapping.
- Renaming `resolve_environment` itself in future
  consumers — call sites use the new name.
- Updating `CONTEXT.md` — the change is implementation; the
  domain glossary (Environment Config, GPU Resolution, Display
  Manager) is unaffected.

## Further Notes

- **Single commit** — rename + consolidation + dispatcher
  swap + precondition deletion + test renames + integration
  test land together. The renamed internals and the new public
  entry must arrive in the same change for callers to keep
  working.
- **Double-invocation acceptable** — `resolve_environment`
  runs twice during a normal install (once from
  `validate_install_context`, once from `collect_packages`).
  Both calls are cheap; the only non-trivial cost is `lspci`
  for GPU auto-detection, and the second call sees the
  already-mutated `ENVIRONMENT_GPU` and skips re-detection.
- **No new globals introduced**. The five existing globals
  remain the only state surface.
- **Pattern available to future consumers** — if the
  self-containment pattern proves worth the cost, extend it to
  `profiles.sh` and `chroot.sh` in a follow-up.
