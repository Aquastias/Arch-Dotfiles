# Guided Installer install-flow buckets and Services merge

---
Status: accepted (amends ADR 0071's archinstall reading order + flat category
list; folds the root-level Printing/Bluetooth/Power categories of ADR 0079/0080
into one Services category)
---

The Guided Installer's top-level Configuration Categories are **re-ordered into
an install-flow narrative, grouped under six non-selectable bucket headers, and
the three service toggles are merged into one Services category** — taking the
list from sixteen categories to fourteen under six buckets. Menu-model plus one
top-screen render tweak; **zero back-end change** (no emit / Layer Resolver /
Package Resolver edit).

## The re-cut

ADR 0071 ordered the categories in **archinstall reading order** for free
familiarity and rejected both bucket-grouping ("full flat archinstall taxonomy")
and merging. With sixteen categories after ADR 0074/0079/0080 added Pacman,
Printing, Bluetooth and Power, the flat list stopped scanning: three one-leaf
service categories (Printing / Bluetooth / Power) sat as peers of Disks, and the
archinstall order no longer matched how an operator reasons through a build.

The categories are now sequenced as an **install-flow mental model** and set off
by bucket headers. `General` is renamed **System** as the identity anchor;
fonts stay in System (they are console + system-wide, not a desktop cosmetic).

| Bucket | Categories |
|--------|------------|
| `── SYSTEM ──` | System (hostname, timezone, fonts), Locales, Users |
| `── STORAGE & BOOT ──` | Disks, Bootloader, Kernels |
| `── SOFTWARE ──` | Environment, Mirrors & Repositories, Pacman, Packages |
| `── SERVICES ──` | Services (printing · bluetooth · power) |
| `── SECURITY & DATA ──` | Security, Backup |
| `── ADVANCED ──` | Advanced |

The **bucket headers** are a new render element on the top screen only: a
`── NAME ──` line emitted when the category's `bucket` changes. They are
non-selectable in spirit — like the existing category/action divider
(`_CTL_DIVIDER`), the cursor may land on one but Enter is a `noop` (the
top-screen Enter fallthrough finds no matching category name). The bucket is a
third column on `_MENU_CATEGORIES` (`name|summary|bucket`); no new state.

The **Services merge** needs no bespoke screen. A category is just the `section`
label its fields share, and `menu_category_rows` already filters by section —
so relabelling `options.printing.enabled` / `options.bluetooth.enabled` /
`options.power.profile` to `section = Services` yields a working drill screen for
free: power's enum drills to a values submenu, the two bools cycle in place
(ADR 0075), exactly as before. Their emit paths (toggle-derived System Programs,
ADR 0079/0080) are untouched.

### Prototype verdict

A 3-variant HTML mock (`.scratch/menu-reorg/prototype.html`, rendering the real
fzf top-screen chrome) answered "how should the list be arranged":
**V3 — grouped + merged** won over **V1** (flat, install-flow reorder only — 16
undifferentiated rows still scroll) and **V2** (grouped with all 16 kept —
scannable, but leaves a lonely one-item DESKTOP bucket). V3 folds Environment
into SOFTWARE and collapses the three service categories, reaching a tighter list
without a one-item bucket.

## Considered options

- **Keep ADR 0071's flat archinstall order (V1).** Rejected: the win of the
  re-cut is grouping; a flat 16-row list is the problem being solved.
- **Group with dividers but no merges (V2).** Rejected: keeps three trivial
  service categories as peers and manufactures a one-item DESKTOP bucket.
- **A bespoke Services drill screen.** Rejected: the shared-`section` drill
  already renders it; a new screen would duplicate the controller's field-shape
  handling.

## Consequences

- The model edits are `_MENU_CATEGORIES` (order + bucket column + merged
  Services + System rename) and the `section` labels in `_MENU_FIELDS`; the
  `menu_categories` / `menu_rows` / `menu_category_rows` contracts and every
  field path are preserved, so emit, Layer Resolver and Package Resolver are
  untouched. The Axis Registry keys on field paths, not sections, so it is
  unaffected.
- The top-screen render (`guided-controller.sh`) gains bucket-header emission;
  Enter/detail already degrade to `noop` on a non-category line.
- The [[Package Resolver]]'s display-only origin hints repoint
  printing/bluetooth/power → `Services` and fonts → `System`.
- CONTEXT.md's Guided Installer entry is updated to the fourteen categories and
  six buckets (it also caught up on Bluetooth/Power, added by ADR 0080 but not
  yet reflected there).
