Status: ready-for-agent

# PRD: Per-program config `home/`, decoupled install + user bareness flag

References: ADR 0134 (supersedes ADR 0012, amends ADR 0095), ADR 0056/0057
(layer merge + `packages.inherit`), ADR 0095 (installer seeds, never stows).
Design prototypes (throwaway, kept as primary sources):
`.scratch/program-config-architecture/prototype.html`,
`prototype-no-core.html`.

## Problem Statement

As the operator I hit three linked frictions:

1. Selecting a Program forces its config. `install.sh` installs the package
   **and** seeds the config in one code path, so I cannot install a Program's
   package but skip its config.
2. A Program's config lives in two authored places kept byte-identical by a
   drift test — the Program's own `home/` bundle (what `install.sh` seeds from)
   and the repo-root stow tree. Two sources, one truth, a test to hide it.
3. A user cannot start bare. A host drops its base with one flag
   (`packages.inherit: false`), but a user has no equivalent — only per-item
   `programs_exclude`. So "a user with nothing from Core" means excluding all
   nine User Core programs by name, which silently goes stale when Core grows.
   `minimal` proves the cost: it is bare at the host layer yet its user still
   installs the full workstation userland onto a headless box.

## Solution

Each Program owns its user config in exactly one place —
`programs/<cat>/<name>/home/`, a plain subtree that mirrors `$HOME`. Config
application is separated from package install: `install.sh` installs the
package and does build/system work only; a single, uniform, selection-driven
pass applies each selected Program's `home/`, honoring a per-user
`config_exclude`. The operator applies the same source by hand with a
`./stow-configs` wrapper (`--except <prog>` to opt out). Users gain a
`programs_inherit: false` flag mirroring the host's `packages.inherit`, so a
user can start with no Core programs and take only what it names. The repo-root
stow tree, its drift test, and the dormant ADR-0012 generator are deleted.

## User Stories

1. As the operator, I want each Program's user config under its own `home/`,
   so that everything about a Program lives in one directory.
2. As the operator, I want `install.sh` to install the package only, so that
   selecting a Program never forces its config onto me.
3. As the operator, I want a Program's config applied by a separate pass, so
   that config is its own axis, independent of package install.
4. As the operator, I want `config_exclude` in a User Profile, so that a user
   installs a Program's package but skips its config.
5. As the operator, I want an empty `config_exclude` to change nothing, so
   that existing Profiles behave exactly as before.
6. As the operator, I want a `./stow-configs` wrapper, so that on any machine I
   clone the repo and apply all my configs with one command.
7. As the operator, I want `./stow-configs --except <prog>`, so that I can
   apply everything but one Program's config in one flag.
8. As the operator, I want `./stow-configs <prog…>` to apply only named
   Programs, so that I can stow a subset.
9. As the operator, I want `./stow-configs` to use `--adopt`, so that it works
   whether `$HOME` is empty or already installer-seeded (same bytes).
10. As the operator, I want new Programs picked up by convention (a `home/`
    dir present), so that adding a Program needs no registry edit.
11. As the operator, I want a Program with no `home/` treated as package-only,
    so that most system Programs need no change.
12. As the operator, I want config edited under the Program's `home/` to be
    the single source, so that there is no second copy and no drift test.
13. As the operator, I want `zsh` to pre-warm its zinit cache from its own
    `home/` into a throwaway `ZDOTDIR`, so that the cache warms at install
    without seeding my `$HOME`.
14. As the operator, I want `/etc/skel` and `/root` seeded by the same pass
    from the same `home/`, so that later users and root get a working default
    from one source.
15. As the operator, I want `programs_inherit: false` in a User Profile, so
    that a user starts with no Core programs.
16. As the operator, I want `programs_inherit: false` scoped to `programs`
    only, so that a bare user still inherits `groups`, `shell`, `sudo`, and
    `ssh_authorized_keys` from User Core.
17. As the operator, I want `programs` to stay a JSON array with
    `programs_inherit` as a sibling key, so that existing User Profiles and
    the closed schema do not break.
18. As the operator, I want the closed schema to accept `config_exclude` and
    `programs_inherit`, so that a Profile using them loads instead of aborting.
19. As the operator, I want the closed schema to still reject unknown keys, so
    that a typo is caught before any disk write.
20. As the operator, I want the Guided Installer's Create-user form to expose
    a bareness toggle and a `config_exclude` surface, so that I can author a
    bare or config-opted-out user from the menu.
21. As the operator, I want a bare host and a bare user to be two flags
    (`packages.inherit: false` + `programs_inherit: false`), so that "nothing
    from Core" is explicit and future-proof.
22. As the operator, I want `minimal` to be minimal end-to-end, so that a
    headless install does not carry a workstation userland.
23. As the operator, I want the ADR-0012 generator, `generate-configs.sh`, the
    `.stow` plumbing, and the drift test removed, so that dead machinery does
    not confuse the next reader.
24. As the operator, I want migration to be per-program, so that I move one
    Program at a time with no flag-day.
25. As the operator, I want `kitty` migrated first as a tracer, so that the
    pass, the wrapper, and `config_exclude` are proven on a small surface
    before `zsh`.
26. As the operator, I want the Runner's config pass to honor each user's
    resolved `config_exclude`, so that install-time and day-2 opt-out agree.

## Implementation Decisions

