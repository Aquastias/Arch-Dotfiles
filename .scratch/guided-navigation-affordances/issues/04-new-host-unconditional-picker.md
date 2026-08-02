# ＋ New host + unconditional Profiles picker

Status: ready-for-agent

## Parent

`.scratch/guided-navigation-affordances/PRD.md`

## What to build

Make the `Profiles ▸` picker always present — even on a repo with no committed
host profiles — and lead it with a `＋ New host (start blank)` row. Selecting
`＋ New host` performs a confirm-gated, undoable **full session reset**: Config
State back to the Host Core baseline, plus clearing session-created users and
their editor forms, the password/secret manifest overrides, and any in-menu disk
bindings. This is deliberately broader than the edit-history `Reset all` (which
resets Config State only) and a distinct action, not an alias. On a fresh repo
the picker restates blank state (only `＋ New host` + `← Back`) — accepted for
a consistent entry point.

## Acceptance criteria

- [ ] The `Profiles ▸` row appears on the top screen even when hosts tree has
      no committed profiles.
- [ ] Picker leads with a `＋ New host (start blank)` row, above any committed
      profile rows.
- [ ] Choosing `＋ New host` asks to confirm before discarding session work.
- [ ] After confirming, Config State returns to the Host Core baseline AND
      session-created users, their editor forms, the secret/password manifest
      overrides, and in-menu disk bindings are all cleared.
- [ ] The reset is undoable (a single undo restores pre-reset session state).
- [ ] Committed profile rows still seed as today; only the picker's presence and
      the leading New-host row are added.
- [ ] Covered headless via `guided_ctl_list` (picker present with zero profiles;
      New-host row leads) and `guided_ctl_enter` (New-host triggers the full
      reset); prior art: `tests/config/guided-profiles-menu.bats`,
      `guided-history.bats`.

## Blocked by

- `02-action-rows-always-visible` — the `＋ New host` and `← Back` rows must
  render as visible rows in rich chrome for this to be reachable/demoable.
