# Unified swap control + zswap (default on)

Status: ready-for-agent

Builds on **ADR 0039** (Guided Installer), **ADR 0042** (persistent single-fzf
controller), **ADR 0040** (Filesystem Adapter axis). Touches the Bootloader
Adapters (systemd-boot + GRUB) and the Config State / menu model.

Glossary: Guided Installer, Configuration Categories, Config State, Effective
Config, Filesystem Adapter, Bootloader Adapter, Host Profile, Single Entry Point.

## Problem Statement

In the Guided Installer's **Disks** category the operator sees two separate rows
for one concept — `swap` (a true/false toggle) and `swap size` (auto / a size).
They read as unrelated settings when they describe a single decision, and there
is no way to enable compressed swap caching. The operator wants one swap control,
and wants modern compressed swap (zswap) on by default.

Separately, the existing `swap size` default of RAM×2 was justified "for
hibernation," but hibernation is not actually wired (no `resume=` kernel
parameter or resume hook exists), so the oversized swap buys nothing today.

## Solution

Collapse the two Disks rows into a single **swap** row that opens a small
sub-editor (the same drill-in pattern as the data-pools editor). Inside, the
operator toggles swap on/off, sets its size, and configures **zswap** — a
compressed RAM cache that sits in front of the real (disk-backed) swap device.

zswap is **on by default** (zstd compressor, 20% max pool). It needs no extra
package — it is a kernel feature enabled purely through kernel command-line
parameters, appended by both Bootloader Adapters. Disk-backed swap creation
(ZFS swap zvol, or swap partition on single/ext4/xfs) is unchanged; zswap layers
on top of whatever swap device already gets created.

The single swap row's value summarizes the whole decision at a glance:
`off` / `auto · zswap zstd` / `8G · no zswap`.

## User Stories

1. As an operator, I want a single **swap** row in the Disks category, so that I
   read one control instead of two unrelated-looking rows.
2. As an operator, I want the swap row to open a sub-editor, so that all swap
   settings live in one focused screen.
3. As an operator, I want to toggle swap on/off in the sub-editor, so that I can
   disable swap entirely.
4. As an operator, I want to set the swap size as free text (`auto` or e.g.
   `8G`), so that I keep the flexibility the old `swap size` field gave me.
5. As an operator, I want `auto` to keep meaning the existing sized default, so
   that nothing about disk-swap sizing changes.
6. As an operator, I want zswap enabled by default, so that I get compressed swap
   caching without having to know it exists.
7. As an operator, I want to toggle zswap on/off, so that I can fall back to plain
   ("normal") swap when I prefer it.
8. As an operator, I want to choose the zswap compressor by cycling
   `zstd → lz4 → lzo`, so that I can trade compression ratio against speed.
9. As an operator, I want to set the zswap max pool percent by cycling
   `5 / 10 / 20 / 40 / 60`, so that I bound how much RAM zswap may use without
   typing an invalid number.
10. As an operator, I want zswap rows (compressor, max pool %) to appear only when
    zswap is on, so that the screen never shows settings that do nothing.
11. As an operator, I want the size and zswap rows to appear only when swap is on,
    so that an off-swap screen is not cluttered with moot settings.
12. As an operator, I want the swap row's one-line value to show `off`, the size,
    and the zswap compressor, so that I see the whole swap decision at a glance.
13. As an operator, I want a disabled zswap to be flagged as `· no zswap` in the
    summary, so that I can tell I have stepped away from the default.
14. As an operator, I want the swap row to appear for every filesystem (ZFS,
    ext4, xfs) and for single-disk layouts, so that swap is configurable wherever
    a swap device is created.
15. As an operator, I want zswap to require no extra package, so that the install
    footprint does not grow.
16. As an operator booting via systemd-boot, I want the zswap parameters present
    on both the main and fallback boot entries, so that zswap is active on either.
17. As an operator booting via GRUB, I want the zswap parameters in the default
    kernel command line, so that zswap is active on normal boots.
