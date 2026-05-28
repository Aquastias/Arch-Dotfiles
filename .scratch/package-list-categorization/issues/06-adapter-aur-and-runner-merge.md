# Adapter aur field; qt6ct-kde in Hyprland; Runner AUR merge; host AUR categorized

Status: ready-for-agent

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

- [ ] `install-hyprland.jsonc` has `aur.qt_theming.qt6ct-kde: true`.
- [ ] `install-kde.jsonc` has the `aur:` field present (may be empty
      or contain entries, but the surface exists).
- [ ] `hyprland.sh` and `kde.sh` do not install AUR packages
      themselves.
- [ ] `lib/profiles.sh` AUR pass reads adapter `aur:` lists for each
      DE in `environment.desktop[]` and merges with host
      `packages.aur` into a single deduped paru invocation.
- [ ] `hosts/core/config.jsonc:packages.aur` (if present) and
      `hosts/desktop/config.jsonc:packages.aur` are 2-level objects.
- [ ] All `packages.aur` read sites use the Categorized List Parser.
- [ ] Smoke tests cover the four Runner AUR merge cases listed above
      and pass.
- [ ] A fresh install on `hosts/desktop` with
      `environment.desktop=["kde","hyprland"]` installs `qt6ct-kde`
      from the AUR.
- [ ] A fresh install with `environment.desktop=kde` does NOT install
      `qt6ct-kde`.
- [ ] `CONTEXT.md` entries for `Desktop Environment Adapter` and
      `Environment Runner` updated.

## Blocked by

- `.scratch/package-list-categorization/issues/04-categorized-list-parser-and-host-repo.md`
