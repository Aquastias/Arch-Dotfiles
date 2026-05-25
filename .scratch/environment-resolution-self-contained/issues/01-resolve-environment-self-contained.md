Status: ready-for-agent

# Make collect_packages self-contained via resolve_environment

## Parent

`.scratch/environment-resolution-self-contained/PRD.md` (ADR 0017)

## What to build

Collapse the three current public functions in the Environment
resolution module (`validate_environment`,
`resolve_gpu_packages`, `resolve_audio_packages`) into private
underscore-prefixed internals
(`_resolve_env_validate`, `_resolve_env_gpu`,
`_resolve_env_audio`) and add a single idempotent public entry
point `resolve_environment()` that runs all three. Then make both
consumers self-contained:

- The validation module's `validate_install_context` replaces its
  three-call sequence with one `resolve_environment` call.
- The packages module's `collect_packages` calls
  `resolve_environment` as its first action and deletes the
  defensive `declare -p GPU_PACMAN_PACKAGES` /
  `declare -p AUDIO_PACKAGES` precondition block along with its
  error messages.

`resolve_environment` is idempotent: it resets all five resolved
globals (`ENVIRONMENT_DESKTOP`, `ENVIRONMENT_GPU`,
`GPU_PACMAN_PACKAGES`, `GPU_PARU_PACKAGES`, `AUDIO_PACKAGES`)
up front and re-runs the full pipeline every call. The
`lspci`-driven mutation of `ENVIRONMENT_GPU` when the value is
`("auto")` is preserved — the second invocation sees an
already-resolved array and skips re-detection.

The five globals stay separate (bash cannot nest arrays in
associative arrays). Consumers in `profiles.sh` and `chroot.sh`
are not modified — extending the self-containment pattern to
them is a noted follow-up in ADR 0017.

Docstrings update: the "Pipeline contract" block in the
Environment module header and the
"Precondition: validate_install_context() must be called
before" paragraph in `collect_packages` both disappear.

Single commit. The renames and the new public entry must
arrive together for callers to keep working. No `CONTEXT.md`
change.

## Acceptance criteria

- [ ] `resolve_environment()` exists as the single public entry
      on the Environment resolution module; runs
      `_resolve_env_validate`, then `_resolve_env_gpu`, then
      `_resolve_env_audio`; resets all five resolved globals
      at the top.
- [ ] The three previous publics no longer exist under their
      old names. Their bodies are now in
      `_resolve_env_validate`, `_resolve_env_gpu`,
      `_resolve_env_audio` with identical behaviour.
- [ ] `validate_install_context` calls `resolve_environment`
      once instead of calling `validate_environment`,
      `resolve_gpu_packages`, `resolve_audio_packages` in
      sequence.
- [ ] `collect_packages` calls `resolve_environment` as its
      first action. The defensive `declare -p` precondition
      block and its error messages are deleted.
- [ ] `resolve_environment` is idempotent — calling it twice
      produces identical state to calling it once.
- [ ] `lspci` auto-detection behaviour is preserved: when
      `ENVIRONMENT_GPU=("auto")`, the array is mutated to the
      detected vendors on first call; the second call sees the
      already-resolved array and does not re-run detection.
- [ ] The five globals remain separate, declared at the top of
      the Environment resolution module as today.
- [ ] `profiles.sh` and `chroot.sh` are untouched.
- [ ] Module header docstring drops the "Pipeline contract"
      block.
- [ ] `collect_packages` docstring drops the
      "Precondition: validate_install_context() must be called
      before" paragraph and any per-source notes that mention
      the old function names.
- [ ] Per-phase test files
      (`tests/environment-validation.bats`,
      `tests/gpu-resolution.bats`,
      `tests/audio-resolution.bats`) continue to exercise the
      renamed internals directly; coverage is at parity with
      the prior pass.
- [ ] A new happy-path integration test for
      `resolve_environment` is added — fixture
      `install.jsonc` with desktop + GPU declared, one call
      asserts all five globals populate, a second call asserts
      state is identical (idempotence).
- [ ] Any test in `tests/packages.bats` (or elsewhere) that
      exercised the deleted defensive precondition block is
      removed.
- [ ] Every assertion currently in
      `tests/environment-validation.bats`,
      `tests/gpu-resolution.bats`,
      `tests/audio-resolution.bats` is preserved (per-phase
      via the rename; integration via the new test).
- [ ] `shellcheck` passes on every changed file.
- [ ] Full `bats` suite passes.
- [ ] Resolved environment state (desktop, GPU packages,
      audio packages) is byte-identical to today's output for
      the same input.
- [ ] Single commit, conventional-commit style, capitalized
      after the prefix.

## Blocked by

None - can start immediately.
