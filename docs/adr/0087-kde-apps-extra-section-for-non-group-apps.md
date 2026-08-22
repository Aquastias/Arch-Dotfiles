# ADR 0087: `apps_extra` for KDE apps outside the kde-applications group

## Status
Accepted.

## Context
`extras/desktop/kde/install-kde.jsonc` carries a mechanical membership
rule (R21): a package belongs in `apps_list` **iff** its pacman `Groups`
field contains `kde-applications`. The rule exists so membership is
verifiable, not a matter of taste.

Expanding the default KDE set to the operator's curated ~45-app list
surfaced a problem the rule could not absorb: many first-class KDE
applications are **not** in the `kde-applications` group. Verified against
archlinux.org, these carry an empty group (or a non-`kde-applications`
group) yet are unmistakably KDE apps: `krita`, `digikam`, `okteta`,
`kommit`, `krename`, `krusader`. The existing `apps_list` already
**violated** R21 by holding `krita`, `krename`, `krusader`, and `kdiff3`.

Three of the requested apps (`spectacle`, `plasma-systemmonitor`,
`discover`) are in the `plasma` group and already pulled by `plasma-meta`;
they are listed explicitly as documenting no-ops (`--needed` makes them
free), not as an R21 exception.

## Decision
Keep R21 strict for `apps_list`, and add a sibling **`apps_extra`**
section to `install-kde.jsonc` for KDE-ecosystem **repo** packages that
are *not* in the `kde-applications` group. It uses the same 2-level
Categorized List shape (`{ category: { pkg: bool } }`), is parsed in bool
mode by the same Categorized List Parser, and installs in the same pacman
pass as `apps_list` — deselectable in the Guided Installer identically.
The misplaced `krita`/`krename`/`krusader`/`kdiff3` move from `apps_list`
into `apps_extra`.

Membership rule for `apps_extra`, equally mechanical: a **repo** package
that is KDE-ecosystem but whose `Groups` does **not** contain
`kde-applications`. AUR-only KDE packages still go in the adapter's `aur`
block (unchanged); genuinely non-KDE packages still belong in a host
profile.

## Considered alternatives
- **Relax R21** to "any KDE-ecosystem app" for `apps_list`. Rejected:
  loses the mechanical, greppable membership test that made the rule worth
  having.
- **Push non-group apps to the host profile `packages.repo`.** Rejected:
  breaks ADR 0021's "the adapter owns every DE-tied package" — selecting
  KDE would no longer pull the full canonical set, and deselection would
  leave the adapter.

## Consequences
- `apps_list` regains a true, checkable invariant; `apps_extra` holds the
  KDE apps the group misses, both in the adapter, both operator-toggleable.
- Amends ADR 0021's app-list membership definition (adds a second,
  provenance-split home) without changing its ownership boundary.
