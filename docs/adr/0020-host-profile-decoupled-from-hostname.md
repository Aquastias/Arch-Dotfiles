# ADR 0020: Host Profile decoupled from machine hostname

## Status
Accepted. Supersedes the "basename becomes hostname … no override"
clause of ADR-0010 and the "which host config to apply (sets
hostname)" framing of the same.

## Context
ADR-0010 fused two roles into one identifier: the `hosts/<name>/`
directory served as both the profile key (which bundle of users +
packages + template to apply) and the machine hostname. Two laptops
running the same software bundle thus needed two duplicated host
directories that differed only in name.

The operator-facing pain: "I want two identical desktops with
different hostnames" is not expressible without copying the entire
`hosts/<name>/` tree.

## Decision
Split the two roles:

- **Host Profile** — the bundle, keyed by directory basename under
  `.os/hosts/<name>/`. Selected via a new top-level `host_profile`
  field in `install.jsonc`.
- **Machine hostname** — `system.hostname` in `install.jsonc`,
  written to `/etc/hostname` unchanged.

Resolution rules:

- `install.template.jsonc` may optionally set `system.hostname`. When
  set, the picker writes that value into the generated
  `install.jsonc`. When unset, the picker falls back to the profile
  name.
- `host_profile` in `install.jsonc` is optional. When unset,
  `validation.sh` falls back to `system.hostname` (preserving today's
  "dir name == hostname" behaviour for existing/hand-written configs
  and for VM test fixtures).
- `system.hostname` empty triggers the same TTY prompt as today;
  `host_profile` follows whatever the prompt resolves.

## Considered alternatives
**Keep them fused (status quo).** Forces directory-per-machine even
when machines share every package and user. Disallows the duplicate-
desktop use case the operator asked for.

**Override only in `install.jsonc`, not in the template.** Operator
must remember to edit `install.jsonc` after every `pick.sh` run.
Defeats the picker's "templates pin per-machine choices" purpose.

**Single field, magical resolution** (e.g. `name@hostname` syntax).
Compresses the schema but obscures the distinction the split is
trying to surface.

## Consequences
- `lib/secrets.sh` and `lib/install-state.sh` rename their arg from
  `hostname` to `profile` (the arg was always a profile key; the
  name was misleading). No behavioural change in either function.
- `seed-generator.sh` is unaffected — VM tests never used host
  profiles (`hosts/vm-test-*/` does not exist; preflight no-ops).
- `picker.bats` test "hostname overrides any template value"
  inverts: template hostname now wins, picker no longer overrides.
- ADR-0010's two-facts-to-resolve framing becomes: profile +
  (hostname when not pinned by template) + disks.
- `hosts/desktop/` and `hosts/laptop/` gain minimal
  `install.template.jsonc` files (pinning hostnames `eterniox` and
  `chronos` respectively) and become pickable in `pick.sh` for the
  first time.
