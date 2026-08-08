# Guided Installer: master-detail layout + moderate taxonomy re-cut

---
Status: ready-for-agent
---

Decision record: ADR 0071. Prototype:
`.scratch/guided-master-detail-redesign/prototype.html` (throwaway).

## Problem Statement

The operator running the **Guided Installer** wants the archinstall feel they
liked: a category list where the pane beside it always shows what the highlighted
item holds — its current values, or a data summary at a leaf — so they never have
to enter a screen just to see what is set. Today's menu is a bare drill-down: the
preview pane lights up on only one screen (the Disk layout), so on every other
category the operator must open the screen to learn its state, and the top-level
**Options** category is a junk drawer (kernel + bootloader + mirrors + ssh +
sysctl + multilib) that reads nothing like archinstall's clear, single-purpose
categories. There is also no persistent sense of place while drilling.

## Solution

The Guided Installer adopts an archinstall-style **master-detail** presentation
on the existing single fzf, and re-cuts its Configuration Categories from eight
to twelve so each category is single-purpose and named the way archinstall names
it. The right-hand preview pane becomes an **always-on detail column**: at every
level it renders the **parent column** (greyed, the current item marked) above a
**live summary** of the highlighted item — a `key: value` list for a category,
sub-values for a sub-group, and current-value-plus-options (or a rich Disks
pool tree / Users account table) at a leaf. Navigation stays drill-down (Enter
deeper, Esc up), matching archinstall's own behaviour, but the operator always
sees where they are and what the highlighted item holds without opening it.

Nothing about the install back-end changes: only menu `section` labels, the
category list, and the preview render move. Reflector, the Layer Resolver, the
Package Resolver and every field path are untouched.

## User Stories

1. As an operator, I want the category I highlight to show its current values in
   the side pane, so that I can read the whole config without opening each screen.
2. As an operator, I want a leaf field to show its current value and the allowed
   options in the side pane, so that I know what I can change it to before I do.
3. As an operator, I want the Disks category to preview its ZFS pool / topology
   tree, so that I can see the layout at a glance.
4. As an operator, I want the Users category to preview the account table
   (name, shell, sudo, groups), so that I can review accounts without drilling in.
5. As an operator, I want the parent column to stay visible (greyed, current item
   marked) while I look at a child, so that I never lose my place.
6. As an operator, I want Enter to drill into a category and Esc to go back up,
   so that navigation behaves like archinstall.
7. As an operator familiar with archinstall, I want the categories named and
   ordered as archinstall names them (Locales, Mirrors & Repositories, Disks,
   Bootloader, Kernels, System, Users, Environment, Packages, Security, Backup,
   Advanced), so that I can find things where I expect.
8. As an operator, I want a dedicated **Locales** category holding language and
   keymap, so that locale settings aren't buried under a Host grab-bag.
9. As an operator, I want a dedicated **System** category holding hostname and
   timezone, so that machine identity is one clear place.
10. As an operator, I want a dedicated **Mirrors & Repositories** category holding
    the mirror countries and multilib toggle, so that repo/mirror config is one
    place — and I want its detail pane to state that the countries drive reflector's
    mirror ranking, so that I understand what the selection does.
11. As an operator, I want a dedicated **Bootloader** category and a dedicated
    **Kernels** category, so that each is a single obvious choice.
12. As an operator, I want kernel-hardening **sysctl** to live under **Security**,
    so that hardening knobs are grouped with the other hardening choices.
13. As an operator, I want the leftover advanced knobs (ssh, age key url) under a
    small honestly-named **Advanced** category, so that there is no junk drawer.
14. As an operator, I want an `●` override dot shown against any field (and its
    category) I have changed from the seeded default, in both the list and the
    detail pane, so that I can see my deltas at a glance.
15. As an operator, I want the terminal actions (Save configuration, Install,
    Abort) to remain reachable below the category list, so that I can finish.
16. As an operator, I want every field that exists today to still be reachable at
    its new home, so that the re-cut loses no capability.
17. As an operator driving a headless `--guided` replay, I want the same fields
    reachable by the same paths, so that saved answer files keep working.
18. As a maintainer, I want the taxonomy defined as data in one table, so that
    adding or moving a field is a one-line edit.
19. As a maintainer, I want the detail-pane render to be a pure function I can
    test headlessly, so that the look is regression-covered without a tty.
20. As a maintainer, I want reflector, the resolvers, and every field path to be
    provably unchanged, so that the redesign is a pure presentation pass.

## Implementation Decisions

- **Two modules change; the back-end does not.** All edits land in the Guided
  Installer's **Menu model** and **fzf controller**. The emitter, Layer Resolver,
  Package Resolver, `reflector_country_args` / `install_base`, and every
  `options.*` / `system.*` field path are untouched.

