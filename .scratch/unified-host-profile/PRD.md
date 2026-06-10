# Unified profile-driven host config

Status: ready-for-agent

Decision of record: ADR 0036 (supersedes the split in 0001, narrows
0002, amends 0015 + 0035).

Glossary: Host Profile, Host Config, Host Core, Install Config, Install
Template, Pre-Install Picker, User Config, User Core, System Program,
User Program, Runner, Single Entry Point, Storage Group, Standalone Data
Pool, Pool Owners, Layout Module, Environment Config, Display Manager,
SOPS Runtime Service, VM Profile, VM Harness.

## Problem Statement

A machine is described by three files — `install.jsonc`
(disk/locale/boot/options), `hosts/<p>/install.template.jsonc` (the
per-host machine properties the picker copies through), and
`hosts/<p>/config.jsonc` (users + system programs + packages). The
glossary calls only the last one the "Host Profile," yet the operator
thinks of "the profile" as the whole machine. That three-file split
plus the template → assembled-`install.jsonc` indirection is the main
reason the architecture diagrams are hard to follow, and a typo'd key
(`options.encrytion`) silently no-ops into a broken install because the
config is read through an open whitelist of accessors that ignore
unknown keys. The operator wants one file per machine, a small schema
that rejects nonsense loudly, and an install flow as simple as "edit the
profile (or run the picker), then install."

## Solution

Collapse the three files into one unified per-host **Host Profile** at
`hosts/<name>/profile.jsonc`, merged with `hosts/core/profile.jsonc`.
The user side renames in step for symmetry —
`users/<name>/config.jsonc` → `users/<name>/profile.jsonc` (+
`users/core/profile.jsonc`). Programs keep `config.jsonc`. Files now
match the nouns: *profile* = a host/user, *config* = a program spec.

The entry point becomes `install.sh --profile <name>`, mirroring
`vm.sh --profile`. The one field that cannot be committed — `disks` — is
operator-picked at install time; the effective install config (disks
included) is assembled in tmpfs and never committed. `install.sh` keeps
one back-end (consume an assembled effective config) behind two
front-ends: `--profile <name>` (interactive; the Pre-Install Picker
resolves disks) and a positional `<config-file>` (the unattended seam
the VM cloud-init seed already injects, reused unchanged).

Every authored config is validated at load against a single closed
schema: any unknown key at any depth aborts with its path, before any
disk write. The schema and the read-accessors become one table, so they
cannot drift.

Authored `install.jsonc` and `install.template.jsonc` are retired; the
`host_profile` *field* is dropped (the directory name / `--profile` arg
is the identity). The migration runs behind a transient assembler so
every commit stays green.

## User Stories

1. As an operator, I want one `profile.jsonc` per machine, so that I
   stop reasoning about three files that describe one host.
2. As an operator, I want `install.sh --profile <name>`, so that
   installing is one discoverable command.
3. As an operator, I want the picker to ask only for the profile and the
   disks, so that everything else comes from the committed profile.
4. As an operator, I want disks resolved at install time and never
   committed, so that a profile is portable across machines of the same
   shape.
5. As an operator, I want the user config renamed to `profile.jsonc`
   too, so that "host profile" and "user profile" match on disk.
6. As an operator, I want a typo'd key to abort with its path before any
   disk is touched, so that a misspelled `options.encryption` can never
   silently produce a broken install.
7. As an operator, I want unknown keys rejected at any depth, so that
   nested typos (`options.impermanence.enabld`) are caught too.
8. As an operator, I want the program `config.jsonc` validated too, so
   that a typo'd `system` key can't misroute a program system↔user.
9. As an operator, I want the profile to carry the full pool skeleton
   (names/topology/mount/ashift/owners) minus devices, so that a
   multi-disk machine's layout is reproducible and only the physical
   disks are picked.
10. As an operator, I want the picker to map my picked disks onto the
    declared pool groups, validated against the min-disk table, so that
    I can't under-populate a raidz1.
11. As an operator, I want `system.locale` and `system.keymap` as arrays
    with element 0 as the default, so that I can have several locales
    generated and several keyboard layouts available.
12. As a desktop user, I want my extra keyboard layouts available in the
    session, so that I can toggle between them without post-install
    fiddling.
