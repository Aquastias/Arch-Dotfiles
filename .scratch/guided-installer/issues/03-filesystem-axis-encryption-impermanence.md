# Filesystem axis + Disks-owned encryption & impermanence

Status: done

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

Realize the **Filesystem Adapter** axis (ADR 0040) end-to-end, ZFS-only.
Add the top-level `filesystem` discriminator (default `zfs`; existing ZFS
layout fields stay flat at root). Add the additive
`options.encryption_method` (`native` | `luks`, default derived from
`filesystem`); the existing `options.encryption` bool still toggles
enablement. Generalize the layout dispatch to a **filesystem-keyed** seam
with ZFS as the only adapter (no behavioural change to the ZFS path). Add
`lib/config/validation.sh` contract checks: fields-set must match
`filesystem`; encryption method must match filesystem; Impermanence only
on ZFS/btrfs.

In the Guided Installer, the Disks section becomes **filesystem-first**
(btrfs/ext4/xfs shown as disabled/reserved entries). **Encryption** and
**Impermanence** move under Disks because the filesystem governs them.
Impermanence is offered only for ZFS/btrfs (hidden for ext4/xfs); when
enabled it applies the Curated Persist Defaults automatically and lets
the operator add Persist Extensions.

## Acceptance criteria

- [x] Config carries `filesystem` (default `zfs`); existing ZFS profiles
      and VM seeds validate and install unchanged. (bats-green; not yet
      VM-smoke-verified.)
- [x] `options.encryption_method` present (`native` | `luks`), default
      derived from `filesystem`; enablement still via the bool.
- [x] Layout dispatch is filesystem-keyed; the ZFS path is unchanged in
      behaviour.
- [x] Contract checks accept valid combinations and reject invalid ones
      (fields↔filesystem, method↔filesystem, impermanence↔filesystem)
      with the offending path.
- [x] Disks menu is filesystem-first with btrfs/ext4/xfs disabled;
      Encryption + Impermanence sit under Disks; Impermanence hidden for
      ext4/xfs.
- [x] Enabling Impermanence applies Curated Persist Defaults (back-end,
      keyed on enablement) and supports adding Persist Extensions
      (operator-typed persist.directories).
- [x] bats: contract checks + emit.

## Blocked by

- `01-guided-install-tracer-bullet`

## Comments

**L1–L3 done via /tdd (2026-06-16); L4 (guided menu) deferred to a
follow-up — user-approved scope split.**

L1 schema+accessors: `install_config_filesystem` (default `zfs`, schema
row) + `install_config_encryption_method` (derived special: zfs→native,
else→luks; explicit wins). Closed schema (`profile.sh`) gains `filesystem`
+ `options.encryption_method`; the `_INSTALL_CONFIG_SCHEMA`↔closed-schema
drift guard forced the lockstep.

L2 contracts (`validation.sh:_validation_filesystem`, wired into
`validate_install_context` before disk work): known-filesystem,
method↔filesystem (zfs+luks / non-zfs+native rejected, names the path),
impermanence↔filesystem (ext4/xfs rejected). Whether a *known* filesystem
is actually built is L3's job, so the contracts stay correct as adapters
land. New `tests/config/validation-filesystem.bats` (10).

L3 dispatch: `lib/layout/dispatch.sh:layout_adapter_source <dir> <fs>
<mode>` — zfs→flat `lib/layout/<mode>.sh` (zfs/ relocation deferred to
filesystem #2 per ADR 0040), non-zfs errors. Wired at `03-install.sh`
`main()` (was the mode-keyed source line). ZFS behaviour unchanged.

Tests: install-config(+5), profile-loader(+1), validation-filesystem(10),
layout/dispatch(3). Full suite **1111 bats**, shellcheck clean.

**L4 done via /tdd (2026-06-17) — issue CLOSED.** Guided menu now
filesystem-first. menu.sh: new **Disks** section — `filesystem` moved
Host→Disks, `options.encryption` + `options.impermanence.enabled` bool rows
added; the impermanence row is hidden when filesystem is ext4/xfs (menu_rows
reads the effective filesystem). guided.sh: `_guided_filesystem_options`
(zfs active, btrfs/ext4/xfs "(reserved)") + `_guided_edit_filesystem`
(commits only an active fs; reserved picks refused); `_guided_edit_bool`
→ encryption/impermanence toggles through the seam; `_guided_add_persist`
(operator-typed dir → persist.directories) surfaced by `_guided_persist_lines`
only when impermanence is on. Loop dispatch re-keyed on the row **label**
(`*"filesystem:"*` / `*"encryption:"*` / `*"impermanence:"*` /
`*"install disk:"*`) so each Disks row routes to its own edit. guided_build's
replay branch drives the new edits (no-op when the answer key is absent), so a
`--guided` answers file emits filesystem/encryption/impermanence/persist into
the Effective Config. Two issue-02 section-reset tests updated for the
filesystem Host→Disks move. Tests: guided-menu(+5), guided-shell(+11). Full
suite **1127 bats**, shellcheck clean. **Not yet VM-smoke-verified** (needs a
push first — guest clones the public remote).
