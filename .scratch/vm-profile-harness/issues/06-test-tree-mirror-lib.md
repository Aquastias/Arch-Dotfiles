# Test-tree mirror lib/ (non-vm)

Status: done

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

- [~] `tests/wipe/` holds the `lib/wipe/` module bats. The flat
      `wipe-*.bats` were NOT removed: they test live functions in flat
      `02-wipe.sh` and are not duplicated by `tests/wipe/`. Kept flat per
      the issue's own "flat vs folder by what it sources" rule. See Comments.
- [x] `chroot-*.bats` are under `tests/chroot/`.
- [x] `commons-{commands,notifications,output,packages,permissions}.bats`
      are under `tests/shell/` renamed to match their `lib/shell/` module;
      `commons-part-name.bats` stays flat.
- [x] Adapter/runner bats are under `tests/extras/`.
- [x] Every moved file's source paths and shellcheck directives are
      rewired.
- [x] `tests/run.sh` (recursive discovery) and `tests/shellcheck.sh` are
      green with no change to the runner.

## Blocked by

None - can start immediately.

## Comments

Wipe deviation (human-decided: keep flat). Investigation found the four
flat `wipe-*.bats` (`wipe-live-medium`, `wipe-probe`, `wipe-select`,
`wipe-prior-install-state`) are LIVE coverage of functions still defined
and called in flat `02-wipe.sh`: `detect_disks`, `select_disks`,
`parse_disk_selection`, `parse_args`, `_wipe_probe_disk`,
`skip_zeroed_disks`, `_wipe_mounts_under_mnt`, `_wipe_pools_altroot_mnt`.
The foldered `tests/wipe/*.bats` cover DIFFERENT `lib/wipe/` functions
(`wipe_method`, `wipe_disk_dirty`, `wipe_select_to_wipe`,
`wipe_resolve_targets`, `progress_*`). "prior-install-state" (mounts at
/mnt, altroot pools) != "prior-state" (disk dirtiness) — not a duplicate.
The PRD's "drop the stale four / dedupe prior-state" rested on a false
premise; deleting would drop real 02-wipe.sh coverage. Per the issue's own
rule (a test of a flat root script stays flat) they remain flat. No wipe
files changed. Full suite 963 ok / 0 fail (unchanged total → no coverage
lost). Revisit if 02-wipe.sh is later thinned onto lib/wipe.
