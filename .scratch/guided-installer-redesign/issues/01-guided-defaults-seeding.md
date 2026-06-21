# Guided defaults seeding

Status: done

## Parent

`.scratch/guided-installer-redesign/PRD.md`

## What to build

Seed the Guided Installer's launch Config State with sensible computed
defaults so an untouched run is ready for this operator. The seeder is a
pure helper over Config State (extends the existing identity seed), so it is
independent of menu rendering and survives the menu rewrite.

Defaults: hostname `eterniox`; `users[0] = aquastias` (the Primary User);
single-disk ZFS layout; locale `en_US.UTF-8`; timezone `Europe/Bucharest`;
keymap `us`. `aquastias` is emitted **explicitly** (not a strippable
default) so the host always has a Primary User. Surface locale / timezone /
keymap as editable Host rows over these seeds.

## Acceptance criteria

- [x] An untouched guided run (replay with no answers) emits an Effective
      Config with hostname `eterniox`, `users` = `["aquastias"]`, single
      layout, locale `en_US.UTF-8`, timezone `Europe/Bucharest`, keymap `us`.
- [x] `aquastias` appears in the emitted/saved config explicitly — Save of an
      untouched run yields a Host Profile with a Primary User.
- [x] locale / timezone / keymap are editable Host rows; editing one
      overrides the seed and emits the new value.
- [x] bats over the seeded state (prior art `tests/config/guided-state.bats`).
- [x] Existing guided replay + full bats suite stay green.

## Blocked by

None - can start immediately.

## Comments

**DONE via /tdd (2026-06-21).** M3 guided-defaults seeder + editable Host
identity rows, on a **baseline + override** Config-State layering (grilled).

New pure core `lib/config/seed.sh` — `cfgstate_seed_defaults <state>` returns the
launch defaults (hostname `eterniox`, `users=["aquastias"]`, `mode=single`,
locale `en_US.UTF-8` / timezone `Europe/Bucharest` / keymap `us`). Tested in new
`tests/config/guided-seed.bats` (+4).

Baseline/override split (the key design): the seed is a **default layer**, not an
override. `_GUIDED_BASELINE` (session constant) holds the seed; `_GUIDED_STATE`
stays the operator's sparse OVERRIDE map (empty at launch). So a fresh run carries
**no ●** (is_overridden = key in override only), yet still emits — `_guided_
effective` merges `BASELINE * STATE` (jq `*`, override REPLACES baseline arrays so
a seeded user can be dropped) and feeds emit / Save / the hostname+mode reads.
Reset just drops the override → the baseline still supplies locale/timezone, so
Reset can no longer strip the back-end-required identity (the dissolved footgun).

guided.sh: `_guided_set_identity` seeds the baseline; `_guided_effective` helper;
emit/Save/hostname/mode reads routed through it; `_guided_seed_primary_user`
pre-selects `aquastias` as the committed Primary User (build + reset-all) so an
ad-hoc add keeps aquastias first (drop it by re-picking committed users without
it). New `_guided_edit_{locale,timezone,keymap}` reuse `_guided_edit_scalar`;
loop label-dispatch + the replay branch route them.

menu.sh: `menu_rows <override> [<baseline>]` — value is `baseline*override`, ● is
override-only; three new `Host` rows (locale/timezone/keymap). state.sh / emit.sh
/ history.sh / guided-save.sh unchanged. Saved profiles stay self-contained
(emit/Save bake the baseline), and every seeded path is in the closed host schema
(the untouched-Save test asserts it validates).

Adjusted existing tests to the layered model: Reset-all now asserts the override
clears and the effective hostname falls back to the seed; the ad-hoc materialize
test expects `["aquastias","carol"]`. Added: menu baseline (no-●) test, a
freshly-seeded `_guided_menu_lines` no-● test, and a reset-falls-back-to-seed
regression test.

VM smoke deferred to issues 04/05 (per grill): this sandbox has no `/dev/kvm`,
and seeding `aquastias` makes a guided install pull its AUR set — heavier than the
old "fast, no-AUR" guided smoke; issue 04 prunes aquastias and carries the
secure-baseline boot-verify. Guided VM fixtures' `timezone` updated UTC →
Europe/Bucharest for consistency with the new seed.

Tests: guided-seed (+4), guided-menu (+2), guided-shell (+8). Full non-VM suite
**1122 bats**, shellcheck clean. fzf draw stays smoke-only; replay exercises the
assembly deterministically.