Locked forks (from grilling): `programs_inherit` is **scoped to `programs`**
(identity keys still inherit); the key is named **`programs_inherit`** (sibling
to `programs`, never a `{inherit,list}` object); `./stow-configs` **defaults to
all** Programs with a `home/` plus `--except`; migration starts with
**`kitty`**, `zsh` last.

**Deep modules (pure, unit-tested):**

- **Config Apply Planner.** Input: a user's resolved program list, which
  Programs ship a `home/`, and the user's `config_exclude`. Output: an ordered
  apply plan (which Programs' `home/` to apply for this user). No filesystem
  writes, no chroot. The apply rule, distilled from the prototype:
  `apply(program) = ships_home(program) && !config_exclude.includes(program)`.
  A Program with no `home/` is package-only and never in the plan.
- **Layer Resolver — `programs_inherit` branch.** Extend the existing pure jq
  resolver: when a user layer sets `programs_inherit: false`, drop the lower
  layer's `.programs` before the fold, mirroring the existing
  `packages.inherit == false` handling for hosts. Scoped to `.programs`;
  `groups`/`shell`/`sudo`/`ssh_authorized_keys` still fold normally.
- **Closed-schema validator — user keys.** Add `config_exclude[]` and
  `programs_inherit` (bool) to `_PROFILE_SCHEMA_user`. Unknown keys still abort.
- **stow-configs discovery/filter.** Pure: given the programs root and the
  `--except` / positional args, produce the ordered list of Programs to stow
  (those with a `home/`, minus excludes, or exactly the named subset). Split
  from the `stow` side effect so the selection logic is testable.

**Shallow / integration (not unit-tested):**

- **Runner config-apply pass.** Invoke the Planner per user after the base is
  in place; apply the plan into the user's `$HOME`, and seed `/etc/skel` +
  `/root` from the same `home/` source. Honors resolved `config_exclude`.
- **Per-program `install.sh` de-seeding + `home/` migration.** Strip the
  `cp … $HOME` config-seed blocks; `zsh` keeps a throwaway-`ZDOTDIR` build-time
  read of its own `home/` for cache-warming. Migrate `kitty` first, then the
  rest, `zsh` last.
- **Guided Create-user wiring.** A bareness toggle (`programs_inherit`) and a
  `config_exclude` surface on the Users screen, kept closed-schema-valid.
- **Deletions.** `lib/config/generator.sh`, `tools/generate-configs.sh`, the
  Runner's `.stow/<user>` stow line and its gitignore entry, and the
  `home/`-vs-repo-root drift test.

**Schema changes.** User Profile gains optional `config_exclude` (array of
program names) and `programs_inherit` (bool, default true). No host schema
change. `programs` stays an array.

**Open decision (carry into a ticket).** `minimal` should declare a bare
**server user** rather than reuse `aquastias` (whose own `docker`/`teamspeak3`
programs and `docker`/`libvirt`/`kvm` groups + sudo survive even under
`programs_inherit: false`). Recommended, not yet locked.

## Testing Decisions

Good tests assert **external behavior**, not implementation: feed a module its
inputs and assert its output, never its internal calls. The four deep modules
are pure and get bats unit tests:

- **Config Apply Planner** — table of `(programs, ships-home set, exclude) →
  expected plan`: config applied, config skipped-because-excluded, and
  package-only (no `home/`) cases; empty `config_exclude` applies all.
- **Layer Resolver `programs_inherit`** — `programs_inherit: false` yields no
  inherited programs while `groups`/`shell` still inherit; absent flag behaves
  as today; a user re-adding a program after a bare base still lands it.
- **Closed-schema validator** — `config_exclude` and `programs_inherit`
  accepted; an unknown user key still aborts with its path; `programs` as an
  object is rejected.
- **stow-configs discovery/filter** — default lists all Programs with a `home/`;
  `--except` subtracts; positional args select exactly that subset; a Program
  without `home/` never appears.

**Prior art.** `.installer/tests/config/*.bats` (`profile-loader.bats`,
`kitty-program.bats`, `guided-packages.bats`), the Layer Resolver
classification/coverage test, and the removed generator's unit tests. The
Runner pass and per-program migrations are covered by the existing VM harness,
not unit tests.

## Out of Scope

- **Config variants** (`configs@<variant>/`, per-user variant selection). ADR
  0012's variant feature is dropped, not reimplemented; if wanted later it is a
  separate `home@<variant>/` sibling, its own PRD.
- **System-path config** (`/etc`, `/usr`). Stays in `install.sh` +
  impermanence, unchanged.
- **Templating, conditionals, or secrets in config.** `home/` holds static
  files; runtime secrets stay behind `/run/secrets/<name>` (SOPS Runtime
  Service).
- **Changing the host `packages.inherit` mechanism.** Reused as the precedent,
  not altered.
- **`dotfiles_repo` / installer-stows-for-you.** ADR 0095 stands: the installer
  seeds; the operator stows.

## Further Notes

- Backward compatibility: every new key is additive and defaults to today's
  behavior, so committed Profiles (`core`, `aquastias`, `vm-*`, all hosts) are
  untouched until they opt in.
- "Nothing from Core" is two flags by design because Host Core and User Core are
  independent folds — documented in ADR 0134 so it is not a later surprise.
- Migration is unbounded in time and per-program; the repo-root stow tree and a
  Program's `home/` never both author the same file (the drift test's job goes
  away because the second author does).