- **Taxonomy is a data edit in the Menu model.** The 8→12 re-cut is expressed by
  changing per-field `section` labels and the category table — no control-flow
  change. Final categories, in archinstall reading order, with every current
  field's new home:

  | # | Category | Fields | Moved from |
  |---|----------|--------|------------|
  | 1 | Locales | locale, keymap | Host |
  | 2 | Mirrors & Repositories | mirror countries, multilib | Options |
  | 3 | Disks | filesystem, encryption, impermanence, esp size, swap, pools | — |
  | 4 | Bootloader | bootloader | Options |
  | 5 | Kernels | kernel | Options |
  | 6 | System | hostname, timezone | Host |
  | 7 | Users | primary user, extra accounts | — |
  | 8 | Environment | desktop, display manager, gpu | — |
  | 9 | Packages | repo, aur, derived, system programs, extra | — |
  | 10 | Security | firewall, antivirus, rootkit, apparmor, sysctl | Options (sysctl) |
  | 11 | Backup | snapshots, borg | — |
  | 12 | Advanced | ssh, age key url | Options |

  The `menu_categories` / `menu_rows` JSON contract is preserved: a category still
  aggregates its rows by matching `section`, and its `●` is still the fold of its
  fields' override flags. Category-level summaries update to the new groupings.

- **The detail pane becomes always-on via a new pure render function** in the
  controller (confirmed seam), returning the preview body for the current nav
  location + state: the **parent column** (each sibling listed, greyed, the
  current item marked) followed by the **live detail** of the highlighted item.
  It dispatches by level — category → `key: value` summary with `●` dots; leaf →
  current value + `menu_enum_options` for that field (or short help for free-text);
  and reuses the existing **Disks** layout-graph builder and **Users** account
  panel rather than new renders. `guided_ctl_preview` calls it on **every**
  screen; the previous per-screen preview gate (which showed a pane only on the
  Disk-layout screen) is retired so the pane is populated everywhere and the fzf
  preview window is shown at a fixed width at all depths.

- **Navigation is unchanged drill-down.** Enter drills, Esc returns; the list
  border keeps the breadcrumb. The archinstall "persistent left column" is
  realised by the parent-column render inside the preview pane, **not** by a
  second live cursor — a true two-live-column Miller was rejected in ADR 0071
  because it is not expressible in one fzf and would discard the `--guided` replay
  and the guided bats suite.

- **Reflector detail note.** The Mirrors & Repositories detail pane states that the
  selected countries feed `reflector --country <list> --latest 10 --sort rate`.
  This is a display string only; no reflector behaviour or field path changes.

- **Look pinned by prototype (Variant A + C's persistent column).** Clean
  archinstall chrome (title bar, category list, detail pane), no heavy
  card/footer chrome, `●` override marks preserved. See the prototype file for the
  concrete layout the render targets.

## Testing Decisions

- **Test external behaviour, not internals.** A good test asserts *what the
  operator sees or what the config becomes* — the category set and order, that a
  moved field surfaces under its new section, that a category's `●` folds its
  fields, that the detail-pane string for a given (state, location) contains the
  expected values / options / parent-column markers — never how the render string
  is assembled.

- **Seam 1 — Menu model** (`menu_categories`, `menu_rows`, `menu_enum_options`,
  `menu_render_value`): extend the existing `guided-menu.bats` and `menu-enum.bats`
  to assert the twelve categories in archinstall order, each field's new `section`,
  that no field path changed, and that every category's override fold still holds.
  Prior art: those two suites already assert the eight-category set and per-field
  rows — update their expectations.

- **Seam 2 — Detail-pane render** (the new pure controller function): a headless
  bats suite driving the function with a seeded state + a synthetic nav location,
  asserting the returned body contains the parent-column entries (with the current
  item marked), the `key: value` detail for a category, the current value + options
  for a leaf, the reflector note under Mirrors & Repositories, and the reused Disks
  pool tree / Users account table at those leaves. Prior art: the existing
  `_ctl_layout_graph` and `_ctl_breadcrumb` tests call controller functions
  directly with no tty — mirror that style.

- **Replay parity.** A `--guided` replay test asserts that answer files written
  against the old section names still resolve every field (paths unchanged), so the
  re-cut is behaviour-preserving for headless installs.

- **No VM tier needed.** Both seams are pure and headless; this is a presentation
  change with no install-flow effect, so it does not extend the Combination Matrix
  or need a `vm.sh --testing` cell.

## Out of Scope

Parity-gap features (each its own future spec, with real back-end work):

- Network configuration category (NetworkManager / iwd / manual).
- Applications rows: bluetooth, audio backend choice, power management, fonts.
- Bootloader extras: plymouth, unified kernel images, and the efistub / limine /
  refind bootloaders.
- Locales extras: encoding and console font rows.
- Mirrors extras: custom mirror servers, testing repos (multilib-testing,
  core-testing, extra-testing), and reflector knobs (`--latest` / `--sort` /
  protocol) as fields.
- System extras: automatic time sync (NTP) toggle.
- Pacman color toggle.
- A live package-search UI for Additional packages.
- archinstall's "Profile" archetypes (desktop / minimal / server / xorg) —
  deliberately not adopted; the name collides with our Host Profile.

Also out of scope: any change to the install back-end, the emitter, the resolvers,
reflector behaviour, disk binding, or the terminal actions.

## Further Notes

- ADR 0071 holds the decision and the full prototype verdict (why Variant A + C's
  persistent column won, why true Miller and a bespoke TUI were rejected).
- CONTEXT.md's **Guided Installer** glossary entry still names "eight top-level
  Configuration Categories"; update it to the twelve **when this lands**, so the
  glossary tracks the built model rather than a plan.
- The prototype (`prototype.html`) is throwaway; capture it on a throwaway branch
  and drop it from main once the look is folded into the real render.
