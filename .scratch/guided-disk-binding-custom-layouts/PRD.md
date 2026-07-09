# Guided In-Menu Disk Binding + Freeform Custom Layouts

Status: ready-for-agent

Decision of record: **ADR 0047** (guided in-menu disk binding + freeform custom
layouts), building on ADR 0036 (device-less Host Profile / Effective Config),
0037 (Pre-Install Picker per-group assignment), 0039 (Guided Installer + deferred
Advanced authoring), 0042 (persistent-fzf controller), 0043 (per-group
filesystem), 0023 (archzfs-compatible ISO lags latest).

Glossary touched (`CONTEXT.md`, already updated): **In-Menu Disk Binding** (new),
**Free Set** (new); references Guided Installer, Pre-Install Picker, Host
Profile, Effective Config, Standalone Data Pool, Storage Group, Combined Data
Pool, Filesystem Adapter.

## Problem Statement

When I build a multi-disk layout in the Guided Installer, the pool editor lets me
cycle each pool's disk count from 1 to 8 with no relation to the machine I'm on —
so I can declare more disks than I physically own, and only find out post-menu
when the flat disk pick fails and forces a redo. I also can't say *which*
physical disk goes into *which* pool — the post-menu pick just slices disks in
pick-order. Separately, the menu chrome mixes actions (`← Back`, `＋ Add`, `✗
remove`) into the same list as real data, and there's no persistent status line —
only a top toolbar. And I'm boxed into four predefined layout presets: I can't
freely author a custom OS pool + arbitrary standalone data pools from scratch.

## Solution

Three coordinated changes to the Guided Installer, all behind ADR 0047.

**In-Menu Disk Binding.** On a machine with real disks, the pool editor binds
actual `/dev/disk/by-id/*` devices per pool (device-mode); off-target it keeps
today's abstract `disk_count` cycle (count-mode). The mode is chosen
automatically by hardware presence at launch — never a manual switch. Binding is
*bind-all*: OS pool, preset storage groups, standalone data pools, and the
single-disk root all bind in the menu, drawing from one global **Free Set** (all
candidates minus the live medium minus every already-bound disk). A pool's
add-disk affordance disappears when the Free Set is empty — the "noop when
exhausted" rule. A bound pool's `disk_count` is *derived* from the disks bound,
so over-declaring is impossible.

**Freeform custom layouts.** A unified editor authors the OS pool + any number of
standalone data pools (name/filesystem/topology/disks/encryption/mount), with a
`Custom…` blank-canvas seed alongside the presets. Presets become seeds that drop
you into the editor. Storage-groups-in-rpool stay preset-sourced (retunable, not
hand-authored).

**Cleaner chrome.** List-embedded actions move onto keybindings so lists hold
only data; navigation lives in the header, per-screen context actions + a live
summary in a persistent fzf footer, and a breadcrumb on the list border. This
rich chrome needs fzf ≥ 0.62; on the older fzf the lagging ISO may ship, the
chrome degrades gracefully to today's action-rows layout — the *features* work
identically either way.

## User Stories

1. As an operator on my real machine, I want to pick each pool's disks by their
   stable by-id path, so that I control which physical disk lands in which pool.
2. As an operator, I want the add-disk action to stop offering disks once none
   are free, so that I can never declare a layout my hardware can't satisfy.
3. As an operator, I want a disk I assign to one pool to vanish from every other
   pool's choices, so that no disk is double-claimed.
4. As an operator, I want the live install medium excluded from the disk
   choices, so that I never accidentally target the USB I booted from.
5. As an operator authoring a profile on a machine that is *not* the install
   target, I want the editor to fall back to abstract disk counts, so that I can
   still Save or Export a device-less profile with no disks attached.
6. As an operator, I want the mode (device vs count) chosen automatically from
   whether disks are present, so that I never have to flip a switch or think
   about it.
7. As an operator, I want my OS pool's disks bound in the menu just like data
   pools, so that the OS root competes for the same physical disks and can't
   double-claim one a data pool took.
8. As an operator, I want a single-disk install to pick its root disk in the menu
   too, so that on-target disk selection is one consistent rule everywhere.
9. As an operator, I want storage groups from a preset to have their disks bound
   in the menu, so that a fully specified layout needs no post-menu disk pick.
10. As an operator, I want a bound pool's disk count to reflect exactly the disks
    I chose, so that the count and the reality can never disagree.
11. As an operator, I want to bind and unbind a disk with a single Enter toggle
    on a list of available + bound disks, so that assignment feels like the
    multi-select screens I already use.
12. As an operator, I want each disk shown with its size and model, so that I can
    tell my disks apart without memorising by-id strings.
13. As an operator, I want to build a custom layout from a blank canvas, so that
    I'm not limited to the four predefined presets.
14. As an operator, I want to add and remove standalone data pools freely, so
    that I can shape storage to my machine.
15. As an operator, I want to edit each data pool's filesystem, topology,
    encryption, and mount point, so that my custom pools land exactly where and
    how I want them.
