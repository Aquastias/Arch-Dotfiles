# Evict Host Package List from Host Core + fix System Program contract

Status: ready-for-agent

## Parent

`.scratch/host-package-cleanup/PRD.md`

## What to build

Bring Host Core back in line with ADR 0007 and the CONTEXT.md glossary:
Host Core declares users, System Programs, and Sysctl Defaults — never a
Host Package List.

Reduce `hosts/core/config.jsonc` to `users`, `system_programs: ["cups"]`,
and the existing `sysctl` block, and delete its entire `packages` object.
This also fixes the current System Program contract violation: the edited
core lists `base`, `base-devel`, `cronie`, and `parallel` under
`system_programs`, none of which resolve to a Program with `system: true`,
so program preflight (`validate_program`) would abort the install. `cups`
is the only valid System Program and stays. `extra-cmake-modules` is
dropped (a pure makedepend paru resolves at build time); `parallel` leaves
core and is picked up by the host-config cleanup slice.

## Acceptance criteria

- [ ] `hosts/core/config.jsonc` has no `packages` object.
- [ ] `system_programs` is exactly `["cups"]`.
- [ ] `sysctl` (vm.swappiness) is retained; `users` retained.
- [ ] Program preflight passes for a host built on core (no
      contract-violation abort).
- [ ] `configs.bats` covers Host Core merging with a host config when
      core carries no `packages` object, and stays green.

## Blocked by

None - can start immediately.