18. As an operator, I want zswap parameters emitted only when both swap and zswap
    are enabled, so that I never get a zswap cmdline pointing at a non-existent
    swap device.
19. As an operator reviewing the pre-install summary, I want a swap line that
    reflects size and zswap state, so that I confirm my choice before install.
20. As an operator authoring a Host Profile, I want the new zswap keys to survive
    a Save / Export / load round-trip, so that my profile reproduces the same
    swap configuration.
21. As an operator with an existing profile using `options.swap` + `swap_size`, I
    want it to keep working unchanged, so that no migration is forced on me.
22. As an operator, I want undo/redo/reset to cover swap edits like every other
    Config State change, so that the sub-editor behaves like the rest of the menu.

## Implementation Decisions

### Schema (additive — no migration)

Existing keys keep their meaning and defaults:

- `options.swap` — bool, default `true`
- `options.swap_size` — string, default `"auto"` (RAM×2 sizing unchanged)

New keys under `options.zswap`:

- `options.zswap.enabled` — bool, default `true`
- `options.zswap.compressor` — string, default `"zstd"`
- `options.zswap.max_pool_percent` — int, default `20`

No `zswap.zpool` key. Modern kernels removed the `z3fold`/`zbud` allocators and
hardcoded `zsmalloc`; the running target has no `/sys/module/zswap/parameters/
zpool` at all. Emitting `zswap.zpool=` would be a no-op, so it is omitted from
both schema and cmdline.

### Control shape — two toggles, not a mode enum

Swap is modeled as two independent toggles (`options.swap`, `options.zswap.
enabled`), not a single `off/normal/zswap` enum. This mirrors the existing schema
(swap is already a bool, zswap is purely additive) and the row-per-setting pattern
of the data-pools editor, and avoids synthesizing a field that would need
translation on every read/write. The state `zswap on + swap off` is unreachable
because the zswap rows are hidden when swap is off.

### Guided Installer — one row → a `swapedit` sub-screen

- The **Disks** category shows a single `swap` row (for all filesystems and
  single-disk layouts); the separate `swap size` row is removed.
- Entering the swap row navigates to a new **swapedit** screen, following the
  data-pools editor drill-in convention (new navigation transition + a back
  transition returning to the Disks category).
- swapedit rows, with conditional visibility (hidden when moot, never shown
  disabled — consistent with how the impermanence row is hidden for ext4/xfs):
  - `enabled` — Enter toggles on/off.
  - `size` — free-text editor (reuses the existing text-screen plumbing); shown
    when swap is on.
  - `zswap` — Enter toggles on/off; shown when swap is on.
  - `compressor` — Enter cycles `zstd → lz4 → lzo → zstd`; shown when zswap is on.
  - `max pool %` — Enter cycles `5 → 10 → 20 → 40 → 60 → 5`; shown when zswap is
    on.
  - `← Back`.
- The four/five settings are seeded with their defaults so the screen opens
  populated.
- The swap row's one-line summary (a label helper in the controller, styled like
  the existing layout-label helper): `off` when swap off; otherwise `<size>`,
  with `· zswap <compressor>` appended when zswap is on, or `· no zswap` when
  zswap is off. Examples: `off`, `auto · zswap zstd`, `8G · no zswap`.
- Edits flow through the existing Config State write + autocommit path, so
  undo/redo/reset already cover them.

### zswap activation — kernel command line only (deep module)

A new **pure module `zswap_cmdline_params`** takes a Config State (or Effective
Config) JSON and returns the kernel cmdline fragment:

- When `options.zswap.enabled` is true **and** `options.swap` is true →
  `zswap.enabled=1 zswap.compressor=<compressor> zswap.max_pool_percent=<n>`
- Otherwise → empty string.

It is bootloader-agnostic and reads only the Config State, so it is unit-testable
without a chroot. The module is staged into the chroot lib directory alongside the
other staged libs the Bootloader Adapters source.

### Bootloader Adapters consume the fragment

- **systemd-boot adapter**: append the fragment to the `options …` line of both
  the main and fallback loader entries.