16. As an operator, I want to edit the OS pool's topology and disks directly, so
    that I'm not locked to a preset's OS shape.
17. As an operator, I want to pick a preset and immediately land in the editor,
    so that I can bind disks and tweak it without hunting for a way back in.
18. As an operator, I want root filesystem and root encryption to stay in their
    existing top-level settings, so that there's exactly one place to change each.
19. As an operator, I want the menu lists to contain only real data, so that
    Back/Add/Remove aren't cluttering the choices I'm scanning.
20. As an operator, I want a persistent footer showing this screen's actions and
    a live summary, so that I always know what I can do and what I've built.
21. As an operator, I want a breadcrumb showing where I am, so that deep in the
    editor I never lose my place.
22. As an operator on an older install ISO, I want the menu to still work with
    its action rows if my fzf is too old for the new chrome, so that a lagging
    ISO never bricks the installer.
23. As an operator, I want Save Profile to record only disk counts, so that the
    committed profile stays device-less and portable to another machine.
24. As an operator, I want Proceed and Export to carry the exact disks I bound,
    so that the install targets precisely what I chose.
25. As an operator running an unattended/headless install, I want to script the
    per-pool disks in an answers file, so that a VM or automated run installs a
    bound layout without interaction.
26. As an installer author, I want the same install to result whether disks were
    bound in-menu or resolved by the post-menu picker, so that both paths produce
    an identical Effective Config.
27. As an operator, I want cycling a pool to ext4/xfs to keep my first bound disk
    and free the rest, so that the single-disk pin never silently loses my whole
    selection.
28. As an operator, I want an under-populated pool (e.g. a mirror with one disk)
    to be caught with a clear message before install, so that I fix it rather
    than boot into a broken pool.

## Implementation Decisions

- **Pool data model.** A pool object gains an additive optional `devices[]` list
  of full `/dev/disk/by-id/*` paths. When present, `disk_count` is *derived* as
  its length; when absent, `disk_count` is the abstract cycle as today. No
  `bind_mode` flag — presence of `devices[]` encodes the mode. The closed Host
  Profile schema does **not** gain a `devices` key (see lifecycle below).
- **`devices[]` lifecycle (transient).** It lives only in the in-session Config
  State. Every terminal action flattens it: **Save** derives `disk_count` and
  drops `devices` (device-less profile, ADR 0036); **Proceed/Export** lift
  `devices` *out* of the skeleton into the per-group **assignment JSON** (the
  shape `picker_assign_disks` already consumes: `{os_pool:[…],
  storage_groups:[[…]], data_pools:[[…]]}`) and hand a device-less skeleton to
  the Effective Config emitter. The bound on-target path therefore *replaces* the
  post-menu flat-slice + ACCEPT prompt with a direct assignment build; a
  partially-counted layout (off-target groups) still runs the flat pick for the
  counted remainder.
- **On-target detection.** device-mode iff the disk enumerator returns ≥1
  candidate (live medium excluded), evaluated **once at guided launch** and
  cached for the session; hotplug mid-session does not flip modes.
- **Free Set.** One global set shared across OS pool + storage groups + data
  pools: enumerated candidates minus the live medium minus every device already
  bound to any group. A pool's add affordance is offered only from this set and
  disappears when empty. Exhaustion can leave a pool below its topology minimum;
  that is **not** prevented at selection time but caught by the existing skeleton
  validation, which names the under-populated group.
- **Filesystem-pin interaction.** Cycling a bound pool's filesystem to ext4/xfs
  (single-disk pin, ADR 0043) trims `devices[]` to the first entry, returning the
  rest to the Free Set. Topology changes never auto-trim or auto-grow.
- **Bind-all scope.** OS pool, preset storage groups (disks bindable;
  topology/existence stay preset-fixed), data pools, and the single-disk root
  (via a `root disk:` row on the Disks screen, single-select) all bind in-menu on
  target. `mode:single` off-target/replay keeps the post-menu single-disk path.
- **Unified layout editor.** Lists OS pool + storage groups + standalone data
  pools. Per-kind editable rows:
  - OS pool — topology, disks. (Root filesystem/encryption stay at their existing
    top-level rows, not duplicated here.)
  - Storage group — disks only; topology/mount/name/existence display-only.
  - Data pool — filesystem, topology, disks, encryption, **mount** (editable,
    default `/<name>`, blank = default), remove.
