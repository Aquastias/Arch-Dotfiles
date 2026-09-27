# 03 — Guided Manual partitioning toggle + notice + locked fields (menu model)

**What to build:** The Disks-category surface for entering and leaving manual
mode. A **Manual partitioning** on/off toggle sets `disk_config.kind`. Turning it
on fires a one-time confirm notice that names the features being given up; while
manual is on, the pool-dependent Disks fields stay visible but locked so the
operator sees what auto mode would have offered. Turning it off restores those
fields and their stored values. No cfdisk or install yet — this is the menu
model only.

**Blocked by:** 01.

**Status:** done

- [x] A **Manual partitioning** toggle field on the Disks category sets
      `disk_config.kind` between `auto` and `manual`.
- [x] Turning it on fires a one-time confirm notice that explicitly enumerates
      the disabled features: ZFS/pool layouts, encryption, impermanence, data
      pools / storage groups, managed swap, ESP size.
- [x] While manual is on, those Disks fields render **shown-but-locked** —
      visible, dimmed, non-enterable (distinct from the hidden-for-ext4/xfs
      impermanence rule, ADR 0040).
- [x] Turning manual off restores the fields and their previously stored values;
      auto↔manual toggling loses neither side's Config State.
- [x] Headless/pure bats at the guided menu seam covers the toggle, the lock
      state, restore-on-off, and the one-time notice, modelled on
      `tests/config/guided-custom-layout.bats` / `guided-disk-bind.bats`.

## Comments

- 2026-09-27 audit: c16f2e8, 62b6315, c485ed0 (guided/manual-menu.bats).
