# ADR 0036: Unified profile-driven host config

## Status
Accepted (implemented across `.scratch/unified-host-profile/` issues
01-10 + 12, VM-verified; doc rewrite issue 11 pending). Supersedes the
file split in ADR 0001 and ADR 0010 (the Pre-Install Picker is now the
`install.sh --profile` front-end, not a separate `tools/pick.sh`); narrows
ADR 0002's reach; amends ADR 0015 (open -> closed schema) and ADR 0035
(VM `install: "repo"` redefined).

## Context
A machine is currently described by three files: `install.jsonc`
(disk/locale/boot/options), `hosts/<p>/install.template.jsonc` (the
per-host machine properties the picker copies through), and
`hosts/<p>/config.jsonc` (users + system programs + packages). The
glossary calls only the last one the "Host Profile," yet operators think
of "the profile" as the whole machine. That three-file split (ADR 0001)
plus the template/assembled-config indirection is the main reason the
architecture diagrams are hard to follow.

Goal: one file per machine, a small un-bloated schema, and an install
flow that reads like the VM harness (`vm.sh --profile`, ADR 0035).

The one field that genuinely cannot live in a committed per-host file is
`disks` -- it is machine-physical and operator-picked at install time
(the reason `install.jsonc` existed as a separate assembled artifact).

## Decision
Collapse the three files into one unified per-host `profile.jsonc` under
`.os/hosts/<name>/`, merged with `hosts/core/profile.jsonc` (core
layering from ADR 0004 preserved). The user side renames in step for
symmetry: `users/<name>/config.jsonc` -> `users/<name>/profile.jsonc`
(+ `users/core/profile.jsonc`). Programs keep `config.jsonc`. Files now
match the nouns: `profile` = a host/user, `config` = a program spec.

install.sh keeps one back-end (consume an assembled effective config)
behind two front-ends:
- `install.sh --profile <name>` -- interactive: the picker resolves
  disks and assembles the effective config in tmpfs. The user-facing
  command.
- `install.sh <config-file>` -- unattended seam: consume a
  pre-assembled effective config, exactly the path the VM cloud-init
  seed already injects, reused unchanged.
`--disk` flags are optional sugar on `--profile` for scripted bare-metal
and may be deferred. The assembled effective config (disks included) is
never a committed source -- only a transient artifact (tmpfs or
seed-injected). Authored `install.jsonc` and `install.template.jsonc`
are retired; the `host_profile` *field* is dropped (the directory name /
`--profile` arg is the identity).

Scope of the unified profile (resolved during design):
- sops, display manager, cpu/microcode, and audio stay AUTOMATIC -- no
  toggles added. Keeps ADR 0025 (sops secrets-activated); DM derived
  from the DE; both ucodes always installed; PipeWire when a DE is
  selected. Each added toggle would re-bloat the schema against the goal.
- Add `options.ssh.enabled` (default false) -> enable `sshd.service`.
  Closes a real gap: `openssh` is installed today but never enabled.
- `system.locale` and `system.keymap` become arrays; element 0 is the
  default (`LANG` / console keymap), the rest are generated locales /
  available desktop layouts. `identity.sh` uncomments every `locale[]`
  in `locale.gen`, sets vconsole `KEYMAP=keymap[0]`, and (when a desktop
  is selected) writes `/etc/X11/xorg.conf.d/00-keyboard.conf` with
  `XkbLayout=keymap[]`. The Hyprland adapter writes its own `kb_layout`
  (it ignores `xorg.conf.d`).
- The profile carries the full pool skeleton -- `os_pool` +
  `storage_groups` + `data_pools` with names/topology/mount/ashift/
  owners -- but NO device fields. The picker maps operator-picked disks
  onto the declared groups at assemble time (a new disk->group step,
  validated against the existing min-disk table).
- No host `services` field -- services stay program-owned (ADR 0002).
  User profiles gain a user-level `systemctl --user enable` list; a unit
  not found at enable-time (after user programs + dotfiles are placed)
  aborts with an actionable message.
- Programs are unchanged: ADR 0002 stays strict (metadata
  `config.jsonc` + mandatory `install.sh`).
- "A host can have multiple profiles" means many named profiles exist
  and the install selects one (+ core) -- the existing decoupling of
  ADR 0020, not multi-profile composition.

User <-> system-program references (refines the old always-abort rule):
- user-level programs may shadow a host program;
- a user referencing a system program the host already installs -> no-op;
- a user referencing a system program no host installs -> abort with an
  actionable message. The `system` flag stays host-owned (ADR 0002).

Closed-schema validation (amends ADR 0015): every authored config (host
profile + core, user profile + core, program `config.jsonc`) is
validated against a closed schema at load. Any unknown key at any depth
aborts with its path, before any disk write. Implemented by completing
`_INSTALL_CONFIG_SCHEMA` into the single authoritative table driving
reads, defaults, AND recursive unknown-key rejection -- jq-based, no new
live-ISO dependency, one source so reads and validation can't drift.
Program `config.jsonc` is in v1 scope (a typo'd `system` key silently
misroutes a program system<->user).

VM harness (amends ADR 0035): a VM Profile's `host_profile` resolves to
the unified `profile.jsonc` (the picker assembles it + virtual disks);
the `install: "repo"` source is redefined to mean "the repo's designated
default Host Profile," named by a single pointer constant in the harness
(e.g. `VM_DEFAULT_HOST_PROFILE="desktop"`) -- no synthetic profile, no
per-profile marker.

## Consequences
- `install.jsonc`, `install.template.jsonc`, the Install Config and
  Install Template glossary terms, and the picker's template-merge path
  are removed. The picker shrinks to "pick profile + pick disks -> tmpfs
  config."
- The committed audit artifact is the profile (disks excluded), not an
  assembled `install.jsonc`. Disks were never meant to be committed.
- A closed schema must enumerate every valid key; adding an option means
  updating the schema -- the cost that buys typo-proof configs.
- `vm/lib/profile.sh` and `profile-validate.sh` rewire off the template;
  `picker_assemble_config` consumes the profile directly.
- ARCHITECTURE.md diagrams collapse: three host inputs become one and
  the template -> install.jsonc assembly node disappears.
- A "designated default Host Profile" mechanism is needed for VM `repo`.

## Migration
Big-bang end state: no dual-read survives. To land the ~29-file change
while keeping every commit green, migrate behind a transient scaffold:
an internal `load_profile` reads a real `profile.jsonc` or synthesizes
one from the legacy template + config through the existing
`picker_assemble_config`. Then hosts/users move to real `profile.jsonc`
in small green commits -- tracer first on `arch-data` (the host with no
template) -- and the scaffold plus the legacy readers are deleted in the
final commit. 11 host files + 4 user configs become `profile.jsonc`;
`config.jsonc` / `install.template.jsonc` are removed (programs keep
`config.jsonc`). The root `install.jsonc` is deleted; its single / multi
/ data_pools example blocks relocate to the schema reference, and the
per-host profiles become the live examples.
