# Terminal actions — Save profile + Export effective config

Status: done

## Parent

`.scratch/guided-installer/PRD.md`

## What to build

The two non-Proceed terminal actions.

**Save profile** writes `hosts/<name>/profile.jsonc` as a **device-less
delta over Host Core** — disks dropped, the mode/topology/`disk_count`
skeleton kept — and **refuses to overwrite** an existing `hosts/<name>/`
or `users/<name>/` profile, demanding a new name (no overwrite path).
Created ad-hoc users are written as their `users/<name>/profile.jsonc`.

**Export effective config** writes the device-baked Effective Config to
an operator-chosen path (default `/root/<name>.effective.jsonc`, with a
"`/root` is RAM on the live ISO — point at a USB to keep it" note),
**never** into the repo's `hosts/` tree.

## Acceptance criteria

- [x] Save emits a closed-schema-valid Host Profile that is a clean delta
      over Host Core and device-less; it re-installs via `install.sh
      --profile <name>`.
- [x] Save refuses to overwrite an existing host/user profile and prompts
      for a new name; there is no overwrite path.
- [x] Export writes a device-baked Effective Config to a chosen path
      (default `/root`, with the RAM warning), never under `hosts/`; it
      re-installs via `install.sh <config-file>`.
- [x] bats: emitter (profile delta strips disks; effective config carries
      disks) + collision refusal.

## Blocked by

- `01-guided-install-tracer-bullet`
- Soft: `03-filesystem-axis-encryption-impermanence`,
  `04-disks-advanced-presets` (fuller content to save/export)

## Comments

**DONE via /tdd (2026-06-21) — issue CLOSED; final issue of the PRD.**

Pure (emit.sh): `guided_profile_delta` strips every device path (the single
`.disk` + per-pool `.disks[]`), keeping the mode/topology/disk_count skeleton —
the committed audit artifact never carries operator-picked devices (ADR 0036).

Writers (new `lib/guided-save.sh`, pure deps state/emit/profile — no fzf):
`guided_save_host_profile <state> <name>` refuses an existing `hosts/<name>/`,
schema-validates the device-less delta, writes `hosts/<name>/profile.jsonc`
(re-loads via `load_profile`, applies over Host Core, schema-clean).
`guided_export_config <effective> <path>` writes the device-BAKED config,
refusing any path under `hosts/` (realpath-guarded). New
`tests/config/guided-save.bats` (5: delta-strip, save loadable, host collision,
export device-baked, export hosts/ guard).

Shell (guided.sh): `guided_build` gained a terminal-action branch
(_GUIDED_ACTION proceed|save|export; replay `terminal` key / the menu loop sets
it). Save is device-less (no disk/assignment) + refuses a colliding ad-hoc
`users/<n>/` BEFORE writing the host (no half-written artifacts) + materializes
ad-hoc users. Export bakes disks like Proceed, warns `/root` is RAM, defaults to
`/root/<host>.effective.jsonc`. Both return `_GUIDED_ACTION_DONE` (64);
`install.sh` treats 64 as "artifact written — skip the back-end install". Menu
loop offers Save/Export with the same disk gate as Proceed (Save needs none).
guided-shell(+5).

Tests: +10 → full suite **1235 bats**, shellcheck clean.
