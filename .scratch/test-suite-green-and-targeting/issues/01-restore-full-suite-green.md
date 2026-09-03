# 01 — Restore `run.sh --full` to green (repair the 18)

**What to build:** `run.sh --full` exits 0 on an unprivileged dev box (no
`/dev/kvm`, no root, no network) — the ~827 always-on tests all pass. Today 18
tests fail across four clusters (AUR-helper resolution, secrets load, pool
export/finalize, pkglist round-trip), all in files outside the `--fast` gate.
They mock their externals and fail from test-harness/SUT drift, not product
bugs: the SUT moved and the test's isolation didn't follow (e.g. an isolated
PATH that provides only some of the coreutils the script now calls, or a stub
the script outgrew). Repair each test's isolation/stubs to match the current
SUT so real coverage is restored — the tests keep running without root, real
binaries, or a network.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `run.sh --full` exits 0 on an unprivileged box; the 18 failures are gone.
- [ ] Each fix repairs the test harness (isolation/stubs) to the current SUT;
      the SUT is changed only if a genuine product bug is found (and if so,
      that's called out).
- [ ] No repaired test is deleted unless it is genuinely obsolete (with a stated
      reason); externals stay mocked (AUR helper, age, mount, zpool).
- [ ] Each repaired test still fails when the behaviour it guards is broken
      (a quick mutation check), so the repair didn't hollow it out.
- [ ] The `--fast` set and the VM/[[Combination Matrix]] tier are untouched; the
      VM tier remains out-of-band and out of the green bar.