- **GRUB adapter / grub-common**: append the fragment to
  `GRUB_CMDLINE_LINUX_DEFAULT` (normal-boot entries).

Both adapters already read install-state via the accessor layer, so they obtain
zswap settings the same way.

### Accessors, summary, profile coverage

- Add accessors `zswap_enabled`, `zswap_compressor`, `zswap_max_pool_percent`
  to the install-config accessor table.
- The pre-install summary's swap line reflects size and zswap state (e.g.
  `Swap: 8G · zswap (zstd)`).
- The profile's covered-field list gains the three new `options.zswap.*` keys so
  Save/Export emit them.

### Disk swap is untouched

The ZFS swap zvol (and the single/ext4 swap partition) are created exactly as
today from `options.swap` + `options.swap_size`. zswap does not change device
creation; it only adds cmdline parameters that make the kernel cache swap pages
in compressed RAM ahead of that device.

## Testing Decisions

Good tests assert **external behavior through the public interface** — the
JSON-in/JSON-out (or string-out) contracts and the rendered menu/screen lines —
never private helpers or file internals. The persistent-fzf controller has no
TTY in tests, so behavior is asserted via the list/enter/back/preview surface,
exactly as the existing `tests/config/guided-controller.bats` does for the
data-pools editor.

Modules to test:

1. **`zswap_cmdline_params`** (the deep module). Cases: default (swap+zswap on)
   emits the full fragment with `zstd`/`20`; custom compressor and percent are
   reflected; zswap off → empty; swap off (zswap on) → empty; no `zswap.zpool`
   token ever appears. Prior art: pure JSON-contract bats like the layout/zfs
   helpers (`tests/zfs/*`, `tests/layout/*`) and the menu/skeleton tests.
2. **swapedit controller**. Cases: the single `swap` row exists and `swap size`
   does not; entering swap navigates to swapedit; `enabled` toggles; `zswap`
   toggles; compressor cycles `zstd→lz4→lzo`; max pool % cycles
   `5→10→20→40→60`; size opens the text screen and saves; rows are hidden when
   swap off / zswap off; the summary label renders `off` / `<size> · zswap
   <comp>` / `<size> · no zswap`; back returns to the Disks category. Prior art:
   the existing data-pools / pooledit blocks in `tests/config/
   guided-controller.bats`.
3. **menu + accessors**. The Disks category surfaces one swap row (no `swap
   size`); `zswap_*` accessors read the seeded/overridden values from install
   state. Prior art: `tests/config/install-config.bats`,
   `tests/config/menu`-style row assertions.
4. **profile round-trip**. The three `options.zswap.*` keys survive a
   Save/Export/load round-trip. Prior art: `tests/config/profile-loader.bats`,
   `tests/vm/profile.bats`.

## Out of Scope

- Hibernation / `resume=` wiring. The RAM×2 sizing rationale referenced it, but
  it is not implemented and this PRD does not add it.
- **zram** (a standalone compressed-RAM swap device). This PRD does zswap (a
  cache in front of disk swap), per the resolved design discussion.
- Exposing other zswap knobs (`accept_threshold_percent`, `shrinker_enabled`) or
  the removed `zpool` allocator.
- Cycling/preset swap sizes — size stays free-text.
- Changing disk-swap creation, sizing math, or the small-disk swap cap.

## Further Notes

- Delivery is two commits, back-to-back: **Slice A** merges the two rows into the
  swapedit sub-editor over the existing keys (UI refactor only, ships green), then
  **Slice B** adds zswap (schema, accessors, the `zswap_cmdline_params` module +
  chroot staging, both Bootloader Adapters, the zswap rows, summary suffix,
  lifecycle/profile, tests). The riskier cmdline/bootloader changes land isolated
  in B.
- The live fzf render and the on-target cmdline (`/proc/cmdline`,
  `/sys/module/zswap/parameters/enabled`) are TTY/VM-gated and not asserted by
  bats, matching the persistent-fzf controller's existing verification boundary.
- Commit messages follow the repo convention: conventional-commit prefix, single
  summarized line, capitalized after the `:`.
