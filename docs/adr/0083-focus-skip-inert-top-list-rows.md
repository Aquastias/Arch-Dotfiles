# Cursor skips inert top-list rows via a focus bind

---
Status: accepted (builds on ADR 0081 bucket headers + ADR 0082 spacing)
---

The Guided Installer's top list renders decorative rows — the category/action
**divider**, the `── BUCKET ──` **headers** (ADR 0081), and the blank **spacer**
lines between buckets (ADR 0082). fzf has **no non-selectable item**, so the
cursor used to land on them (Enter was already a no-op). It now **auto-skips**
them: a `focus` bind hops the cursor to the next real row, so only Profiles, a
category, and the terminal actions are ever selected.

## How

One rule — `guided_row_inert` (`lib/guided-rows.sh`) — classifies a row as inert
when it is blank/whitespace-only or opens with a box-drawing dash (`─`, which
both the divider and the bucket headers do). It is pure and dependency-free so
the per-focus bind can source just it, not the whole controller.

fzf drives it with three binds (`lib/guided.sh`):

- `up` / `down` record the movement direction into a tmpfs file
  (`GUIDED_SKIP_FILE`) **before** moving;
- `focus` runs `guided-fzf-entry.sh skip {}` — on an inert row it echoes the
  recorded direction (fzf re-moves and focus fires again), on a selectable row
  it echoes nothing (the cursor settles).

Termination is guaranteed by the layout: every inert run is **flanked by
selectable rows**, and the first (`Profiles ▸`) and last (`Abort ▸`) rows are
selectable, so a same-direction skip always reaches a real row. Nav keys other
than the arrows inherit the last recorded direction — still correct, because the
flanking holds regardless of direction.

## Considered options

- **Leave rows inert-on-Enter only (pre-0083).** Rejected: the cursor stopping
  on a divider/header/blank reads as broken.
- **fzf `--gap`.** Rejected: it inserts a non-selectable gap between *every*
  item uniformly — it cannot express the selective per-bucket spacing, and does
  nothing for the header/divider rows.
- **A direction-less focus skip (always advance one way).** Rejected: it makes
  upward navigation impossible past a header. The recorded-direction file is the
  minimal fix.

## Consequences

- `guided_row_inert` is unit-tested (guided-controller bats); the fzf wiring
  (up/down/focus binds) is interactive glue, **unverified by bats** like the
  rest of `lib/guided.sh`, so the skip *feel* is a VM/HITL check.
- Two extra tmpfs writes + one `bash` fork per cursor move (the fork mirrors the
  preview, which already runs per focus) — negligible, but noted for slow ISOs.
- `GUIDED_SKIP_FILE` joins the tmpfs set reaped on RETURN.
