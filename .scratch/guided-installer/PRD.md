# Guided Installer

Status: done (all issues 01–08 closed, 2026-06-21)

Decision of record: ADR 0039 (Guided Installer as a third,
profile-optional front-end) + ADR 0040 (Filesystem Adapter axis).
Builds on ADR 0036 (unified profile / Effective Config), 0037 (per-group
disk_count), 0004 (core base layer), 0024 (kernel list + ZFS Module
Guard), 0023 (archzfs-Compatible ISO), 0008 (impermanence), 0031 (pool
owners), 0032 (lib taxonomy).

Glossary: Guided Installer, Config State, Filesystem Adapter, Effective
Config, Host Profile, Host Core, User Profile, User Core, Pre-Install
Picker, Single Entry Point, System Program, Program Runner, Layout
Module, Storage Group, Standalone Data Pool, Kernel Selection, ZFS Module
Guard, Impermanence, Curated Persist Defaults, Persist Extensions,
Environment Config, GPU Resolution, Display Manager, Base Package List,
Host Package List, Categorized List.

## Problem Statement

To install a machine today the operator must hand-author a
`hosts/<name>/profile.jsonc` in an editor before anything can run — and
bare `install.sh` dead-ends into `generate_template`, which writes a
stub `install.jsonc` and tells you to edit it in vim and re-run. There
is no guided, interactive path: no way to sit at the live ISO, build an
install by menu, see what you've set, change your mind, and either
install now or save the result for next time. archinstall offers exactly
that and the operator wants the same — adapted to this installer's own
config model.

Two further pains: the installer is **ZFS-welded top to bottom** (schema,
layout adapter, encryption, impermanence, bootloader), so there is no
seam to add the btrfs / ext4 / xfs / LUKS the operator wants later
without a painful schema migration; and the committed Host Profile is
the only audit artifact, so any guided/ephemeral path has to be
reconciled with that — not bolted on as a way to quietly erode it.

## Solution