- **Entry flow.** `layout:` opens the preset picker, now including `Custom…`.
  `single` applies and backs out (bind via the `root disk:` row). Every multi
  preset, `data-pools`, and `Custom…` applies the skeleton **and opens the
  unified editor** (extending today's data-pools door to all multi presets).
  `Custom…` seeds `{mode:"multi", os_pool:{pool_name:"rpool", topology:"none",
  disk_count:1}}`.
- **Disk display.** Store the full by-id path; render `<size>  <model>  ·
  <by-id-tail>` (via the existing lsblk preview data) in the disk sub-screen and
  Free-Set rows; render only the count (`N bound`) in pool summary lines.
- **Chrome (version-gated, features version-independent).** Disk sub-screen = an
  Enter-toggle multi-select over `bound ∪ free` disks (bound = marked). Actions
  `^A` (add/new/create) and `^X` (remove/delete) become keybindings; Back = Esc;
  Undo/Redo/Reset stay `^Z`/`^Y`/`^R`. **Rich chrome iff fzf ≥ 0.62**: header =
  global nav keys, footer (`change-footer`) = per-screen context actions + live
  summary, breadcrumb on `--list-label` (static ` Guided Installer ` stays on the
  outer border-label), rounded list/footer borders. **Legacy (0.36–0.61)**:
  today's action-rows-in-list + header/border, no footer/breadcrumb. Version
  detected once at launch into a cached boolean. No hard-floor bump and no
  `pacman -Sy fzf` at menu start (would break offline Save/Export authoring).
- **Modules touched.** `lib/guided-controller.sh` (pool model, editor nav/rows,
  Free Set, fs-pin trim, chrome-action emission, version gate),
  `lib/guided-fzf-entry.sh` (dispatch for the new screens/keys), `lib/guided.sh`
  (bind-all resolution, flatten-on-save, replay `devices[]` injection),
  `lib/config/skeleton.sh` (devices↔count flatten, Custom seed builder),
  `lib/picker.sh` (Free-Set computation over enumerated candidates;
  assignment-from-`devices[]` build), `CONTEXT.md` (done). No back-end change —
  the Effective Config shape is unchanged.
- **Headless replay.** In-Menu Disk Binding is interactive-only. `--guided`
  replay gains a per-pool `devices[]` answer form that injects bound disks into
  the Config State so the bound assignment path is scriptable; the summed
  post-menu pick stays the count-mode/replay fallback.

## Testing Decisions

Good tests here assert **external behavior at a seam** — JSON-in/JSON-out for
logic, emitted fzf action strings for chrome — never internal helper calls. Three
seams, all already established, plus one small new replay hook:

- **Pure logic seam (bats over `guided-controller.sh` / `skeleton.sh` /
  `picker.sh`).** Covers the pool data model (`devices[]` add/remove, derived
  `disk_count`), the fs-pin trim-to-first, the Free-Set computation (using the
  existing **`PICKER_BY_ID_DIR`** override to fake `/dev/disk/by-id`, exactly as
  `picker.bats` does), the flatten-on-save, and the assignment build from
  `devices[]`. Prior art: `guided-controller.bats`, `guided-per-group-fs.bats`,
  `skeleton.bats`, `picker.bats`.
- **fzf-entry seam (bats over `guided-fzf-entry.sh dispatch`).** Automates the
  chrome without a tty: assert the rendered list contains only data (no action
  rows in rich mode), the emitted action string carries the right
  `change-footer` / `change-list-label` / `change-header` content and the
  `^A`/`^X` binds, the Enter-toggle reload-sync on the disk sub-screen, the
  rich-vs-legacy branch off a stubbed fzf version, and the nav-file mutation for
  each new screen. Prior art: `guided-fzf-entry.bats` (already asserts action
  strings + nav mutations).
- **VM seam (`vm.sh --testing --verify-boot` via the config seam).** One bound
  cell — per-pool `devices[]` injected through the new `--guided` replay form —
  installs and boots, asserting `INSTALLER-EXIT-0` + first-boot sentinel, proving
  the on-target bound path produces a bootable system. Prior art: the
  combination-matrix Tier-2 VM cells and `seed-generator-guided.bats`.

The full existing bats suite must stay green on every slice.

## Out of Scope

- Hand-authoring storage-groups-in-rpool (role selection: in-rpool vs standalone)
  — deferred; storage groups stay preset-sourced and retunable. A later increment
  if hand-authoring proves needed.
- Any change to the back-end / Effective Config shape or the install flow.
- Auto-fill / auto-assignment of disks to a pool from the Free Set — binding is
  always one disk at a time, operator-driven.
- Raising the minimum fzf version or upgrading fzf at menu start.
- Live pixel-level fzf render verification (fzf's own job; the entry seam covers
  our emission).
- Fixing the stale `CONTEXT.md` note that says Standalone Data Pool encryption
  "inherits the global `options.encryption`" (code gives a per-pool toggle) — a
  one-line doc sync tracked separately.

## Further Notes

- The lagging archzfs-compatible ISO (ADR 0023) means the legacy-chrome path is
  not hypothetical — an older ISO may genuinely ship fzf < 0.62, so the graceful
  fallback must be real and tested, not aspirational.
- Off-target authoring (Save/Export with no disks) is a first-class path the
  design must never break; it is why detection is hardware-presence based and why
  no network/pacman step gates the menu.
- The bound path and the post-menu picker must converge on an identical
  assignment JSON for the same disks — a pure-seam test pins this equivalence so
  the VM seam stays a thin belt-and-suspenders check rather than the primary
  guarantee.
