# Install-flow reorder + General→System rename

Status: done
Type: AFK

## Parent

.scratch/menu-reorg/PRD.md
ADR: docs/adr/0081-guided-install-flow-buckets-and-services-merge.md

## What to build

Re-order the Guided Installer's top-level **Configuration Categories** from
archinstall reading order to **install-flow order**, and rename the `General`
category to **System** (the identity anchor holding hostname, timezone, fonts).
Fonts stay in System. This slice leaves all sixteen categories flat (no bucket
headers, no Services merge yet) — it only changes order and the one rename.

Target order after this slice (flat):

System, Locales, Users, Disks, Bootloader, Kernels, Environment,
Mirrors & Repositories, Pacman, Packages, Printing service, Bluetooth, Power,
Security, Backup, Advanced.

Touch the menu model only: the category table (order + the System row/summary)
and the `section` label on the hostname / timezone / fonts fields. No field
paths, defaults, shapes, emit, or resolver behaviour change.

## Acceptance criteria

- [ ] hostname, timezone, fonts rows report `section == "System"` (not
      "General").
- [ ] `menu_categories` returns the sixteen categories in the install-flow order
      above; `System` is first, `Advanced` last.
- [ ] The System category summary mentions fonts; `menu_category_rows System`
      returns the hostname/timezone/fonts rows.
- [ ] The top screen (`guided_ctl_list` at `top`) lists a `System — ` line, and
      drilling `System` opens its fields; no `General` string remains in the
      menu model or its tests.
- [ ] `guided-menu.bats` + `guided-controller.bats` updated (canonical-order
      test, section assertions, and the `General` nav fixtures repointed to
      `System`); the full guided bats suite passes.

## Blocked by

None - can start immediately.
