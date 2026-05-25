# ADR 0017: Environment resolution is self-contained at each consumer

## Status
Accepted

## Context
`lib/environment.sh` exposed three public functions
(`validate_environment`, `resolve_gpu_packages`,
`resolve_audio_packages`) that had to be called in a fixed order
to populate five globals (`ENVIRONMENT_DESKTOP`,
`ENVIRONMENT_GPU`, `GPU_PACMAN_PACKAGES`, `GPU_PARU_PACKAGES`,
`AUDIO_PACKAGES`). The sequence was called from exactly one site
(`validate_install_context`, `lib/validation.sh:279-281`); the
contract was enforced by a defensive precondition check inside
`collect_packages` (`lib/packages.sh:48-53`) that aborted with
"call validate_install_context() first" if the globals were unset.

The ordering contract was spread across three files:
`environment.sh` declared the three publics; `validation.sh`
called them in sequence; `packages.sh` asserted the result. A
caller extracting `collect_packages` for reuse — or simply
reading it cold — had to chase preconditions through two other
files. The split into three publics bought nothing today (one
call site) and made the consumer hostile to anyone who hadn't
already memorised the pipeline.

## Decision
Collapse the three publics into one idempotent
`resolve_environment()` in `environment.sh`. The old publics
become private internals
(`_resolve_env_validate`, `_resolve_env_gpu`, `_resolve_env_audio`)
called only by the wrapper. Each call to `resolve_environment`
resets the five globals and re-runs the full pipeline.

Consumers no longer depend on call order: both
`validate_install_context` and `collect_packages` invoke
`resolve_environment` directly. The defensive precondition check
in `collect_packages` is deleted — there is nothing to guard. The
"call validate_install_context() first" error message becomes
impossible to trigger.

`profiles.sh` (reads `GPU_PARU_PACKAGES`) and `chroot.sh` (passes
`ENVIRONMENT_DESKTOP` into the chroot env) continue to trust that
prior pipeline stages populated the globals. Self-containing them
is a separate refactor — noted as a follow-up.

The five globals stay separate. Bash associative arrays cannot
hold nested arrays; the current layout (five string-list globals)
is the idiomatic shape and consolidation would cost clarity at
every read site without semantic gain.

## Considered alternatives
- **Keep three publics; add `resolve_environment` as a one-line
  wrapper.** Rejected: cosmetic; the implicit-ordering contract
  survives.
- **Single `resolve_environment`; keep the precondition check in
  `collect_packages`.** Rejected: preserves the ordering contract
  the precondition was guarding against. Defeats the point.
- **Consolidate the five globals into one assoc array
  `_ENV[gpu_pacman]` etc.** Rejected: bash can't nest arrays in
  assoc arrays; would require flat string + per-read split; every
  read site becomes noisier; no semantic gain.

## Consequences
- `collect_packages` is self-contained — calling it from any
  context (tests, future scripts) just works. No "did you call
  validate first?" ceremony.
- `resolve_environment` runs twice during a normal install
  (once from `validate_install_context`, once from
  `collect_packages`). Both calls are cheap; the only non-trivial
  cost is `lspci` for GPU auto-detection, well under 100ms.
- A future reader sees `collect_packages` call
  `resolve_environment` and may wonder why, given
  `validate_install_context` already did. This ADR is the answer.
  The header docstring of `collect_packages` points at it.
- Existing per-phase test files (`environment-validation.bats`,
  `gpu-resolution.bats`, `audio-resolution.bats`) keep testing
  the renamed internals directly — bash has no real privacy, so
  the underscore prefix is convention, not enforcement.
- Follow-up exists: `profiles.sh` and `chroot.sh` consumers of
  these globals are not self-contained. If the pattern proves
  worth it, extend it to them.
