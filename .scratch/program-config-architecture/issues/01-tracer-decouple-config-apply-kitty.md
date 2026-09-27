Status: done

# Tracer: decouple config apply + `config_exclude`, migrate `kitty`

## Parent

`.scratch/program-config-architecture/PRD.md` (ADR 0134).

## What to build

The end-to-end spine of the new model, proven on one Program (`kitty`).
`install.sh` stops seeding config; a new **Config Apply Planner** decides which
selected Programs' `home/` to apply for a user, honoring that user's
`config_exclude`; the Runner runs that plan into the user's `$HOME` (and seeds
`/etc/skel` + `/root` from the same `home/` source). `kitty` becomes
single-source under its own `home/`, with its repo-root copy removed.

Verifiable outcome: installing with `kitty` selected applies its config;
installing with `config_exclude: ["kitty"]` installs the package but applies no
config.

Apply rule (from the design prototype):
`apply(program) = ships_home(program) && !config_exclude.includes(program)`.
A Program with no `home/` is package-only and never in the plan.

## Acceptance criteria

- [x] Config Apply Planner is a pure module: `(resolved programs, ships-home
      set, config_exclude) → ordered apply plan`, no filesystem writes.
- [x] `config_exclude[]` accepted by the closed user schema; unknown keys still
      abort; empty/absent `config_exclude` changes nothing.
- [x] Runner invokes the Planner per user and applies the plan into `$HOME`;
      `/etc/skel` and `/root` seeded from the same `home/` source.
- [x] `kitty` config lives only under its Program `home/`; the repo-root copy is
      deleted; `kitty` `install.sh` installs the package and does no `$HOME`
      config seeding.
- [x] With `kitty` selected → its config is applied; with `kitty` in
      `config_exclude` → package installs, no config applied.
- [x] Planner unit tests (bats): config-applied, excluded, and package-only
      cases; empty exclude applies all. Prior art: `tests/config/*.bats`.

## Blocked by

- None — can start immediately.

## Comments

- 2026-09-27 audit: 33cf3d8 (lib/config/config-apply.sh; config-apply.bats),
  ee417a5 (kitty).