A third front-end over the one back-end (ADR 0036's two become three):
the **Guided Installer**, launched by bare `install.sh`, an fzf-driven
menu that builds an install interactively and hands the existing back-end
the same **Effective Config** the Pre-Install Picker produces.

It is built on a single in-session **Config State** — a *sparse override
map* over the computed defaults (accessors + Host Core), so it emits only
what the operator changes and the back-end fills the rest. Navigation is
non-destructive: every screen is re-entrant, edits commit on confirm
(never on `Esc`), changes survive moving between sections, validation is
deferred to the terminal actions, and mistakes are recoverable three ways
— re-edit, **Reset** (field / section / all), and **Undo/Redo** over a
snapshot stack. fzf is the uniform selection/navigation surface; only
free-text fields with nothing to enumerate drop to a typed prompt.

The menu is split **Host** / **Users**, mirroring the artifacts a save
writes. It ends in one of three terminal actions: **Proceed** (assemble
a tmpfs Effective Config from the choices plus picked disks, then run
`01 → 02 → 03`), **Save profile** (write a device-less
`hosts/<name>/profile.jsonc` as a delta over Host Core — the committed
audit artifact, replayed via `--profile`), or **Export effective config**
(write the device-baked artifact to an operator path *outside* the repo's
`hosts/` tree, replayed via `install.sh <config-file>`).

The Disks section is **filesystem-first**. To make later filesystems
additive rather than a migration, a **Filesystem Adapter** axis is
reserved now while only ZFS is implemented: a top-level `filesystem`
discriminator (default `zfs`; existing ZFS layout fields stay flat),
encryption stays a bool plus an additive `options.encryption_method`
(`native` | `luks`, default derived from `filesystem`), and the layout
dispatch generalizes to a filesystem-keyed seam. Encryption and
Impermanence live under Disks because the filesystem governs them;
Impermanence is offered only for ZFS/btrfs and hidden for ext4/xfs.

`generate_template` is retired; the VM seed passes its Effective Config
positionally instead of leaning on the bare-default `install.jsonc`.

## User Stories

1. As an operator, I want to run bare `install.sh` and get an
   interactive installer, so that I never hand-edit a stub in vim first.
2. As an operator, I want fzf to drive every menu and list, so that
   selection feels consistent throughout.
3. As an operator, I want to type values that can't be enumerated
   (hostname, package names, sizes, URLs, sysctl pairs, persist paths),
   so that free-form fields aren't forced into a list.
4. As an operator, I want to leave any section and come back without
   losing what I set, so that I can move around freely.
5. As an operator, I want each row to show its current value and a `●`
   when it differs from the default, so that I can see what I've touched.
6. As an operator, I want to reset a single field, a whole section, or
   everything to defaults, so that I can back out of a mess.
7. As an operator, I want Reset-all to confirm and be itself undoable, so
   that I can't wipe my work by accident.
8. As an operator, I want Undo and Redo across my edits, so that I can
   step back and forth through changes regardless of section.
9. As an operator, I want the menu split into Host and Users, so that I
   can see which file each choice ends up in.
10. As an operator, I want Proceed disabled until the disk layout is
    valid, so that I can't start an install that can't complete.
11. As an operator, I want to set the hostname, locale, timezone, and
    keymap, so that system identity is mine to choose.
12. As an operator, I want locale / timezone / keymap picked from the
    live system, so that I choose from real, valid values.
13. As an operator, I want to choose the filesystem first in the Disks
    section, so that everything beneath it is shaped by that choice.
14. As an operator, I want ZFS available now and btrfs/ext4/xfs shown as
    reserved, so that I know what's coming without it pretending to work.
15. As an operator, I want one-pick ZFS shapes (single, OS mirror, OS
    mirror + raidz1, OS none + data pools), so that common layouts are a
    single choice.
16. As an operator, I want an Advanced door to author the pool skeleton
    by hand (mode, os_pool, storage_groups, data_pools), so that the long
    tail is still reachable.
17. As an operator, I want to pick disks with the same lsblk/SMART
    preview the Pre-Install Picker uses, so that I assign the right
    drives.
18. As an operator, I want the per-group disk assignment shown and
    validated against the min-disk table before I accept, so that a
    multi-disk layout is never implicit.
19. As an operator, I want encryption under Disks with the method gated by
    the filesystem (ZFS → native, others → LUKS), so that I can't pick an
    impossible combination.
20. As an operator, I want Impermanence under Disks, offered only on
    ZFS/btrfs and hidden on ext4/xfs, so that it appears only where it can
    work.
21. As an operator, I want the Curated Persist Defaults applied
    automatically when Impermanence is on, so that system identity
    survives without me listing it.
22. As an operator, I want to add my own Persist Extensions, so that extra
    paths survive reboots.
23. As an operator, I want to choose one or more kernels from
    linux-lts / linux / linux-hardened / linux-zen, so that I run the
    kernel I want.
24. As an operator, I want non-lts kernels offered even on ZFS with the
    ZFS Module Guard as the backstop, so that I can try zen/hardened and
    fail fast if archzfs can't build them.
25. As an operator, I want to choose the bootloader (grub or
    systemd-boot), so that boot matches my preference.
26. As an operator, I want to toggle swap and type a swap size, so that I
    control swap sizing.
27. As an operator, I want to set the ESP size, toggle SSH, and set an
    age_key_url, so that the FS-agnostic options are all reachable.
28. As an operator, I want to choose a desktop — kde, hyprland, or both,
    so that I get the environment I want.
29. As an operator, I want GPU to default to auto or let me pick any of
    amd/nvidia/intel, so that hybrid setups are expressible.
30. As an operator, I want to pick mirror countries (default
    Germany/Switzerland/Sweden/France/Romania), so that reflector sorts
    fast mirrors near me.
31. As an operator, I want to toggle multilib (on by default), so that I
    control whether [multilib] is enabled.
32. As an operator, I want to type extra packages inline, so that I can
    add arbitrary repo packages.
33. As an operator, I want a typed extra-package name that matches a
    program under `programs/` to install via the Program Runner, so that
    it gets that program's full setup, not a raw pacstrap.
34. As an operator, I want to set sysctl keys (swappiness pre-set to 10),
    so that I can tune the kernel.
35. As an operator, I want the rarely-touched host knobs (system
    programs, sysctl, persist, post-install, dotfiles repo) under an
    Advanced subgroup, so that the main menu stays focused.
36. As an operator, I want to pick existing committed user profiles, so
    that I reuse my curated user across machines.
37. As an operator, I want to create a new user ad-hoc (name, shell,
    sudo, groups, programs, git, ssh keys), so that I don't need to
    hand-write a user profile first.
38. As an operator, I want to set a user's password in the TUI (default
    12345), so that the machine is usable on first boot without editing
    secrets.
39. As an operator, I want to set the root password in the TUI, so that
    root is configured during the install.
40. As an operator, I want the first selected user marked as the
    AUR/paru user and default pool owner, so that the Primary User is
    explicit.
41. As an operator, I want to Proceed and install immediately from my
    choices plus picked disks, so that I don't have to save anything.
42. As an operator, I want a final review screen listing host, fs, disks,
    desktop, users, and the disks that will be WIPED, with a typed
    INSTALL confirmation, so that I don't destroy data by accident.
