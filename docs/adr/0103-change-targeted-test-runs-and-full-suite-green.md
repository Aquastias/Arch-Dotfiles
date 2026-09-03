# Change-targeted test runs and full-suite green restoration

---
Status: accepted. Builds on ADR 0046/0048/0078 (the two-tier bats/VM model and
the `--fast` install-correctness gate).
---

Two problems, one effort. **(1)** `run.sh --full` had drifted red — 18 tests
across `install-pkglist`, `secrets`, `finalize`, `pkglist-profile` fail, all in
files **outside** the `--fast` gate. Every one mocks its externals
(paru/yay/age/mount/zpool) and needs no privilege or real binary; they fail from
**harness/SUT drift** (e.g. `install-pkglist.bats`'s isolated `$BIN` symlinks
only `bash`+`dirname` but the script now calls `grep`). The `--fast`
install-correctness tier stayed green while the ungated remainder rotted
unnoticed. **(2)** Below `--fast`'s fixed curated set, the only granularity is
the whole 195-file suite — there is no way to run just the tests for the code a
human or agent actually changed.

## Decision

1. **Restore `--full` to green on an unprivileged box.** Repair the test
   harnesses to the *current* SUT (restore missing tool symlinks/stubs, widen
   the isolated PATH); touch the SUT only if a genuine bug surfaces; delete a
   test only if it is truly obsolete. The **VM/matrix tier stays out-of-band**
   (needs `/dev/kvm`) and is not part of the green bar — `--full` green means
   the ~827 always-on tests pass unprivileged.

2. **Add `run.sh --changed [<ref>]`** — a [[Change-Targeted Run]]. It maps
   `git diff --name-only` (default working-tree+staged vs `HEAD`, **including
   untracked** files; an optional `<ref>` diffs against a base for the pre-push
   view) to the tests to run via the **directory mirror** (`lib/<x>/… →
   tests/<x>/`) plus a small explicit map for the non-mirrored root/`tools/`
   tests. It runs at **directory granularity** (simple and provably safe; the
   big `config/` dir is pure-bash-cheap, and the slow validator tier lives in
   `chroot/`/`profiles/`). It is **fail-safe**: a changed [[Broad-Blast Path]]
   (`lib/common.sh`, widely-sourced helpers, `tests/fixtures/*`, `run.sh`
   itself) or any unmapped path widens to `--full`. And it **always unions the
   [[Install-Correctness Core]]** (the `--fast` set), so no change can skip
   the catalogued bug-class guards.

3. **Bounded redundancy pass, sequenced last.** After green + targeting land,
   remove only true duplicate-assertion pairs and fixtures fully superseded by
   an exhaustive/property successor (the catalog's "few-fixture → exhaustive"
   cases); consolidate rather than delete when unsure; keep every unique
   bug-class the regression catalog guards. No full 195-file audit.

## Considered options

- **Delete the 18 red tests** — rejected: they guard real behaviour (AUR-helper
  resolution, secrets load, pool export); they rotted, they aren't wrong.
- **File-level test↔source linking** — rejected for now: `tests/config/` is 68
  feature-named files with no 1:1 source map; directory granularity is correct
  and cheap. Revisit only if a directory proves too slow.
- **`--changed` replaces `--fast` as the gate** — rejected: an unrelated edit
  would skip the install-correctness core. `--changed` unions it instead.

## Consequences

- The source→test map and broad-blast denylist are maintained in `run.sh` (or a
  sidecar it reads); an unmapped new source path fails safe to `--full` until
  mapped, so coverage is never silently dropped.
- `--fast` remains the pre-push safety gate; `--changed` is the edit-loop /
  agent tool. A pre-push hook, if added, runs the union.
- The regression catalog gains a note that `--full` is now the green bar and how
  `--changed` relates; the glossary gains three terms.
- Directory granularity means a one-line `lib/config` edit runs all of
  `tests/config/` — accepted as the safe default.
