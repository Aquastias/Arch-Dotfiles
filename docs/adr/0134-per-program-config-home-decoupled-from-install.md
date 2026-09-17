# ADR 0134: Per-program config `home/`, decoupled install + bareness flag

## Status
Accepted — not yet implemented (forward-looking; migration is incremental).
Supersedes ADR 0012 (per-program config tree with variants). Amends ADR 0095
(single source moves from the repo-root stow tree into each program's `home/`;
the installer still seeds a working default and still never stows).

Design was explored with two throwaway logic prototypes kept as primary
sources under `.scratch/program-config-architecture/` (`prototype.html`,
`prototype-no-core.html`).

## Context

Three problems, all felt by the operator, all rooted in the same coupling.

1. **Config-seed is welded to package-install.** A Program's `install.sh`
   installs its package *and* seeds its config in the same code path
   (`cp -r payload/. ~/…`). Selecting a Program therefore forces its config —
   there is no way to install the package and skip the config. This was the
   originating complaint.

2. **Config has two authored homes kept identical by a drift test.** For
   `zsh`/`kitty`/`lazygit`/`yazi` the config exists both under the Program
   (`programs/<cat>/<name>/home/`, what `install.sh` seeds from) *and* in the
   repo-root stow tree (`.zsh/`, `.config/kitty/`, …). A test enforces they
   stay byte-identical. Two sources, one truth, a test to paper over it.

3. **Bareness is asymmetric between hosts and users.** A host goes bare with
   one flag (`packages.inherit: false`, ADR 0056). A user has no equivalent —
   the only opt-out is `programs_exclude`, per-item. So "a user with nothing
   from Core" means excluding all nine User Core programs by name, which goes
   stale the moment Core grows. The `minimal` profile exposes the bug
   concretely: `packages.inherit: false` strips the *host* base, but its
   declared user still extends User Core and installs the full workstation
   userland (kitty, yazi, virt-manager, searxng+podman, pi, claude,
   teamspeak3) onto a headless box. `minimal` is minimal at the host layer and
   a workstation at the user layer.

ADR 0012 addressed (2) with a manifest + generator + generated stow tree +
variants, kept coexisting with the legacy tree indefinitely. It was accepted,
partially coded (`lib/config/generator.sh`, `tools/generate-configs.sh`), never
wired into the Runner, and migrated zero programs. It also never addressed (1)
or (3): it *auto-applies* a Program's config for every declared Program, so it
gives config-*swap* (variants), not config-*skip*.

## Decision

### Single source: the Program's `home/`
Each Program's user-side config lives in exactly one place,
`programs/<cat>/<name>/home/`, a plain subtree that mirrors `$HOME`. The
directory layout *is* the manifest — no `src`/`dst` JSON, no generator, no
generated tree, no variants. A Program with no `home/` is package-only. The
repo-root stow tree and its drift test are deleted; migration is per-program
(move files into `home/`, drop the root copy), no flag-day (ADR 0095's
coexistence intent is preserved, minus the second *authored* copy).

### Decouple config-apply from package-install
`install.sh` installs the package and does genuine build/system work only. It
never seeds user config. Config application becomes a separate, uniform,
selection-driven pass with two entry points over one source:

- **Install time** — the Runner applies each selected Program's `home/` for
  each user, honoring that user's `config_exclude`.
- **Day 2** — `./stow-configs [program…]` (a thin repo-root wrapper looping
  `stow -d <prog> -t ~ --adopt --no-folding home` over Programs that ship a
  `home/`). `--adopt` makes it safe whether `~` is empty or already
  installer-seeded (same bytes, single source).

A Program that needs its own config *during* install (`zsh` pre-warms the
zinit cache) reads from its `home/` into a throwaway `ZDOTDIR`, never into the
user's `$HOME`.

### Opt-out is first-class
`config_exclude[]` (new per-user Profile key) skips a Program's config while
its package still installs — the install-time twin of `./stow-configs
--except`. Default empty ⇒ every selected Program's config applies, i.e. no
behaviour change for existing Profiles.

### Symmetric bareness
Users gain an `inherit` boolean mirroring the host's `packages.inherit`. A user
with `"inherit": false` starts from nothing and takes only what it names,
extending neither User Core nor its programs. `programs` stays an **array**;
`inherit` is a **sibling key**, never a reshape of `programs` into an object
(that would break the closed schema, all committed user Profiles, the Layer
Resolver, and validation at once). `minimal` sets it on its user (or declares a
bare server user) and is finally minimal end-to-end.

### Discovery by convention
A Program ships config iff it has a `home/` dir. No registry, no
`config.jsonc` flag — adding a Program needs no central edit. The Runner and
`./stow-configs` walk the same glob.

## Considered alternatives

- **Finish ADR 0012 as written** (manifest + generator + variants, dual trees
  forever). Rejected: more machinery than the problem needs, keeps two trees
  (the confusion), and still never delivers config-*skip*.
- **Drop Core entirely; every user a flat additive list** (prototyped in
  `prototype-no-core.html`). Rejected: with a nine-program User Core the
  duplication tax is real (re-declare the base per user) and machine daemons
  lose their host home. Core earns its keep; the missing piece was a per-user
  bareness flag, not the removal of inheritance.
- **Stow-only, no install-time seed.** Rejected: breaks `/etc/skel`, `/root`,
  and non-stowing users, reverses ADR 0095, and lets the installer take over
  `~`. Seed (installer's working default) and stow (operator's live config)
  serve different actors over one source; both stay.
- **`programs` as `{ inherit, list }` object.** Rejected: breaks the closed
  schema and every existing user Profile. Sibling `inherit` key instead.

## Consequences

- `programs/<cat>/<name>/` becomes the single discoverable home for a Program:
  metadata, install logic, **and** its user config — no parallel root tree.
- The originating problem is closed: install a package, skip its config, per
  user, at install (`config_exclude`) or after (`--except`).
- "New host + new user, nothing from Core" becomes a two-flag operation
  (`packages.inherit: false` on the host, `inherit: false` on the user) instead
  of a stale nine-item exclude list. It is two flags because Host Core and User
  Core are independent folds — stated here so it is not a later surprise.
- Implementation is pending and touches: every seeding `install.sh` (strip the
  `cp … $HOME` blocks; `zsh` keeps a throwaway-`ZDOTDIR` build-time read); the
  Runner (new config-apply pass honoring `config_exclude`; `/etc/skel` + `/root`
  move into it); the closed schema (`_PROFILE_SCHEMA_user` gains
  `config_exclude[]` and `inherit`); the Layer Resolver (a user `inherit: false`
  branch mirroring the host `packages.inherit` handling); the Guided Installer
  (a Create-user bareness toggle + `config_exclude` surface, kept
  closed-schema-valid); the docs; and deletion of `lib/config/generator.sh`,
  `tools/generate-configs.sh`, the `.stow` plumbing, and the drift test.
- Existing committed Profiles are forward-compatible: the new keys are additive
  and default to today's behaviour; only Profiles that opt in are affected.
