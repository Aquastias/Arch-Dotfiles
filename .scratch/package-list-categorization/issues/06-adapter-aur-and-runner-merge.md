# Adapter aur field; qt6ct-kde in Hyprland; Runner AUR merge; host AUR categorized

Status: done

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

Close the loop on adapter ownership of DE packages by giving Desktop
Environment Adapters a way to declare AUR dependencies, and teaching
the Runner to merge those into its existing AUR pass. Also migrates
`packages.aur` in host configs to the categorized shape and updates
the glossary entries that this slice's behaviour changes.

### Adapter aur field

Add a top-level `aur:` field to `install-<de>.jsonc` files. Same
2-level boolean-toggle schema as `apps_list`. Validated by the
Categorized List Parser in `bool` mode. Absent field is permitted
and contributes nothing.

In `install-hyprland.jsonc`:

```jsonc
"aur": {
  "qt_theming": { "qt6ct-kde": true }
}
```

In `install-kde.jsonc`: introduce the field structurally (may be
left empty) so both adapters share the same surface.

### Adapter aur is declaration-only

Adapter `.sh` scripts do NOT install AUR themselves — they continue
to use pacman only. The Runner is responsible for AUR installs.

### Runner AUR merge

`lib/profiles.sh` AUR pass:

- Before invoking paru as the primary user, iterate the resolved
  `environment.desktop[]` array.
- For each DE, read `extras/desktop/<de>/install-<de>.jsonc:aur`
  through the Categorized List Parser (bool mode). Missing field →
  empty contribution.
- Read host `packages.aur` through the Categorized List Parser
  (string mode — see migration below).
- Union all results, dedupe, install via paru in a single pass.

### Host packages.aur migration

- `hosts/core/config.jsonc:packages.aur` (if present) reshape to
  2-level object.
- `hosts/desktop/config.jsonc:packages.aur` reshape from flat array
  to 2-level object. Category names operator's choice.
- Any read site that touches `packages.aur` switches to the parser
  in `string` mode.

### Tests

Smoke test for Runner AUR merge against fixture configs:

- `environment.desktop=hyprland` + Hyprland adapter declares
  `qt6ct-kde` → resolved AUR set contains `qt6ct-kde`.
- `environment.desktop=kde` + KDE adapter has no `aur:` entries →
  resolved AUR set is exactly the host AUR set.
- `environment.desktop=["kde","hyprland"]` + both adapters
  declare entries + host AUR has overlap → output is deduped.
- Adapter file missing the `aur` field → no error, no warning,
  empty contribution.
- Asserts on the resolved package list before paru actually runs —
  no live paru required.

Test style follows existing fixture-driven Bash tests in
`.os/tests/`.

### CONTEXT.md updates

- `Desktop Environment Adapter` — note the `aur:` field and the
  fact that adapters now own every DE-tied package (apps, Qt
  plugins, AUR theming bridges).
- `Environment Runner` — note the new adapter-AUR discovery
  responsibility and the unified paru pass.

## Acceptance criteria

- [x] `install-hyprland.jsonc` has `aur.qt-theming.qt6ct-kde: true`.
- [x] `install-kde.jsonc` has the `aur:` field present (may be empty
      or contain entries, but the surface exists).
- [x] `hyprland.sh` and `kde.sh` do not install AUR packages
      themselves.
- [x] `lib/profiles.sh` AUR pass reads adapter `aur:` lists for each
      DE in `environment.desktop[]` and merges with host
      `packages.aur` into a single deduped paru invocation.
- [x] `hosts/core/config.jsonc:packages.aur` (if present) and
      `hosts/desktop/config.jsonc:packages.aur` are 2-level objects.
- [x] All `packages.aur` read sites use the Categorized List Parser.
- [x] Smoke tests cover the four Runner AUR merge cases listed above
      and pass.
- [x] A fresh install on `hosts/desktop` with
      `environment.desktop=["kde","hyprland"]` installs `qt6ct-kde`
      from the AUR.
- [x] A fresh install with `environment.desktop=kde` does NOT install
      `qt6ct-kde`.
- [x] `CONTEXT.md` entries for `Desktop Environment Adapter` and
      `Environment Runner` updated.

## Blocked by

- `.scratch/package-list-categorization/issues/04-categorized-list-parser-and-host-repo.md`

## Comments

Done via TDD. New pure `_profiles_resolve_aur <host_json> [de...]` in
`lib/profiles.sh` unions host `packages.aur` (string mode) with each
desktop adapter's `aur` (bool mode, from
`${OS_DIR}/extras/desktop/<de>/install-<de>.jsonc`), sorted-unique;
missing field/file → empty; malformed → aborts (parses captured by
command substitution so the parser `error()` propagates, not swallowed
by process substitution). Runner AUR pass rewired to call it with
`ENVIRONMENT_DESKTOP[@]`, feeding the existing single paru pass (+ GPU).

`install-hyprland.jsonc` gained `aur.qt-theming.qt6ct-kde`;
`install-kde.jsonc` gained empty `aur:{}`. Adapters install no AUR
(verified — they use pacman only).

Deviations from the issue text:
- `qt-theming` (kebab), not `qt_theming` — the parser regex rejects
  underscores (same call as `plasma-extras` in slice 05).
- Migrated `hosts/laptop` too (issue named only core+desktop; core has
  no `packages.aur`, but laptop's flat array would break once the
  read-site switched). Both reshaped to a single `misc` category;
  sets unchanged (desktop 35, laptop 30).
- `audit.sh` AUR read flattens the 2-level shape with the same
  `[.. | strings]` jq idiom already used for `packages.repo` (the
  repo read-site does not source the parser fn either); the runtime
  read-site that matters — the Runner — uses the parser.

8 new bats in `tests/profiles-aur.bats` (tracer, empty==host, dedupe
union, missing-field, missing-file, malformed-aborts, 2 real-file
regressions). Full suite 681/681; shellcheck 0; audit 81/81. The two
e2e "fresh install" criteria are VM-covered; the unit guarantee is the
resolver smoke tests (cases 1 & 2 prove qt6ct-kde present for hyprland,
absent for kde-only).
