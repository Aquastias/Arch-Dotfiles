Status: ready-for-agent

# Relocate test-only modules → tests/vm/lib/ + dedup harness

## Parent

`.scratch/lib-taxonomy-refactor/PRD.md`

## What to build

Move the test-only modules out of `lib/` into the test tree and dedup
the test harness so there is a single harness. These modules are test
infrastructure, not install-time code, and should not be sourced by the
installer.

Relocate:

```
lib/vm-pool-verify.sh    -> tests/vm/lib/vm-pool-verify.sh
lib/seed-generator.sh    -> tests/vm/lib/seed-generator.sh
lib/sentinel-watcher.sh  -> tests/vm/lib/sentinel-watcher.sh
```

Update every test that sources these to the new path, and collapse any
duplicated harness logic into one shared harness.

## Acceptance criteria

- [ ] 3 test-only modules relocated to `tests/vm/lib/`
- [ ] No install-time code sources them from `lib/`
- [ ] Test harness deduped to a single shared harness
- [ ] All test sourcing updated to the new paths
- [ ] Full bats + VM test suite passes unchanged

## Blocked by

- None - can start immediately
