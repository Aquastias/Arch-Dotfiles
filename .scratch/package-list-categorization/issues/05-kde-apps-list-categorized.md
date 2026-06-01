# Migrate install-kde.jsonc:apps_list to categorized shape; add plasma_extras category

Status: done

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

Switch the KDE adapter's `apps_list` consumption from flat
boolean-map traversal to the Categorized List Parser, and reshape
the JSONC file accordingly.

Changes to `kde.sh`:

- Replace the current `jq '.apps_list | to_entries[] | select(...)'`
  pipeline with a call to the Categorized List Parser in `bool` mode
  over `apps_list`.

Changes to `install-kde.jsonc`:

- Reshape `apps_list` from a flat `{ pkg: bool }` map to a 2-level
  `{ category: { pkg: bool } }` object.
- Introduce a `plasma_extras` category containing `sddm-kcm`,
  `kimageformats5`, `xdg-desktop-portal-kde` (all defaulted `true`)
  — these moved into `apps_list` by issue 03 as top-level entries,
  now grouped under the new category.
- Remaining KDE applications grouped into operator-chosen categories
  (cosmetic). Category names must match `^[a-z0-9-]+$`.
- All existing entries keep their current default value (`true`).

## Acceptance criteria

- [x] `kde.sh` reads `apps_list` via the Categorized List Parser
      (bool mode); no direct `jq` traversal of the old shape remains.
- [x] `install-kde.jsonc:apps_list` is a 2-level object with at least
      a `plasma-extras` category containing `sddm-kcm`,
      `kimageformats5`, `xdg-desktop-portal-kde` — all `true`.
- [x] Every KDE app present in `apps_list` before this change is
      still present, under some category, defaulted `true`.
- [x] A fresh install on `hosts/desktop` with
      `environment.desktop=kde` installs the same KDE app set as
      before this change.
- [x] A malformed `apps_list` (wrong shape, invalid category name,
      non-bool leaf) fails the install with a precise error from the
      parser.

## Blocked by

- `.scratch/package-list-categorization/issues/03-kde-adapter-ownership-refactor.md`
- `.scratch/package-list-categorization/issues/04-categorized-list-parser-and-host-repo.md`

## Comments

Done via TDD. `kde.sh` now sources `lib/categorized-list.sh` and reads
`apps_list` in bool mode via command substitution (not process
substitution) so a parser `error()` aborts the install. `KDE_JSON` made
injectable for tests. `install-kde.jsonc` reshaped to 2-level; count
line now reuses the parsed list. `lib/chroot.sh` stages
`categorized-list.sh` into `/root/lib` for chroot runtime.

Deviation: category named `plasma-extras` (kebab), not `plasma_extras`
— the parser regex `^[a-z0-9]+(-[a-z0-9]+)*$` rejects underscores, and
the issue's own rule says `^[a-z0-9-]+$`. Confirmed with operator.

7 new bats in `tests/kde-adapter.bats` (select, deselect, plasma-extras,
3 malformed, 24-app regression lock). Full suite 673/673; shellcheck 0;
audit 81/81.