13. As an operator, I want `options.ssh.enabled`, so that I can have
    `sshd` enabled on first boot instead of installed-but-inert.
14. As an operator, I want sops, display manager, cpu microcode, and
    audio to stay automatic, so that the schema doesn't grow toggles for
    things the installer can derive.
15. As a user, I want my user-level programs to install even when they
    share a name with a host program, so that I can have my own version
    of a non-root tool.
16. As a user, I want listing a system program the host already installs
    to be a no-op, so that referencing it is harmless rather than fatal.
17. As an operator, I want a user that references a system program no
    host installs to abort with an actionable message, so that a user
    can't silently trigger (or silently miss) a root-level install.
18. As a user, I want a user-level `systemctl --user enable` list, so
    that my per-user services come up without modeling each as a program.
19. As a user, I want a `user_services` entry whose unit isn't found to
    abort with a clear message, so that a typo doesn't silently leave a
    service disabled.
20. As a developer, I want a VM Profile's `host_profile` to resolve to
    the unified `profile.jsonc`, so that VM tests exercise the real
    profile, not a copied template.
21. As a developer, I want `install: "repo"` to mean "the designated
    default profile" named by one constant, so that the shipped-default
    smoke test survives the loss of `install.jsonc`.
22. As a maintainer, I want the migration to keep every commit green via
    a transient assembler, so that I can bisect and review the change in
    small slices.
23. As a maintainer, I want `arch-data` (the template-less host)
    migrated first as the tracer, so that the smallest slice proves the
    whole path before the bulk migration.
24. As a maintainer, I want the root `install.jsonc` deleted and its
    example blocks relocated to the schema reference, so that the
    per-host profiles are the only live examples.
25. As a reader, I want the architecture diagrams to show one host input
    instead of three, so that the install flow is finally legible.

## Implementation Decisions

- **Profile Loader + closed schema** (deep module, `lib/config/`).
  `load_profile <name>` merges the host profile with host core and
  returns the effective config; an analogous path merges user profile +
  user core. The existing `_INSTALL_CONFIG_SCHEMA` (ADR 0015) is
  completed into the single authoritative table that drives reads,
  defaults, AND recursive unknown-key rejection — jq-based, no new
  live-ISO dependency. Validation covers host profile + core, user
  profile + core, and program `config.jsonc`. Reject-on-unknown is
  recursive (nested objects + arrays-of-objects such as
  `storage_groups[].*`) and reports the offending path; it runs at load,
  before any disk write.
- **Two front-ends, one back-end** (`install.sh`, `03-install.sh`).
  `--profile <name>` is the user-facing interactive path (picker
  resolves disks → effective config in tmpfs). The positional
  `<config-file>` remains the unattended seam the VM seed injects. The
  assembled effective config keeps the shape `03-install.sh` already
  consumes. `--disk` flags are optional sugar on `--profile`, deferrable.
  The `host_profile` field is removed from the schema.
- **Picker disk→group assignment** (deep module, `lib/picker.sh` /
  `tools/pick.sh`). The profile declares `os_pool` + `storage_groups` +
  `data_pools` with names/topology/mount/ashift/owners but no device
  fields. The picker prompts for the profile and the disks, then assigns
  picked disks onto the declared groups, validated against the existing
  min-disk table (mirror/stripe ≥2, raidz1 ≥3, raidz2 ≥4). Single mode
  resolves one device. Output is the tmpfs effective config.
- **Transient migration assembler** (deleted at end). An internal
  `load_profile` reads a real `profile.jsonc` or synthesizes one from
  legacy template + config via the existing `picker_assemble_config`, so
  code reads "a profile" before the files are migrated. Removed in the
  final commit together with the legacy readers.
- **identity locale/keymap arrays** (`lib/chroot/identity.sh`).
  Uncomment every `locale[]` in `locale.gen`; `LANG=locale[0]`; vconsole
  `KEYMAP=keymap[0]`; when a desktop is selected, write
  `/etc/X11/xorg.conf.d/00-keyboard.conf` with `XkbLayout=keymap[]`. The
  Hyprland adapter writes its own `kb_layout` from `keymap[]` (it ignores
  `xorg.conf.d`).
