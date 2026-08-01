# KDE apps_list holds only KDE applications

Status: ready-for-agent

## Parent

.scratch/layered-software-model/PRD.md (R10, R21)

## What to build

When KDE is selected, the installer prints "KDE Applications" and then installs
five things that are not applications. Make the section honest.

The rule is mechanical, verified against <https://apps.kde.org/> and each
package's pacman metadata: a package belongs in `apps_list` **iff** its
`Groups` contains `kde-applications`. Real applications carry
`URL: https://apps.kde.org/<name>/`; Plasma pieces carry `Groups: plasma` and
point at the plasma-desktop page; frameworks carry `Groups: kf5`.

Applying it:

- `sddm-kcm` is a config module, not an application, and is **not** in
  `plasma-meta` — it moves to the mandatory shell section.
- `xdg-desktop-portal-kde` is already in `plasma-meta`'s dependency tree.
  Remove it.
- `kimageformats5` is the **KF5** build. Plasma 6 uses `kimageformats`, already
  pulled via `kscreen`. The declared package installs a stale Qt5 parallel
  stack for nothing. Remove it.
- `pacmanlogviewer` and `octopi` are third-party Qt pacman tools, not KDE. They
  move to Host Core, and the adapter's `aur` block goes away.

Four packages needed checking past the URL field: `krusader`, `krita` and
`calligra` all have apps.kde.org pages despite non-KDE upstream URLs and stay.
`keditbookmarks` has no page but ships in the `kde-applications` group, and is
kept on the group test.

The DE-tied packages relocating **into** the adapter from the host profiles
(ADR 0021) — `papirus-icon-theme`, `qt5-wayland`, `qt6-wayland`, `xdg-utils`
and `qt6ct-kde` — go to the **shell section**, not `apps_list`. They are
DE-tied but they are not applications, and putting them in `apps_list` would
regress this fix immediately.

## Acceptance criteria

- [ ] `apps_list` contains exactly the 20 `kde-applications` entries
- [ ] The `plasma-extras` category is gone
- [ ] `sddm-kcm` installs with the Plasma shell
- [ ] `xdg-desktop-portal-kde` and `kimageformats5` are removed
- [ ] `pacmanlogviewer` and `octopi` are declared in Host Core
- [ ] The adapter's `aur` block is removed
- [ ] The five DE-tied relocations install with the shell, not as applications
- [ ] A test asserts every `apps_list` entry has `kde-applications` in its groups
- [ ] Selecting KDE installs no third-party pacman frontend

## Blocked by

- Host Core carries packages; apply the curation