43. As an operator, I want to Save my session as a device-less Host
    Profile that extends Host Core, so that I get a committed, reusable,
    audit-clean artifact.
44. As an operator, I want Save to refuse to overwrite an existing
    `hosts/<name>/` or `users/<name>/` profile and demand a new name, so
    that I never clobber hand-authored config.
45. As an operator, I want Export to write a device-baked Effective
    Config to a path I choose outside the repo, so that I can replay the
    exact install later via `install.sh <config-file>`.
46. As an operator, I want Export to default to `/root/<name>.effective.
    jsonc` and warn that /root is RAM on the live ISO, so that I know to
    point it at a USB to keep it.
47. As an operator, I want my passwords applied at install time but never
    written into the saved profile or exported config, so that no
    plaintext secret lands in a file.
48. As a maintainer, I want the guided session to merge over Host Core,
    so that the shared base (cups, swappiness, base users) still applies.
49. As a maintainer, I want unknown keys rejected by the closed schema
    before any disk is touched, so that the guided output is as safe as a
    hand-authored profile.
50. As a maintainer, I want the filesystem axis reserved in the schema
    now, so that adding btrfs/ext4/xfs later is an additive adapter, not
    a migration.

## Implementation Decisions

- **New front-end (ADR 0039).** Bare `install.sh` (no `--profile`, no
  positional config) launches the Guided Installer, slotting in at the
  same seam the `--profile` branch uses: build config → set the
  positional config → fall through to `01 → 02 → 03`. The two existing
  front-ends are unchanged. `generate_template` and the bare-default
  `install.jsonc` fallback are removed; missing config on the
  non-guided path is an error.

- **Config State — the deep core.** A sparse override map over computed
  defaults. Interface verbs: `get`/`set`/`unset` by JSON path,
  `is-overridden`, `reset(field|section|all)`, and a snapshot stack with
  `push`/`undo`/`redo`. Every mutating action snapshots first, so one
  action = one undo step (including Reset-all). Stack is unbounded
  (state is small). Pure: in-memory JSON, no TTY.

- **Emitter — pure.** Config State (+ optional disk assignment) →
  device-less **Host Profile** (emitted as a delta over Host Core, so the
  saved file cleanly "extends core") or device-baked **Effective Config**.
  Owns the **program-promotion split**: a typed `packages.extra` entry
  that resolves to a `programs/<category>/<name>/` is moved into
  `system_programs`; non-matches stay repo packages; a name that is both
  resolves as the program. The back-end's System-Program-vs-package
  contract is untouched — resolution is TUI-side only.

- **Menu model — pure.** Config State → menu rows (section, summary, `●`
  override flag, `✓`/`⚠` validity) and per-field metadata (type:
  enum | multi | bool | text | reference; default source; enumerable
  source). Drives both the fzf shell and the tests, so "full parity"
  means "every schema field has a row."

- **Disk skeleton builder — pure.** Menu choices → ZFS pool skeleton
  (mode/topology/groups/`disk_count`), reusing the existing
  `suggest_os_topologies` / `suggest_storage_topologies` (rules) and
  `picker_validate_layout`; disk picking and per-group assignment reuse
  `picker_build_assignment` / `picker_assign_disks` / the picker preview.
  Writing topology into the config means the layout phase's
  "topology set → don't prompt" branch fires, so there is no double
  prompt at install time.

- **fzf shell + entry — the only impure module.** Renders fzf menus,
  reads input, dispatches to Config State mutations, handles `Esc` = back
  (non-destructive), and runs the three terminal actions. fzf for all
  enumerable selection and navigation; typed prompt only for free-text.
  Multi-select re-entry pre-marks prior picks from the state.

- **Passwords.** Proceed prompts for root and per-user passwords (default
  user password 12345); the TUI writes the *decrypted* secrets shape
  (`{root_password}`, per-user `{password, ssh_identity_private_key?}`)
  to tmpfs and points the Runner at it via install-state — the same
  downstream contract the Secrets Module produces, **without SOPS**.
  Install-time only; not persisted by Save or Export.

- **Filesystem Adapter axis (ADR 0040).** Top-level `filesystem`
  discriminator, default `zfs`; existing ZFS layout fields stay flat;
  future filesystems add namespaced fields gated by contract checks.
  `options.encryption` stays a bool (enabled); `options.encryption_method`
  added (`native` | `luks`, default derived from `filesystem`). Layout
  dispatch generalizes to a filesystem-keyed seam (ZFS the only
  implementation). Impermanence and the bootloader `root=` are
  filesystem-conditional. Build is ZFS-only; the rest is reserved.

