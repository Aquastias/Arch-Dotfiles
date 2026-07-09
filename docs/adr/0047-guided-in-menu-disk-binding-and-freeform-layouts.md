# Guided in-menu disk binding + freeform custom layouts

Give the Guided Installer's pool editor **In-Menu Disk Binding**: when real
hardware is enumerable it binds actual `/dev/disk/by-id/*` devices per pool
group (device-mode), and when authoring off-target it falls back to today's
abstract `disk_count` cycle (count-mode) — the mode is chosen automatically by
hardware presence, never a manual switch. A pool gains an additive `devices[]`
list whose length *derives* `disk_count`; disks come from one global **Free Set**
(all candidates minus the live medium minus every already-bound disk), and a
pool's `＋ add disk` disappears when the Free Set is empty ("noop when
exhausted"). Bound pools bypass the post-menu picker; Save Profile always
flattens back to device-less counts (ADR 0036 invariant), only Export carries
devices. In the same pass the menu also gains **freeform custom layouts** (the
composable `skeleton_*` builders wired to a unified editor for the OS pool +
standalone data pools, plus a blank `Custom…` seed) and a chrome split that
moves list-embedded actions (Back/Add/Remove) onto keybindings so the list holds
only data, with navigation in the header and per-screen context actions + a live
summary in the fzf footer.

Builds on ADR 0036 (device-less Host Profile / Effective Config), ADR 0037
(Pre-Install Picker per-group assignment), ADR 0039 (Guided Installer + deferred
"Advanced authoring"), ADR 0042 (persistent-fzf controller) and ADR 0043
(per-group filesystem). Extends CONTEXT.md with **In-Menu Disk Binding** and
**Free Set**.

## Considered Options

### Where device identity lives
- **(a)** Keep the menu fully device-less; only cap the `disk_count` cycle at the
  count of available disks. Prevents over-declaring but never lets the operator
  choose *which* physical disk goes in *which* pool. Rejected — misses the real
  capability the request was after.
- **(b)** Bind by-id devices in the menu unconditionally. Cleanest per-pool
  control, but breaks authoring a profile on a machine that is not the install
  target (no disks to enumerate). Rejected.
- **(c)** Hybrid — device-mode when hardware is present, count-mode when not,
  auto-selected. Chosen. Keeps device-less off-target authoring *and* gives
  per-pool by-id assignment on the real machine.

### Pool data model
- **Additive `devices[]`, derived `disk_count`** — chosen. `disk_count` stays the
  single "how many" source of truth (skeleton/validate/picker code unchanged for
  the counted path); flatten-on-save is one operation (`disk_count` = length,
  drop `devices`). A separate `bind_mode` flag or replacing `disk_count`
  outright were rejected as redundant / higher blast-radius.

### Under-min on exhaustion
- Selection-time prevention (topology options vanish as disks run out) was
  rejected as a confusing UI. Chosen: `＋ add disk` simply stops, and the
  existing `skeleton_validate` blocks Proceed naming the under-populated group.

### Chrome
- A purely decorative footer over today's action-rows was rejected. Chosen:
  actions become keybindings and the list holds only data, so the footer is a
  genuine persistent status/context zone. Requires fzf ≥ 0.62 (`--footer`); on
  older fzf the chrome **degrades gracefully** to the header + action-rows layout
  rather than aborting.

### Custom-layout scope
- Full role exposure (author storage-groups-in-rpool vs standalone pools by
  hand) was deferred — the role is meaningful only for ZFS and drags in a
  role×filesystem validation matrix. Chosen scope: freeform authoring of the OS
  pool + standalone data pools; storage-groups-in-rpool stay reachable via the
  `os-mirror-raidz1` preset (retunable), a later increment if hand-authoring
  proves needed.

## Consequences

- The post-menu `_guided_resolve_assignment` must consult per-pool `devices[]`
  and only run the flat picker for still-counted groups — bound and counted
  pools can coexist in one layout.
- Save Profile must strip `devices[]` deterministically; a round-tripped profile
  is always counts, re-bound on the next on-target run.
- Headless replay (`--guided`) is unchanged: In-Menu Disk Binding is
  interactive-only; scripted runs keep supplying devices via answer keys.

## Resolved implementation details (grilled)

**Binding scope.** *Bind-all in-menu on-target*: OS pool, preset storage groups
(binding-only — topology/existence stay preset-fixed), data pools, AND the
single-disk root (via a `root disk:` row on the Disks screen) all bind their
disks in the menu. When every group is bound, on-target resolution runs no flat
pick at all. `mode:single` off-target / replay keeps the post-menu `guided_pick_
disk` path.

**`devices[]` lifecycle.** Transient in `_GUIDED_STATE` only. Every exit
flattens it: **Save** derives `disk_count` + drops `devices`; **Proceed/Export**
lift `devices` into the per-group assignment JSON (the shape `picker_assign_
disks` consumes) and hand a device-less skeleton to `emit_effective` — replacing
`picker_build_assignment`'s flat-slice + `ACCEPT` re-prompt. The closed profile
schema never gains a `devices` key.

**On-target detection.** `picker_enum_disks(live)` non-empty, evaluated **once
at guided launch** and cached — no per-open re-eval (hotplug won't flip modes).

**Free-Set fs-pin interaction.** Cycling a bound pool's filesystem to ext4/xfs
(single-disk pin, ADR 0043) trims `devices[]` to the first, returning the rest
to the Free Set. Topology changes never auto-trim/grow; `skeleton_validate`
catches under-min.

**Editor per-kind field matrix.** OS pool = topology + disks only (root
filesystem/encryption stay at their top-level rows). Storage group = disks only.
Data pool = filesystem + topology + disks + encryption + **mount** (editable,
default `/<name>`) + remove.

**Entry flow.** `layout:` opens the preset picker (now incl. `Custom…`). Single
applies + backs out (bind via `root disk:` row). Every multi preset / `data-
pools` / `Custom…` applies the skeleton **and opens the unified editor** (no
re-entry dead end). `Custom…` seeds `{mode:multi, os_pool:{rpool, topology:
none, disk_count:1}}`.

**Device display.** Store full `/dev/disk/by-id/*`; render `<size> <model> ·
<by-id-tail>` in pickers, count only (`N bound`) in summaries.

**Chrome (version-gated, features version-independent).** Disk sub-screen =
Enter-toggle multi-select (`bound ∪ free`, marked = bound); no per-disk keys.
Actions `^A` add / `^X` remove (override fzf line-start, consistent with the
existing `^Z`/`^Y`/`^R` overrides). **Rich chrome iff `fzf ≥ 0.62`**: header =
global nav keys, footer (`change-footer`) = per-screen context actions + live
summary, breadcrumb on `--list-label` (static ` Guided Installer ` stays on the
outer border-label), rounded list/footer borders. **Legacy (`0.36–0.61`)**:
today's action-rows-in-list + header/border, no footer/breadcrumb. No hard-
require bump and no `pacman -Sy fzf` at menu start (would break offline
Save/Export authoring).
