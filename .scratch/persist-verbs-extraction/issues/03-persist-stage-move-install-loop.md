Status: ready-for-agent

# `persist_stage_in_move`, migrate install-time loop

## Parent

`.scratch/persist-verbs-extraction/PRD.md`

## What to build

Add one function to `lib/impermanence-common.sh`:

- `persist_stage_in_move <target>` — move live data to the Persist
  Dataset via `mv`. Used by install-time materialization because the
  rolled-back dataset will lose any live copy on next boot anyway.

Refactor `lib/chroot/impermanence.sh::impermanence_apply` to compose
`persist_apply` (no reload — system is not running) +
`persist_stage_in_move` in a loop over Curated Persist Defaults and
host-declared Persist Extensions.

The existing `_impermanence_write_*` helpers covering mount units,
tmpfiles entries, and data movement collapse into calls to the shared
verbs.

Install-time outputs (units written, snapshots taken, file layout on
disk) must be byte-identical before and after for the same inputs.

## Acceptance criteria

- [ ] `persist_stage_in_move` exists in `lib/impermanence-common.sh`
- [ ] Bats test covers the move semantic against a temp `ROOT`
      (source removed, destination populated)
- [ ] `lib/chroot/impermanence.sh::impermanence_apply` composes
      `persist_apply` + `persist_stage_in_move` for curated +
      extension paths
- [ ] Duplicated `_impermanence_write_*` helpers covering mount unit
      / tmpfiles / data move are removed
- [ ] `tests/chroot-impermanence.bats` passes unmodified
- [ ] `tests/chroot-install-state-persist.bats` passes unmodified
- [ ] `tests/run.sh` and `tests/shellcheck.sh` pass

## Blocked by

- `.scratch/persist-verbs-extraction/issues/01-persist-apply-and-stage-copy.md`
