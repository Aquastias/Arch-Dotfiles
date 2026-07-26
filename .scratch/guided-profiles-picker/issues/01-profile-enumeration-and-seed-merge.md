# Pure core: profile enumeration + seed-merge

Status: ready-for-agent

## Parent

.scratch/guided-profiles-picker/PRD.md
ADR: docs/adr/0055-guided-profiles-picker-and-default-secret-posture.md

## What to build

The two pure helpers the Profiles picker stands on, testable with no TTY:

- **Enumeration** — given the `hosts/` root, return the installable Host Profiles:
  directories containing a `profile.jsonc`, **excluding `core`** (the merge base)
  and the **`vm/` tree** (harness fixtures, ADR 0035), **alphabetical**. For each,
  also return the leading `//` header-comment block (the prose atop
  `profile.jsonc`), or an empty value when there is none.
- **Seed-merge** — given a parsed profile delta and the seeded launch Config
  State, return the Config State with the profile merged over the baseline using
  the same jq `*` deep merge as `cfgstate_seed_defaults` / the guided
  effective-state read. Device paths are not part of the seed (profiles are
  device-less, ADR 0036).

No menu, no fzf — just JSON/text in, JSON/text out.

## Acceptance criteria

- [ ] Enumeration returns `desktop` and `laptop` from the real `hosts/` tree
- [ ] Enumeration excludes `core` and everything under `vm/`
- [ ] Enumeration is alphabetical and stable
- [ ] Each entry carries its `//` header-comment text; a header-less fixture
      yields an empty/absent comment value (the caller renders the fallback)
- [ ] Seed-merge over a seeded state yields a Config State whose fields equal the
      profile's values, with untouched fields retaining the seed
- [ ] Seed-merge introduces no device paths into the state
- [ ] bats coverage over a fixture `hosts/` tree; behaviour-only assertions
      (emitted names/text/state), prior art `guided-seed.bats` / `guided-state.bats`

## Blocked by

- None — can start immediately.
