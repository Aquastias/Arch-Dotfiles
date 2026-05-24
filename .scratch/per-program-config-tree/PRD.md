Status: ready-for-agent

# PRD: Per-program config tree with variants

References: ADR 0012.

## Problem Statement

A program's identity is fractured across the repo. Today the
operator wants to find "everything kitty" but the package list lives
in a Program Config under `.os/programs/terminal/kitty/`, the
install script next to it, and the user-side config files inside the
top-level Stow Tree at `.config/kitty/`. Three locations for one
program. Worse, some programs (searxng, virt-manager) seed user
configs ad-hoc from their `install.sh` via `cp`, bypassing stow
entirely — so two mechanisms place user files, both authoritative,
neither aware of the other.

The operator also wants alternate configurations for the same
program (e.g. zsh with theme A vs theme B) selectable per user. The
current layout has no answer for this — every dotfile is the one
canonical version.

## Solution

Each program owns a Program Config Tree under
`.os/programs/<cat>/<name>/configs/`, with sibling Config Variants
named `configs@<variant>/`. A Config Manifest (`manifest.jsonc`) in
each variant declares which file goes to which user path.

User Config grows a `variants` object selecting variants per
program; User Core can declare House Defaults overridden per-key by
User Config.

A new Config Generator (`.os/tools/generate-configs.sh`) runs
per-user during install (inside `arch-chroot`, between the dotfiles
clone and stow) and post-install (standalone, for re-rendering after
variant edits). It resolves variants, validates manifests,
materializes a Generated Stow Tree at `~/.dotfiles/.stow/<user>/`,
and aborts if any planned destination collides with the legacy Stow
Tree. Stow then runs against the generated tree in addition to the
legacy one.

Migration is per-program and atomic per program: move kitty's files
into `configs/`, write the manifest, delete `.config/kitty/`. The
legacy Stow Tree stays supported indefinitely; programs cross over
one at a time.

## User Stories

1. As the operator, I want each program's user-side config to live
   next to its install logic, so that I can find everything about
   one program in one directory.
2. As the operator, I want to declare multiple alternate config sets
   for a program (e.g. minimal vs gaudy zsh), so that I can swap
   between them without editing files.
3. As the operator, I want to pick which variant a user gets in that
   user's User Config, so that two users on the same host can have
   different themes.
4. As the operator, I want to set a house-default variant in User
   Core, so that all users inherit my preferred default and only
   override when they want something different.
5. As the operator, I want the generator to fall back to the
   unsuffixed `configs/` when no variant is declared, so that
   programs with a single config "just work" with no User Config
   noise.
6. As the operator, I want the literal name `default` reserved and
   mapped to `configs/`, so that I can explicitly select the default
   without filesystem ambiguity.
7. As the operator, I want variant names restricted to
   `[a-z0-9-]+`, so that case-sensitive directory names cannot drift
   from the strings in JSONC.
8. As the operator, I want a single Config Manifest format
   (JSONC matching the rest of the repo), so that I do not learn
   YAML for one tool only.
9. As the operator, I want each manifest entry to declare only `src`
   / `dst` / optional `mode`, so that the manifest stays small and
   does not invite templating or conditionals.
10. As the operator, I want `dst` to be `~/`-rooted user paths only,
    so that system files stay the install script's responsibility
    and the impermanence layer is not bypassed.
11. As the operator, I want the generator to refuse to emit a
    destination already owned by the legacy Stow Tree, so that
    migration is atomic per program with no silent overrides.
12. As the operator, I want both the legacy and generated stow
    trees applied per user, so that I can migrate program-by-program
    without a flag day.
13. As the operator, I want the Generated Stow Tree gitignored, so
    that PRs do not include large generated diffs.
14. As the operator, I want the generator to validate manifests
    before writing anything (parse, dst-shape, src-exists, mode
    format), so that a malformed manifest fails loudly and early.
15. As the operator, I want `--dry-run` and `--validate-only`
    flags, so that I can preview a render or gate CI without side
    effects.
16. As the operator, I want the generator to discover programs by
    walking `.os/programs/*/*/configs[@*]/`, so that adding a new
    program needs no central registry edit.
17. As the operator, I want system programs with `configs/`
    applied to every user on the host, so that "this host runs
    virt-manager" implies "every user has its config."
18. As the operator, I want each user to independently pick their
    variant for a shared system program, so that a system program's
    config can still vary per user.
19. As the operator, I want secrets-laden configs (e.g.
    `~/.ssh/config`) to be plaintext in the manifest and reference
    `/run/secrets/<name>` paths, so that I do not duplicate the
    SOPS pipeline inside the generator.
