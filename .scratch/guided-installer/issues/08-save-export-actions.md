# Terminal actions — Save profile + Export effective config

Status: ready-for-agent

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

- [ ] Save emits a closed-schema-valid Host Profile that is a clean delta
      over Host Core and device-less; it re-installs via `install.sh
      --profile <name>`.
- [ ] Save refuses to overwrite an existing host/user profile and prompts
      for a new name; there is no overwrite path.
- [ ] Export writes a device-baked Effective Config to a chosen path
      (default `/root`, with the RAM warning), never under `hosts/`; it
      re-installs via `install.sh <config-file>`.
- [ ] bats: emitter (profile delta strips disks; effective config carries
      disks) + collision refusal.

## Blocked by

- `01-guided-install-tracer-bullet`
- Soft: `03-filesystem-axis-encryption-impermanence`,
  `04-disks-advanced-presets` (fuller content to save/export)
