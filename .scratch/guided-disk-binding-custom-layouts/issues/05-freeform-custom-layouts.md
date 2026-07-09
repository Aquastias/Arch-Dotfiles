# 05 — Freeform custom layouts

Status: done
Type: AFK

## Parent

`.scratch/guided-disk-binding-custom-layouts/PRD.md`

## What to build

Let an operator build a custom layout instead of only picking one of the four
presets: a unified editor over the OS pool + any number of standalone data
pools, plus a blank `Custom…` starting point.

- **Unified editor** — lists the OS pool + storage groups + standalone data pools
  together, each opening with its per-kind editable rows:
  - OS pool: topology, disks.
  - Storage group: disks only (rest display-only).
  - Data pool: filesystem, topology, disks, encryption, **mount** (editable text
    row, default `/<name>`, blank = default), remove.
- **Add/remove** — add and remove standalone data pools freely.
- **`Custom…` seed** — a new entry in the preset picker seeds `{mode:"multi",
  os_pool:{pool_name:"rpool", topology:"none", disk_count:1}}` and opens the
  editor.
- **Entry flow** — `layout:` opens the preset picker (now including `Custom…`);
  `single` applies and backs out; every multi preset, `data-pools`, and `Custom…`
  applies its skeleton and opens the editor (extending today's data-pools-only
  door to all multi presets), so there is no re-entry dead end.

Chrome polish (footer/breadcrumb/keys) is slice 06; this slice uses whatever
list/action affordances exist.

## Acceptance criteria

- [ ] The editor lists OS pool + storage groups + data pools; each opens with the
      per-kind row set above (fzf-entry + nav seams).
- [ ] A data pool exposes an editable `mount` row defaulting to `/<name>`; blank
      input keeps the default (pure seam).
- [ ] `Custom…` appears in the preset picker, seeds the single-disk OS skeleton,
      and lands the operator in the editor.
- [ ] Picking any multi preset (e.g. `os-mirror-raidz1`) opens the editor rather
      than backing out; `single` still backs out.
- [ ] Adding/removing a standalone data pool updates the layout and the editor
      list (pure + fzf-entry seams).
- [ ] Full existing bats suite stays green.

## Blocked by

- 03 — Bind-all: OS pool, storage groups, single-disk root.
