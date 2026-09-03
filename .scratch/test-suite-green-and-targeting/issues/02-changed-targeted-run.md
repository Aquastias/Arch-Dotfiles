# 02 — Add the `--changed` change-targeted run

**What to build:** `run.sh --changed [<ref>]` runs only the tests for the code a
human or agent actually changed — a [[Change-Targeted Run]] — so the edit-verify
loop is seconds, not a full 195-file run. It derives "what changed" from
`git diff --name-only` (default working-tree + staged versus `HEAD`, untracked
files included; an optional `<ref>` diffs against a base for the pre-push view),
maps those paths to a test-file set, and runs that set. Mapping, in order:
mirrored source dir (`lib/<x>/… → tests/<x>/`); root/`tools` script → its
test(s) via an explicit table; a [[Broad-Blast Path]] or any unmapped/unknown
path → widen to `--full`; and the result is always unioned with the
[[Install-Correctness Core]] (the `--fast` set). Directory granularity
throughout. It prints the selected files and any widen-reason, and an empty diff
still runs the core.

**Blocked by:** 01 (green baseline — `--changed` is only a trustworthy signal
once `--full` is green).

**Status:** ready-for-agent

- [ ] `run.sh --changed` runs the tests mapped to the current `git diff` unioned
      with the `--fast` core, and prints what it selected (and why it widened).
- [ ] A changed mirrored source dir runs its mirrored `tests/<x>/`; a changed
      root/`tools` script runs its mapped test(s).
- [ ] A changed [[Broad-Blast Path]] (shared helper, fixture, the runner) and
      any unmapped/unknown changed path both widen to `--full` (fail-safe).
- [ ] An optional `<ref>` arg diffs against that base; untracked new source files
      are picked up; an empty/irrelevant diff still runs the core without error.
- [ ] The path→test selection is a **pure function** of the changed-path list
      (no git call, no bats invocation inside it); the map + broad-blast list
      live in one place so a new source area is a one-line change.
- [ ] A new bats seam tests the pure function directly — mirrored dir, root/tools
      map, broad-blast widen, unmapped widen, always-includes-core, empty-input,
      multi-path union/dedupe — mirroring `profiles-aur.bats`'s pure-resolver
      style (inputs in, resolved set asserted, externals never run).
- [ ] `--fast` remains the pre-push safety gate; `--changed` augments it.