- **ssh toggle**. `options.ssh.enabled` (default false) enables
  `sshd.service` in the chroot. `openssh` is already in the Base Package
  List.
- **Automatic, not configured**: sops stays secrets-activated (ADR
  0025), Display Manager stays derived from the DE, microcode stays
  both-ucodes, audio stays PipeWire-when-DE. No schema fields added.
- **Runner reconciliation** (`lib/profiles/runner.sh`). User-level
  programs may shadow a host program; a user referencing a system
  program the host already installs is a no-op; a user referencing a
  system program no host installs aborts with an actionable message (the
  `system` flag stays host-owned, ADR 0002). A `user_services` list is
  enabled via `systemctl --user enable` after the user's programs +
  dotfiles are placed; a missing unit aborts with an actionable message.
- **VM harness rewire** (`vm/lib/profile.sh`, `profile-validate.sh`). A
  VM Profile's `host_profile` resolves through the picker to the unified
  `profile.jsonc`; the template-existence check is dropped. `install:
  "repo"` resolves to the profile named by one harness constant
  (`VM_DEFAULT_HOST_PROFILE`, default `arch-kde` — the repo smoke forces
  single-disk, so the default must be a single-pinned, slim host; the
  multi-disk `desktop` would demand ≥2 disks and a heavy AUR build).
- **Data + docs**. 11 host files + 4 user configs become `profile.jsonc`;
  `config.jsonc` / `install.template.jsonc` are removed (programs keep
  `config.jsonc`). Root `install.jsonc` is deleted; its single / multi /
  data_pools example blocks move to the schema reference (`REFERENCE.md`
  / `ARCHITECTURE.md`). The four `ARCHITECTURE.md` diagrams collapse the
  three host inputs into one and drop the template → install.jsonc node.

## Testing Decisions

Tests assert external behavior — the effective config a loader produces,
the errors a validator emits, the device assignment a picker computes —
never internal structure. bats, with fixtures, matching the existing
suites.

- **Profile Loader + schema** (prior art: `tests/config/`). Merge
  correctness (core + specific; arrays concat+dedupe, objects
  deep-merge, scalars specific-wins); defaults applied; recursive
  unknown-key rejection including nested objects, arrays-of-objects
  (`storage_groups[].bogus`), user profile, and program `config.jsonc`
  (a typo'd `system` key is caught). Assert the offending path appears
  in the error and that validation fails before any disk-touching phase.
- **Picker disk→group** (prior art: `tests/layout/`). Given a declared
  pool skeleton + a set of picked disks, assert the assignment and the
  min-disk validation (raidz1 with 2 disks fails with a clear message;
  single mode resolves one device). No libvirt.
- **Migration assembler** (equivalence). A legacy template + config
  synthesizes byte-for-decision-equal effective config to the
  hand-written `profile.jsonc` for the same host — the guard that lets
  every migration commit stay green.
- **Runner reconciliation** (prior art: `tests/profiles/`). user-level
  shadow installs; host-installed system-program reference → no-op;
  unsatisfied system-program reference → abort with message;
  `user_services` missing unit → abort with message.

## Out of Scope

- `--disk` flags for scripted bare-metal unattended installs (optional
  sugar; the VM seed path covers unattended today).
- Multi-profile composition / profile variants — "a host can have
  multiple profiles" stays pick-one-of-many (ADR 0020).
- Generating program installers from spec — ADR 0002 stays strict
  (metadata `config.jsonc` + mandatory `install.sh`).
- A `services` field on the host profile — host services stay
  program-owned.
- Any new sops / display-manager / cpu / audio config field.
- A downstream-fork migration script — 11 in-repo files are
  hand-migrated.

## Further Notes

- The redesign mirrors the VM harness work (ADR 0035): the install flow
  becomes profile-driven exactly as `vm.sh --profile` already is, and
  the picker's existing `picker_assemble_config` is the seam the
  transient migration assembler reuses.
- The closed schema is the un-bloat forcing function: every option must
  be enumerated, so the schema stays small and fully specified.
- Implementation details deliberately omitted (picker disk→group UX,
  accessor-table nesting convention, `--profile` name resolution across
  `hosts/vm/*`) are left to the slices.
