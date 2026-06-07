# VM provisioning unified behind a profile-driven harness

The ~18 per-flavor VM scripts (`vm/vm-*.sh`, `tests/vm/testing-*.sh`),
each a thin wrapper inlining a near-duplicate `install.jsonc`, are
replaced by a single profile-driven harness `vm/vm.sh` plus JSONC **VM
Profiles** (data) grouped into Profile Categories. A profile names its
install config via exactly one source — a `host_profile` reference
(resolved through the picker's existing template-merge, so config has one
source of truth), an inline `install` block (for test-only permutations
with no real host), or `"install": "repo"` (smoke-test the shipped
default) — alongside a `hardware` block and, for tests, a `verify` block.
`--testing` flips the disposable test flow (headless, serial capture,
sentinel/exit-code, boot-verify) over the default persistent flow (spice,
reboots into the installed system); all harness code, including the test
flow and its helpers, consolidates under `vm/` so the prod entrypoint
never depends on `tests/`.

## Considered Options

- **Two harnesses, profile-driven** — keep separate prod/test entry
  scripts. Rejected: the user wants one `--testing` entrypoint, and the
  two already share `_harness-core.sh`.
- **All-inline profiles** — every profile self-contained. Rejected:
  re-entrenches the config duplication with `hosts/vm/*` templates that
  this work removes.
- **A host profile per test permutation** — make every profile reference
  a `host_profile`. Rejected: 13 of 14 test configs are install
  permutations (mirror/stripe/none/dirty/reorder/…) that are not real
  machines; this would pollute `hosts/vm/` with ~10 fixture profiles.
- **Test code under `tests/vm/lib/`** — split flow modules across prod
  and test dirs. Rejected: the single prod entrypoint would then source a
  `tests/` path (backwards dependency).

## Consequences

- The 18 wrapper scripts are deleted; both READMEs are rewritten to
  document `vm.sh --profile`. ADRs 0019 and 0028 keep their original
  script-name references as point-in-time record.
- `tests/` finishes mirroring the `lib/` taxonomy (ADR 0032): VM unit
  bats (`vm-*.bats`) move to `tests/vm/`; `tests/vm/` otherwise holds
  only profiles and run artifacts.
