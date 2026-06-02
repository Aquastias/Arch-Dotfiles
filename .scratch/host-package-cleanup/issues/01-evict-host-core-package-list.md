# Evict Host Package List from Host Core + fix System Program contract

Status: done

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

- [x] `hosts/core/config.jsonc` has no `packages` object.
- [x] `system_programs` is exactly `["cups"]`.
- [x] `sysctl` (vm.swappiness) is retained; `users` retained.
- [x] Program preflight passes for a host built on core (no
      contract-violation abort). `cups` is `system: true`.
- [x] `configs.bats` covers Host Core merging with a host config when
      core carries no `packages` object, and stays green.

## Blocked by

None - can start immediately.

## Comments

- Done (TDD). `hosts/core/config.jsonc` reduced to `users`,
  `system_programs: ["cups"]`, and `sysctl`; the entire `packages` object
  (and the bloated `system_programs`) removed; header note added pointing
  packages to host configs / the Base Package List (ADR 0007).
- Tests: +2 `configs.bats` real-core shape guards (no `packages`,
  `system_programs == ["cups"]`) + 1 merge guard (core sans packages
  preserves host packages). Verified `cups` resolves `system: true`, so
  preflight passes.
