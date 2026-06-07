# Test-tree mirror lib/ (non-vm)

Status: ready-for-agent

## Parent

`.scratch/vm-profile-harness/PRD.md`

## What to build

Finish making `tests/` mirror `lib/`'s subsystem foldering (ADR 0032),
for everything except the VM harness tests (those move with issues 02/03).
Rule: a test lives in `tests/<sub>/` iff `lib/` ships a matching
`lib/<sub>/`; otherwise it stays flat.

- **Wipe:** consolidate under `tests/wipe/`. Remove the stale top-level
  `wipe-*.bats`, and resolve the duplicate where
  `wipe-prior-install-state.bats` overlaps `wipe/wipe-prior-state.bats`
  (keep one, covering `lib/wipe/prior-state.sh`). Ensure the other
  top-level wipe concerns (live-medium, probe, select) land correctly
  (folder vs flat per the rule and what they source).
- **Chroot:** `chroot-*.bats` → `tests/chroot/` (mirrors `lib/chroot/`).
- **Shell:** the five `commons-*.bats` that source `lib/shell/*.sh` →
  `tests/shell/<module>.bats`, renamed 1:1 with the lib file. Keep
  `commons-part-name.bats` flat (it sources flat `lib/common.sh`).
- **Extras:** `kde-adapter`, `hyprland-adapter`, `environment-runner`
  bats → `tests/extras/`.

Rewire every moved file's `source=` / `BASH_SOURCE`-relative path and
`# shellcheck source=` directive. No production code moves in this issue.

## Acceptance criteria

- [ ] `tests/wipe/` holds all wipe bats; no stale top-level `wipe-*.bats`
      remain; the prior-state duplicate is resolved to a single file.
- [ ] `chroot-*.bats` are under `tests/chroot/`.
- [ ] `commons-{commands,notifications,output,packages,permissions}.bats`
      are under `tests/shell/` renamed to match their `lib/shell/` module;
      `commons-part-name.bats` stays flat.
- [ ] Adapter/runner bats are under `tests/extras/`.
- [ ] Every moved file's source paths and shellcheck directives are
      rewired.
- [ ] `tests/run.sh` (recursive discovery) and `tests/shellcheck.sh` are
      green with no change to the runner.

## Blocked by

None - can start immediately.