- **Schema additions** (closed schema + accessors + validation in
  lockstep): `filesystem`, `options.encryption_method`,
  `options.mirror_countries[]` (default Germany/Switzerland/Sweden/France/
  Romania → `reflector --country`), `options.multilib` (bool, default
  true → makes the existing always-on `enable_multilib` honour a flag).
  New `validation.sh` contract checks: fields-set match `filesystem`;
  encryption method matches filesystem; Impermanence only on ZFS/btrfs.

- **Field behaviours.** GPU: `auto` or multi amd/nvidia/intel (auto
  clears vendors). Kernel: multi over lts/default/hardened/zen tokens,
  first = Primary Kernel; all offered on ZFS with the ZFS Module Guard as
  backstop. Desktop: multi kde/hyprland. Bootloader: grub | systemd-boot.
  Swap size, ESP size, sysctl pairs, persist paths, dotfiles repo:
  free-text. Curated Persist Defaults auto-applied when Impermanence on.

## Testing Decisions

A good test asserts **external behaviour, not implementation** — for the
pure modules that means feeding an input (a Config State, an edit
sequence, a set of menu choices, a config JSON) and asserting the emitted
output (state, JSON, rows, validity), never internal structure. Prior
art: `tests/picker.bats` and `tests/config/*.bats` (JSON-in/JSON-out, no
TTY) and the existing `validation` bats.

Modules getting bats unit tests (confirmed):

- **Config State** — apply an edit sequence and assert resulting state;
  override tracking; `reset` at each level; `undo`/`redo` (including
  undo of Reset-all). Highest-value tests.
- **Emitter + program promotion** — state → Host Profile (assert it is a
  clean delta over Host Core) and → Effective Config (assert device
  paths); assert the program-promotion split routes program names to
  `system_programs` and leaves non-matches as packages.
- **Menu model** — state → rows/summaries/`●`/validity; assert every
  schema field surfaces a row (the "full parity" guard) and that Disks
  validity gates Proceed.
- **Disk skeleton + schema contracts** — skeleton-from-choices reuses and
  agrees with `picker_validate_layout`; the new filesystem / encryption /
  impermanence contract checks accept valid combinations and reject
  invalid ones with the offending path.

The **fzf shell stays smoke-only** (no bats). Its output — the assembled
Effective Config — is already exercised by the existing VM profiles; the
guided path produces the same artifact the back-end and VM suite already
cover.

## Out of Scope

- Implementing btrfs / ext4 / xfs / LUKS adapters — the axis is *reserved*
  now; only ZFS is built. Those are reserved/disabled menu entries.
- Committing passwords from the TUI (SOPS encryption into `secrets.json`)
  — Save/Export are password-less; the existing SOPS flow (README §4)
  remains the way to persist secrets.
- Autosave / resume across a TUI quit — "don't lose changes" is
  within-session; deliberate persistence is via Save/Export.
- `[testing]` and other repos — only multilib is toggleable; testing is
  deliberately excluded (it pulls kernels archzfs can't track and breaks
  the ZFS DKMS build).
- Mirror selection beyond country granularity.
- Editing Host Core / User Core from the TUI — the Guided Installer
  authors a profile that extends core; it never modifies core.

## Further Notes

- Generalizing layout dispatch to a filesystem-keyed seam will relocate
  the ZFS layout files into a `zfs/` subdir — the BASH_SOURCE
  root-sibling foldering hazard (lib taxonomy gotcha); handled when
  filesystem #2 lands, not now.
- `reflector --list-countries` needs network (already a documented
  prerequisite, and the picker already `pacman -Sy`s); offline, the
  country picker falls back to the 5-country default plus free-text.
- Retiring `generate_template` has a known blast radius: the bare-default
  in `install.sh` and `03-install.sh`, `load_config`'s missing-config
  branch in `lifecycle.sh`, and the VM seed (the cloud-init user-data
  templates that base64-decode an Effective Config and the
  seed-generator bats assertion) — switch the seed to invoke the
  installer with a positional config path.
- CONTEXT.md (Guided Installer, Filesystem Adapter, 3-front-end Single
  Entry Point) and ADR 0039 / 0040 were written during design. The full
  22-decision ledger lives in the design conversation.
- Suggested slicing for `/to-issues`: (1) Config State + bats; (2)
  Emitter + promotion + bats; (3) Menu model + bats; (4) Disk skeleton +
  contracts + bats; (5) fzf shell; (6) bare-`install.sh` entry + retire
  template + VM-seed positional fix; (7) schema seam (filesystem,
  encryption_method, mirror_countries, multilib); (8) VM smoke.
