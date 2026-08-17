# Bucket headers on the top screen + glossary catch-up

Status: done
Type: AFK

## Parent

.scratch/menu-reorg/PRD.md
ADR: docs/adr/0081-guided-install-flow-buckets-and-services-merge.md

## What to build

Group the fourteen Configuration Categories under six non-selectable **bucket
headers** on the Guided Installer top screen, reaching the final prototype-V3
look. Each category is tagged with a bucket; a `── BUCKET ──` header line is
emitted once, when the bucket changes while walking the categories in order.

Buckets:

| Bucket | Categories |
|--------|------------|
| `── SYSTEM ──` | System, Locales, Users |
| `── STORAGE & BOOT ──` | Disks, Bootloader, Kernels |
| `── SOFTWARE ──` | Environment, Mirrors & Repositories, Pacman, Packages |
| `── SERVICES ──` | Services |
| `── SECURITY & DATA ──` | Security, Backup |
| `── ADVANCED ──` | Advanced |

Add a `bucket` column to the category table and emit it from `menu_categories`.
Put the header-interleaving behind a **pure, unit-tested helper**
`menu_top_lines <override> [baseline]` in the menu model (not inline jq in the
controller), returning the ordered top-screen block: header lines plus each
category as `"<name> — <summary>"` (+ `"  ●"` when overridden). The controller's
top-screen render prints this block between the `Profiles ▸` divider and the
terminal-row divider. Reduce shape (from the prototype):

```
reduce categories as $c ({prev:null, out:[]};
  out += (["── \($c.bucket) ──"] when $c.bucket != prev)
       + ["\($c.name) — \($c.summary)" + ("  ●" when overridden)]
  ; prev = $c.bucket)
| out[]
```

Headers are cursor-landable but inert (fzf has no skip), consistent with the
existing `_CTL_DIVIDER`: Enter on a `── BUCKET ──` line returns `noop` (it has
no ` — ` separator and matches no category name), and the detail pane renders
the category column with no field detail. Verify these degrade correctly; add an
explicit header branch only if it reads more clearly.

Finally, update **CONTEXT.md** to the built model: fourteen categories, six
buckets, the System rename, and the Services merge (the glossary tracks the
built model — this lands now that the code does).

## Acceptance criteria

- [ ] `menu_categories` rows each carry a `bucket`; the six buckets tag the
      categories exactly as tabled above.
- [ ] `menu_top_lines` emits each bucket header once, in order, immediately
      before that bucket's first category; a category line carries `  ●` iff its
      category is overridden. Covered by a direct bats unit test.
- [ ] The top screen shows the six `── … ──` headers interleaved with the
      categories, still bracketed by the Profiles and terminal-row dividers.
- [ ] Enter on a `── BUCKET ──` line returns `noop`; the detail pane does not
      error on a header line.
- [ ] Existing top-screen assertions (Proceed / Save / Export / Abort, a
      `System — ` line) still pass; `guided-menu.bats` +
      `guided-controller.bats` updated and green.
- [ ] CONTEXT.md's Guided Installer entry reflects the fourteen categories, six
      buckets, System rename, and Services merge.

## Blocked by

- .scratch/menu-reorg/issues/02-services-merge.md
