# Services merge — one category for printing/bluetooth/power

Status: done
Type: AFK

## Parent

.scratch/menu-reorg/PRD.md
ADR: docs/adr/0081-guided-install-flow-buckets-and-services-merge.md

## What to build

Merge the three standalone service categories — **Printing service**,
**Bluetooth**, **Power** — into a single **Services** Configuration Category.
This takes the list from sixteen categories to fourteen. No bespoke editor
screen is built: relabelling the three fields' `section` to `Services` makes the
existing `menu_category_rows` section-filter render the drill screen for free —
power's enum drills to a values submenu, printing and bluetooth are bare-bool
Cycle Fields that flip in place (ADR 0075). Their toggle-derived System Program
emit paths (ADR 0079/0080) are untouched.

Also repoint the Package Resolver's display-only origin hints so
`printing` / `bluetooth` / `power` name `Services` and `fonts` names `System`
(the "where do I change this" hint in the read-only derived section /
explain-packages).

Slots into the install-flow order from slice 01 as: … Packages, **Services**,
Security, Backup, Advanced.

## Acceptance criteria

- [ ] `options.printing.enabled`, `options.bluetooth.enabled`,
      `options.power.profile` rows report `section == "Services"`.
- [ ] `menu_categories` returns fourteen categories including one `Services`
      row (with a non-empty summary) and no `Printing service` / `Bluetooth` /
      `Power` rows.
- [ ] `menu_category_rows Services` returns exactly the three service rows.
- [ ] The Services category's aggregated `●` is set when any of the three
      toggles is overridden, and clear on a fresh state.
- [ ] Drilling Services: power drills into its none/ppd/tuned enum; printing and
      bluetooth flip in place without leaving the screen.
- [ ] `pkgres_source_origin` returns `Services` for printing/bluetooth/power and
      `System` for fonts.
- [ ] `guided-menu.bats` updated (14-category order, Services section + drill,
      merged-category ●); resolver origin assertions added; guided + resolver
      bats suites pass.

## Blocked by

- .scratch/menu-reorg/issues/01-install-flow-reorder-system-rename.md
