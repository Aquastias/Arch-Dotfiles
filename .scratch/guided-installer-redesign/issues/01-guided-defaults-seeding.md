# Guided defaults seeding

Status: ready-for-agent

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

- [ ] An untouched guided run (replay with no answers) emits an Effective
      Config with hostname `eterniox`, `users` = `["aquastias"]`, single
      layout, locale `en_US.UTF-8`, timezone `Europe/Bucharest`, keymap `us`.
- [ ] `aquastias` appears in the emitted/saved config explicitly — Save of an
      untouched run yields a Host Profile with a Primary User.
- [ ] locale / timezone / keymap are editable Host rows; editing one
      overrides the seed and emits the new value.
- [ ] bats over the seeded state (prior art `tests/config/guided-state.bats`).
- [ ] Existing guided replay + full bats suite stay green.

## Blocked by

None - can start immediately.
