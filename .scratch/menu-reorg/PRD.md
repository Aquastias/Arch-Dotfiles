# PRD: Guided Installer menu re-org — install-flow buckets + Services merge

Status: done
ADR: docs/adr/0081-guided-install-flow-buckets-and-services-merge.md
Prototype: .scratch/menu-reorg/prototype.html (variant V3 selected)

## Problem Statement

The Guided Installer's top screen is a flat list of sixteen **Configuration
Categories** in archinstall reading order (ADR 0071). After Pacman (0074),
Printing (0079), Bluetooth and Power (0080) were added, the list stopped
scanning: three one-leaf service categories sit as peers of Disks, and the
reading order no longer matches how an operator reasons through a build. Nothing
groups related categories, so the operator hunts a sixteen-row list.

## Solution

Re-cut the top-level categories into an **install-flow order**, set off by six
non-selectable **bucket headers**, and merge the three service toggles
(Printing / Bluetooth / Power) into one **Services** category. `General` is
renamed **System** (identity anchor; fonts stay in it). The list goes from
sixteen categories to fourteen under six buckets. Menu-model plus one top-screen
render change; zero back-end change (no emit / Layer Resolver / Package Resolver
behaviour edit).

Bucket layout (prototype V3):

| Bucket | Categories |
|--------|------------|
| `── SYSTEM ──` | System, Locales, Users |
| `── STORAGE & BOOT ──` | Disks, Bootloader, Kernels |
| `── SOFTWARE ──` | Environment, Mirrors & Repositories, Pacman, Packages |
| `── SERVICES ──` | Services (printing · bluetooth · power) |
| `── SECURITY & DATA ──` | Security, Backup |
| `── ADVANCED ──` | Advanced |

## User Stories

1. As an operator, I want the categories ordered the way I build a machine
   (identity → storage/boot → software → services → security), so that the menu
   reads as a narrative instead of an arbitrary list.
2. As an operator, I want related categories grouped under a visible bucket
   header, so that I can jump to the right area without scanning every row.
3. As an operator, I want the print, bluetooth and power daemons under one
   **Services** category, so that service enablement lives in one place instead
   of three near-identical one-line rows.
4. As an operator, I want the identity category named **System** (hostname,
   timezone, fonts), so that its purpose is obvious at a glance.
5. As an operator opening **Services**, I want printing and bluetooth to flip in
   place (Cycle Fields) and power to drill into its enum, so that each toggle
   behaves exactly as it did as a standalone category.
6. As an operator, I want the Services category to show a `●` when any of its
   three toggles is overridden, so that the aggregated override flag still tells
   me a change lives inside.
7. As an operator moving the fzf cursor onto a bucket header, I want Enter to do
   nothing, so that headers read as labels, not selectable rows (matching the
   existing category/action divider).
8. As an operator highlighting a bucket header, I want the detail pane to stay
   sane (the category column, no field detail), so that nothing looks broken.
9. As an operator, I want the master-detail preview, drill-down navigation, undo
   /redo, Save/Export/Proceed and every field editor to keep working unchanged,
   so that the re-org is purely presentational.
10. As an operator inspecting a derived package's origin (`explain-packages` /
    the read-only `derived` section), I want printing/bluetooth/power to point
    at **Services** and fonts at **System**, so that "where do I change this"
    names the screen that actually exists.
11. As a maintainer, I want the bucket-header formatting behind a pure,
    unit-tested helper, so that the ordering + header logic is verified in
    isolation and the controller stays thin.
12. As a maintainer, I want the category-order / section contract asserted by
    tests, so that a future field move that breaks the taxonomy fails loudly.

## Implementation Decisions

- **Menu model (`lib/config/menu.sh`) is the single edit surface for the
  taxonomy.** No emit, Layer Resolver, Package Resolver behaviour, or field-path
  change. The Axis Registry keys on field paths, not sections, so it is
  unaffected.
- **`_MENU_CATEGORIES` gains a `bucket` column** (`name|summary|bucket`) and is
  reordered to the V3 layout above; the merged **Services** row replaces the
  three service rows; **General → System**. `_menu_categories_json` and
  `menu_categories` parse/emit the new `bucket` field. `menu_categories`'
  aggregated `overridden` fold is unchanged (any field whose `section` matches
  the category name).
