Status: ready-for-agent

# Guided Create-user wiring for `programs_inherit` + `config_exclude`

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

Expose the two new user knobs in the Guided Installer's Users screen so an
operator can author a bare or config-opted-out user from the menu: a
`programs_inherit` bareness toggle on the Create-user form, and a
`config_exclude` surface for skipping selected Programs' config. Guided-emitted
Profiles must stay closed-schema-valid and round-trip through the resolver.

## Acceptance criteria

- [ ] Create-user form offers a `programs_inherit: false` toggle; a bare user
      created via Guided installs no Core programs.
- [ ] Users screen offers a `config_exclude` surface; an excluded Program
      installs its package but not its config.
- [ ] Guided-emitted Profiles carrying either key pass closed-schema validation
      and resolve correctly.
- [ ] Guided fzf smoke / preview coverage updated for the new affordances.

## Blocked by

- `01-tracer-decouple-config-apply-kitty.md` (`config_exclude` schema)
- `03-programs-inherit-bareness.md` (`programs_inherit` schema)
