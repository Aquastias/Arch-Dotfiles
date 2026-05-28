# Migrate KDE apps from desktop host config to install-kde.jsonc

Status: ready-for-agent

## Parent

`.scratch/package-list-categorization/PRD.md`

## What to build

Pure data movement. Remove all KDE-ecosystem packages currently listed
in `hosts/desktop/config.jsonc:packages.repo` and re-declare them as
defaults in `install-kde.jsonc:apps_list` (still flat at this stage —
no schema change yet). The shipped default install should remain
behaviourally identical: the same packages get installed, just from
the KDE adapter instead of the host config.

Packages to migrate from `hosts/desktop/config.jsonc:packages.repo`
into `install-kde.jsonc:apps_list` (boolean `true` defaults):

- `pacmanlogviewer` (newly added — was not in `apps_list` before)

All other KDE apps already present in `apps_list` are removed from the
host config without further changes to `install-kde.jsonc`.

Packages that stay in `hosts/desktop/config.jsonc:packages.repo` for
later slices: `plasma-meta`, `plasma-workspace`, `polkit-kde-agent`,
`kimageformats5`, `extra-cmake-modules` (these are handled by issue
03 and 04).

## Acceptance criteria

- [ ] `hosts/desktop/config.jsonc:packages.repo` no longer contains
      `ark`, `calligra`, `dolphin`, `filelight`, `gwenview`, `kate`,
      `kdiff3`, `keditbookmarks`, `kleopatra`, `kompare`, `konsole`,
      `krename`, `krita`, `krusader`, `ktorrent`, `kwalletmanager`,
      `okular`, `pacmanlogviewer`, `partitionmanager`, `skanlite`,
      `skanpage`.
- [ ] `install-kde.jsonc:apps_list` contains `pacmanlogviewer: true`
      in addition to the existing entries.
- [ ] A fresh install on `hosts/desktop` with `environment.desktop=kde`
      installs the same KDE app set as before this change.
- [ ] No schema changes to `install-kde.jsonc` or any host config.

## Blocked by

None - can start immediately.