- **`_MENU_FIELDS` section relabels only:** hostname / timezone / fonts →
  `System`; `options.printing.enabled` / `options.bluetooth.enabled` /
  `options.power.profile` → `Services`. No paths, labels, defaults, or field
  shapes change, so the Services drill screen is produced for free by the
  existing `menu_category_rows` (section filter): power's enum drills, the two
  bools are Cycle Fields (ADR 0075).
- **New deep module: `menu_top_lines <override> [baseline>]`** (pure, in
  menu.sh) returns the ordered top-screen category block with `── BUCKET ──`
  header lines interleaved (one header when the bucket changes), each category
  line formatted `"<name> — <summary>"` + `"  ●"` when overridden. This is the
  decision the prototype settled, expressed as a reduce over `menu_categories`:

  ```
  reduce categories as $c ({prev:null, out:[]};
    out += (header "── <bucket> ──" when $c.bucket != prev)
         + ["<name> — <summary>" + (● when overridden)]
    ; prev = $c.bucket)
  ```

  Keeping it in the model (not inline jq in the controller) makes it
  unit-testable and keeps the render thin.
- **Top-screen render (`lib/guided-controller.sh`)** `guided_ctl_list` top case
  emits `menu_top_lines` between the `Profiles ▸` divider and the terminal-row
  divider, replacing the inline `menu_categories | jq` category loop. The
  Profiles/divider/Proceed/Save/Export/Abort rows are unchanged.
- **Enter/detail already degrade.** `_ctl_enter_top`'s fallthrough splits on
  ` — `; a `── BUCKET ──` line has no ` — ` and matches no category name → it
  returns `noop`, exactly like `_CTL_DIVIDER`. `_ctl_detail_top` on a header
  renders the category column and finds no `menu_category_rows` → returns. No
  new controller branch is required, though a header may be matched explicitly
  for clarity if preferred.
- **Package Resolver origin labels (`lib/packages/resolver.sh`,
  `_PKGRES_SOURCES`)** repoint `printing`/`bluetooth`/`power` → `Services` and
  `fonts` → `System`. Display-only ("where to change it"); no resolution
  behaviour changes.
- **CONTEXT.md glossary** is updated to the fourteen categories + six buckets,
  the System rename, and the Services merge **when the code lands** (the
  glossary tracks the built model, per ADR 0071's precedent), not before.

## Testing Decisions

Good tests assert **external behaviour** — the JSON contract the menu model
emits and the lines the controller lists — never internal jq shape. Prior art:
`.os/tests/config/guided-menu.bats` (menu_rows / menu_categories / section
assertions) and `.os/tests/config/guided-controller.bats` (guided_ctl_list top
screen, enter directives).

- **Menu model (`guided-menu.bats`)** — update the canonical-order test to the
  fourteen names in V3 order; assert each category carries a `bucket`; assert
  hostname/timezone/fonts are `section == "System"`; assert printing/bluetooth/
  power are `section == "Services"`; assert `menu_category_rows Services`
  returns exactly the three service rows; add a `menu_top_lines` test — headers
  appear once per bucket, in order, and a category line carries its `●` when
  overridden.
- **Top-screen render (`guided-controller.bats`)** — top list shows a
  `System — ` line and at least one `── ` bucket header; Enter on a bucket
  header returns `noop`; the existing Proceed/Save/Export/Abort assertions still
  pass. Repoint the `nav_to_category/values/text General …` fixtures to
  `System`.
- **Resolver origin labels** — `pkgres_source_origin` returns `Services` for
  printing/bluetooth/power and `System` for fonts.

## Out of Scope

- Any change to emit, the Layer Resolver, the Package Resolver's resolution, or
  field paths / defaults / shapes.
- Adding, removing, or renaming any field (only `section` labels move).
- A bespoke Services editor screen — the shared-`section` drill already renders
  it.
- Making bucket headers truly unselectable in fzf (fzf has no skip; headers are
  cursor-landable but inert, consistent with `_CTL_DIVIDER`).
- The rejected prototype variants (V1 flat reorder, V2 grouped-no-merge).

## Further Notes

- The prototype (`.scratch/menu-reorg/prototype.html`) is the primary source for
  the V3 selection; capture it on a throwaway branch when the work lands.
- The `── BUCKET ──` header uses U+2500 box-drawing dashes; the category summary
  separator is ` — ` (U+2014). They must stay distinct so the Enter split never
  mistakes a header for a category.