20. As the operator, I want SSH private keys and other secret
    material to stay in User Secrets (handled by `create-user.sh`),
    so that no secret material enters the manifest at all.
21. As the operator, I want the Runner to invoke the generator
    inside `arch-chroot` per user, so that installs produce a
    fully-configured system without an extra manual step.
22. As the operator, I want to re-run the generator standalone
    post-install after editing a variant, so that I can iterate
    without reinstalling.
23. As the operator, I want no pacman post-transaction hook, so
    that ordinary package updates do not trigger config
    regeneration (configs are authored, not derived).
24. As the operator, I want `save-pkglist.sh` to remain
    package-only with no variant awareness, so that the package
    capture concern stays orthogonal.
25. As the operator, I want the generator to produce a clear error
    naming both source paths when a conflict with the legacy tree
    is detected, so that I know exactly which file to delete to
    complete the migration.
26. As the operator, I want the generator to error when a program
    has only `configs@*/` (no `configs/`) and the user has not
    declared a variant, so that I never silently get a half-
    configured tool.
27. As the operator, I want the existing Stow Tree to keep working
    unchanged for as long as I have not migrated a program, so
    that adopting ADR 0012 does not break any current install.

## Implementation Decisions

### Module breakdown

Seven modules. The first five are deep — pure or pure-ish logic
with simple inputs and outputs, testable without a chroot.

**Variant Resolver.** Inputs: merged user `variants` map (after
User Core + User Config merge); set of available variant dirs per
program. Output: `{program → resolved variant dir name}` or a list
of errors. Errors covered: variant declared but `configs@<x>/`
does not exist; program has only `configs@*/` and no `configs/`
and no variant declared; reserved-name violation (`configs@default/`
exists on disk).

**Manifest Validator.** Input: path to a `manifest.jsonc`.
Validations: JSONC parses; top-level has `files` array; each entry
has string `src`, string `dst`; `dst` starts with `~/`, contains no
`..`, contains no `/etc/` or `/usr/` prefix after expansion;
optional `mode` matches `^0?[0-7]{3,4}$`; `src` resolves to an
existing regular file relative to the manifest's directory. Output:
ok or a list of `(line-ish, message)` errors.

**Plan Builder.** Inputs: resolved variant map; per-variant
manifest contents; target stow root path (e.g.
`~/.dotfiles/.stow/<user>`). Output: a flat list of plan entries
`{src_abs, dst_in_stow_tree, mode?}`. No writes. Same plan feeds
materializer and dry-run renderer.

**Conflict Detector.** Inputs: plan; legacy stow tree root and the
set of legacy stow packages stowed by the Runner today (`.config`,
`.zsh`, `.claude` plus any home-relative loose files). Output: list
of conflicts `{plan_entry, legacy_path}`. Non-empty list aborts the
generator with the operator-facing message naming both sources.

**Materializer.** Inputs: plan; target stow root. Side-effects:
create directories with mode 0755 by default; copy each `src_abs`
to `dst_in_stow_tree`; apply `mode` when present. Idempotent — a
re-run with unchanged inputs produces the same tree.

**Generator CLI.** `.os/tools/generate-configs.sh`. Flags:
`--user <name>` (required), `--dry-run` (plan + validate, print
plan, no writes), `--validate-only` (validate manifests + resolve
variants, exit 0/1, no plan output, no writes). Discovers programs
by walking `.os/programs/*/*/configs[@*]/`. Reads merged user
configs via the existing User Core + User Config merge function
already used by the Runner.

**Runner integration.** Inside `_profiles_clone_dotfiles`'s sibling
flow in `profiles.sh`, after the dotfiles clone for each user and
before the existing `stow --no-folding */`, invoke
`generate-configs.sh --user <u>` inside `arch-chroot`. Then run a
second stow against the generated tree:

```
stow -d ~/.dotfiles --no-folding .config .zsh .claude    # existing
stow -d ~/.dotfiles/.stow/<u> --no-folding .              # added
```

The exact legacy package list passed to the first stow stays
whatever the Runner already does — this work does not change it.

### Schema additions

User Config and User Core gain an optional `variants` object,
string-to-string, keyed by program name:

```jsonc
{ "variants": { "kitty": "minimal", "zsh": "gaudy" } }
```

Standard deep-merge: User Core's `variants` is overridden per key
by User Config's, not whole-object replace. No other schema
changes anywhere.

### Manifest format

