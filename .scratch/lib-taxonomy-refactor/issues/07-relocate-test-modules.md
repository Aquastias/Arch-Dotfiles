Status: done

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

## Comments

**Part A — module relocation: DONE.** `vm-pool-verify/seed-generator/
sentinel-watcher.sh` → `tests/vm/lib/`. Refs repointed: the 3 unit tests
(`tests/*.bats` → `$BATS_TEST_DIRNAME/vm/lib/…`), `tests/vm/_harness.sh`
(`${LIB_DIR}/…` → `${HARNESS_DIR}/lib/…`), and `seed-generator.sh`'s
hardcoded VM-install **source** path
(`/root/dotfiles/.os/tests/vm/lib/vm-pool-verify.sh`; the
`/usr/local/lib/…` VM **destination** is unchanged). No install-time
code sourced these (test-only confirmed). Verified: bats **917/0**,
`audit.sh` **82/82**, `shellcheck.sh` clean.

**Part B — harness dedup: NOT done, needs a decision.** There are two
*distinct* (not duplicate) harnesses: `vm/_harness.sh` (482 lines,
builds persistent usable VMs; sources common + iso-resolver) and
`tests/vm/_harness.sh` (507 lines, automated testing; also sources
seed-generator + sentinel). Consolidating them is a real ~500-line
merge, and the VM harness is **not runnable in this sandbox** (no
libvirt/QEMU) so it can't be verified here. **Split out to issue 10**
(`10-dedup-vm-harness.md`, `ready-for-human` — needs VM verification).
Issue 07 is closed on the relocation; the dedup is tracked separately.