`manifest.jsonc` at the root of each `configs[@variant]/`. Single
top-level `files` array. Each entry: `src` (string, relative to
the manifest's directory), `dst` (string, `~/`-rooted), optional
`mode` (string, octal). No other fields are recognized; unknown
fields are a validation error so the schema cannot accrete
silently.

### Tooling consistency

JSONC is parsed via `jq` (already a dependency). All five logic
modules can be implemented as bash functions in
`.os/tools/generate-configs.sh` and `.os/lib/` helpers — no new
language runtime.

### Repo hygiene

`.gitignore` already has `.stow/` (added with ADR 0012).

## Testing Decisions

### What makes a good test

Test external behavior at the module boundary. The five testable
modules each have a small surface — give them fixture inputs and
assert on their outputs. Do not test internal helper functions, do
not test private bash variables. Tests should survive a
refactoring of the internals.

### Modules under test

Four bats files, matching existing `commons-*.bats` and
per-concern naming:

- **`configs-variant-resolver.bats`** — Variant Resolver. Fixtures:
  programs with `configs/` only, `configs@*/` only, both, neither.
  Cases: declared variant resolves, undeclared falls back to
  `configs/`, undeclared with no `configs/` errors, declared with
  no matching `configs@<x>/` errors, `configs@default/` on disk
  errors. House Defaults inherited and overridden cases.
- **`configs-manifest-validator.bats`** — Manifest Validator.
  Cases: valid manifest passes; malformed JSONC fails; missing
  `files` array fails; `dst` not under `~/` fails; `dst` with
  `..` fails; `dst` under `/etc/` fails; bad `mode` string fails;
  missing `src` file fails; unknown top-level fields fail; unknown
  per-entry fields fail.
- **`configs-plan-builder.bats`** — Plan Builder. Cases: single
  program produces one plan per file; multi-variant resolves to
  the right variant's manifest; multiple programs produce a
  combined plan; system program shared across users produces the
  per-user plan; modes pass through.
- **`configs-conflict-detector.bats`** — Conflict Detector. Cases:
  clean (no conflicts) returns empty; planned `.config/kitty/
  kitty.conf` against a legacy `.config/kitty/kitty.conf`
  detects it; planned `.config/foo` against legacy `.zsh/foo`
  does not collide (different package); plan against an empty
  legacy tree returns empty.

### Prior art

- `commons-output.bats`, `commons-commands.bats`, etc. — shape and
  helper conventions for pure-bash function tests.
- `audio-resolution.bats`, `environment-validation.bats` — pure
  resolver / validator tests over fixture JSONC inputs, very close
  shape to what Variant Resolver and Manifest Validator need.
- `configs.bats` (existing) — verify the new files do not collide
  by name and that overall configs coverage stays clean.

End-to-end integration (Runner actually invoking the generator
inside `arch-chroot`) is covered by the existing VM test harness
(`.os/tests/vm/`) — no new bats integration suite for that path.

## Out of Scope

- Templating, conditionals, hooks, or any DSL beyond the three-field
  manifest entry. Variants are the complexity axis.
- System paths (`/etc/`, `/usr/lib/`) in the manifest. Those stay
  in `install.sh` and are governed by the impermanence layer.
- Secret material in the manifest. Secrets stay in User Secrets /
  Host Secrets; the SOPS Runtime Service decrypts to `/run/secrets/`
  at boot; configs reference those paths plaintext.
- Encrypted manifest entries (`encrypted: true`). Rejected — adds a
  SOPS dependency to the generator and writes plaintext to
  `.stow/<user>/`.
- Pacman post-transaction hook re-running the generator. Configs
  are authored, not package-derived.
- `save-pkglist.sh` extensions. Variants are declared, not
  discovered — nothing to capture from a running system.
- Migration of any specific existing config (kitty, zsh, etc.).
  This PRD ships the mechanism; per-program migrations are
  separate units of work.
- Removal of the legacy Stow Tree. It remains supported
  indefinitely; only specific programs cross over when migrated.
- Changes to the Pre-Install Picker. Variants are User Config, not
  Install Config — the picker is unaffected.
- A standalone `tools/lint-manifests.sh`. Validation lives in the
  generator; a thin wrapper can be added later if CI demands it.

## Further Notes

The Generated Stow Tree at `~/.dotfiles/.stow/<user>/` is a new
artefact visible in the filesystem on every installed host. Worth
mentioning in `README.md` alongside the existing stow note when
the first program migration lands.

The reserved-name rule (`configs@default/` is illegal on disk)
should be enforced by the Variant Resolver, not assumed by
convention — the bats test must include a fixture that exercises
the rejection.

The Conflict Detector's "legacy package list" is whatever the
Runner currently passes to its first `stow` invocation. If the
Runner ever changes that list, the Conflict Detector reads from
the same source — they must not drift.
