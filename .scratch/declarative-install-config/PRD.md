# PRD: Declarative Install Config Layer

Status: ready-for-human
Category: enhancement

## Problem Statement

Today, installing a new Arch Linux system from this repo requires editing `.os/install.jsonc` (which mixes disk, ZFS, locale, users, and packages into one file) and manually running per-program installers from `.pkglist/` after the OS is up. There is no clean way to declare a host's identity (which users, which system programs) or a user's profile (which programs, what shell, what groups) as a reusable, per-entity config. Common settings are duplicated across hosts and users. Software setup happens after the system is booted, so the user logs in to a half-configured machine and has to run scripts manually.

## Solution

Introduce a declarative configuration layer inside `.os/` with three entity types (Host Config, User Config, Program Config) plus a Core layer for shared defaults. The user clones the repo on an Arch live CD, edits the configs that describe their machine, and runs a single entry-point script. The installer handles ZFS bootstrap, disk wipe, partitioning, pacstrap, system program installation (via arch-chroot), and user program installation (via `arch-chroot /mnt su - <username>`) — all during the live CD phase. When the user reboots and logs in, the system is fully configured.

`install.jsonc` is preserved as the source of truth for live-CD-time concerns only (disk layout, ZFS topology, bootloader, locale, timezone, keymap, hostname, base package groups). Software and identity move to the new layer.

## User Stories

1. As a sysadmin, I want to declare a host's users and system programs in a single host config file, so that I can describe a machine's identity in one place.
2. As a sysadmin, I want each user to be defined in their own config file, so that the same user definition can be reused across hosts.
3. As a sysadmin, I want each program to be defined in its own folder with a config and an install script, so that programs are self-contained and easy to add or remove.
4. As a sysadmin, I want a host core config that every host inherits from, so that I do not duplicate base system programs across host configs.
5. As a sysadmin, I want a user core config that every user inherits from, so that I do not duplicate base user programs across user configs.
6. As a sysadmin, I want list fields to concatenate when merging core with specific configs, so that core declarations are always preserved and specific configs only add to them.
7. As a sysadmin, I want scalar fields to be overridable by the specific config, so that a user can set their own shell while still inheriting other defaults from core.
8. As a sysadmin, I want to mark each program as either a system program or a user program, so that the runner knows whether to install it as root via pacman or as the user via paru.
9. As a sysadmin, I want user configs to be rejected at validation time if they reference a system program, so that I cannot accidentally install root-only software in a user context.
10. As a sysadmin, I want to run a single `install.sh` script after providing my configs, so that I do not have to remember the order of bootstrap, wipe, and install steps.
11. As a sysadmin, I want disks to always be wiped as part of the install flow, so that I do not have to call a separate wipe script.
12. As a sysadmin, I want all software installation to happen during the live CD phase, so that when a user logs in for the first time the system is fully ready.
13. As a sysadmin, I want paru to be bootstrapped per user inside the chroot, so that user-level AUR packages can be installed during the install without ever booting the new system.
14. As a sysadmin, I want `base-devel` hardcoded into pacstrap, so that paru can be built inside the chroot for any user.
15. As a sysadmin, I want `git` to be declared explicitly per user (not installed by default), so that minimal users do not get tools they do not need.
16. As a sysadmin, I want all users to receive a default password of `12345` for now, so that I can complete an install without a password prompt and change passwords later.
17. As a sysadmin, I want the hostname in `install.jsonc` to implicitly link to the host config directory of the same name, so that I do not have to declare the link in two places.
18. As a sysadmin, I want a missing host config to be a warning rather than a hard error, so that the existing `install.jsonc`-only flow still works for backward compatibility.
19. As a sysadmin, I want programs to be referenced by name only in host and user configs, so that I do not have to repeat the category path in every reference.
20. As a sysadmin, I want a shared shell stdlib at `.os/lib/shell-stdlib.sh`, so that program install scripts have a single place to source utility functions from.
21. As a sysadmin, I want the runner to export `$OS_DIR`, `$PROGRAMS`, and `$SHELL_COMMONS` before calling each program install script, so that install scripts can locate addons and stdlib without hardcoded paths.
22. As a sysadmin, I want an existing program's install.sh to remain the source of truth for installation logic, so that complex programs (like teamspeak3 with its specific addon directory layout) can keep their bespoke logic.
23. As a sysadmin, I want a program's `config.jsonc` to be metadata-only (display name, system flag, description), so that the orchestrator only reads what it needs for routing decisions.
24. As a sysadmin, I want any leftover scripts created during install to be cleaned up before the install ends, so that the new system does not contain installation residue.
25. As a sysadmin, I want `install.jsonc` to retain its package groups section, so that base packages like the kernel and bootloader remain declared at the live-CD layer where they belong.
26. As a sysadmin, I want `hosts/core` and `users/core` reserved as directory names, so that they cannot conflict with a real host or user.
27. As a sysadmin, I want the `.pkglist/` directory left untouched as reference material, so that I can keep using its existing scripts independently while the new layer matures.
28. As a sysadmin, I want each new program inside `.os/programs/` to ship both `config.jsonc` and `install.sh`, so that the runner can rely on a consistent contract for every program.
29. As a sysadmin, I want the install flow to fail loudly if a referenced user or program does not exist, so that typos in configs are caught immediately rather than producing a partially configured system.
30. As a sysadmin, I want shellcheck applied to all scripts, so that common shell pitfalls are caught without needing to write tests for everything.
31. As a sysadmin, I want unit tests for the config loader/merger, so that I am confident the merge semantics (concatenate lists, override scalars) behave correctly under all combinations of core and specific config.

## Implementation Decisions

### Modules to build

- **Single Entry Point (`.os/install.sh`)** — top-level orchestrator. Sequences ZFS bootstrap, disk wipe, partitioning + pool creation, pacstrap, system configuration, profiles runner, cleanup. The numbered scripts (`01-bootstrap-zfs.sh`, `02-wipe.sh`, `03-install.sh`) remain on disk for modularity and debugging but are no longer the documented entry point.
- **Config Loader / Merger (`.os/lib/configs.sh`)** — the deep module of this PRD. Simple public interface: load a host or user config by name and return the merged result of core + specific. Encapsulates merge semantics (list concatenation with dedupe, scalar override, missing-field handling). Pure function in spirit — no side effects, no chroot calls — so it can be tested in isolation.
- **Profile Runner (`.os/lib/profiles.sh`)** — reads the merged host config, validates that all program references resolve and that user configs do not reference system programs, creates users (with default password `12345`), installs system programs via `arch-chroot pacman -S`, then for each user bootstraps paru and installs user programs via `arch-chroot /mnt su - <username>`. Cleans up any temporary scripts at the end.
- **Shell Stdlib (`.os/lib/shell-stdlib.sh`)** — port of `.pkglist/shell-commons/shell-stdlib.sh` into the `.os/` namespace. Same utility surface (string, array, command, package, output helpers).

### Modules to modify

- **`.os/lib/chroot.sh`** — drop the user-creation block that reads from `install.jsonc`. User creation moves to the Profile Runner.
- **`.os/lib/config.sh`** — drop the `users` field from validation. Keep all other validation intact.
- **`.os/03-install.sh`** — call the Profile Runner as a new step after `configure_system()`.
- **`.os/install.jsonc`** (template) — remove the `users` section. Leave `packages` (and its base groups) intact.

### Seed content

- **`.os/hosts/core/config.jsonc`** — base set of users and system programs shared across hosts.
- **`.os/users/core/config.jsonc`** — base set of programs and shell defaults shared across users.
- **At least one example host config** and **one example user config**, documented as templates.
- **Initial program directories** under `.os/programs/<category>/<name>/` for the programs currently invoked from the existing chroot/post-install path (so the new flow is functionally equivalent to today's flow on day one).

### Schemas

- **Host Config:** `{ users: string[], system_programs: string[] }`. The hostname is implicit from the directory name.
- **User Config:** `{ shell: string, sudo: bool, groups: string[], programs: string[] }`. Optional: `git: { name, email }`, `ssh_authorized_keys: string[]`.
- **Program Config:** `{ name: string, system: bool, description?: string }`. All other installation knowledge lives in the adjacent `install.sh`.

### Validation rules

- Every program referenced by a user config must have `system: false` in its program config — otherwise validation aborts.
- Every program referenced by a host config must have `system: true` — otherwise validation aborts.
- Every user referenced by a host config must have a corresponding user config directory — otherwise validation aborts.
- A missing host config matching the hostname is a warning, not an error (graceful degradation to install.jsonc-only behaviour).
- `core` is a reserved directory name in both `.os/hosts/` and `.os/users/`.

### Runtime contracts

- The Profile Runner exports `OS_DIR`, `PROGRAMS`, `SHELL_COMMONS` before calling each program's `install.sh`.
- System programs are installed with pacman; AUR is forbidden in system context.
- Paru is bootstrapped per user inside the chroot. `base-devel` is hardcoded into the pacstrap package list to support paru builds.
- All installation completes before pools are exported. No first-boot setup scripts are dropped into user homes.

## Testing Decisions

A good test here exercises external behaviour, not implementation: given a set of input config files, assert the merged output. Tests should not introspect internal helper functions or rely on file paths beyond what is declared in the test fixture.

- **Shellcheck across all scripts** in `.os/` (existing scripts and new ones). Run as a single check, not per-file. Catches the bulk of shell pitfalls (unquoted vars, subshell traps, missing `set -e` semantics) without writing test code.
- **Bats unit tests for `.os/lib/configs.sh`**, the config loader/merger. Cases to cover:
  - core + empty specific → core unchanged
  - empty core + specific → specific unchanged
  - core list + specific list → concatenated, deduped
  - core scalar + specific scalar → specific wins
  - missing field in one side → present field preserved
  - missing core file → error
  - missing specific file → graceful (host-config-not-found semantics)
- **No tests for** `profiles.sh`, `install.sh`, `shell-stdlib.sh` directly. These are integration-shaped (they run pacman, arch-chroot, etc.) and are better validated by an end-to-end VM install run, which is already documented in `.os/REFERENCE.md`.

Prior art: there are no existing automated tests in the repo. This PRD introduces both shellcheck and bats. The bats tests should live at `.os/tests/configs.bats` (or similar) — directory chosen during implementation.

## Out of Scope

- Modifying `.pkglist/`. It stays as reference material.
- Per-user password input or hashed-password support. Default password is `12345` for now.
- First-boot setup scripts. All installation happens during the live CD phase.
- Migrating every existing program from `.pkglist/programs/` into `.os/programs/`. Only the programs needed for the new flow on day one are migrated; the rest can be ported incrementally.
- Multi-host configs in a single repo checkout (the install runs for the host whose hostname is in `install.jsonc`).
- Generic merge logic for nested objects beyond the scalar/list distinction described above.
- Reworking the existing ZFS / disk / bootloader code in `.os/lib/`.

## Further Notes

- The four ADRs in `docs/adr/` (0001 split disk/software config, 0002 install.sh as source of truth, 0003 all-during-live-CD, 0004 core configs) capture the design rationale and should be referenced from implementation issues.
- The hostname in `install.jsonc` is the implicit foreign key to the host config — there is no second declaration of hostname in the host config file itself.
- This PRD is a structural foundation. Once it lands, additional follow-on PRDs can cover: porting the rest of `.pkglist/programs/` into `.os/programs/`, replacing the `12345` default with a proper password mechanism, and any first-boot ergonomics that turn out to be missing.

## Comments

### Triage — ready-for-human

> *This was generated by AI during triage.*

**Category:** enhancement
**State:** ready-for-human

**What's settled:**

- Design is fully specified through a `/grill-with-docs` session in this branch.
- CONTEXT.md captures the glossary (Host Config, User Config, Program Config, Host Core, User Core, Runner, Single Entry Point, Shell Stdlib, Program Install Script).
- Four ADRs cover the load-bearing decisions: 0001 split disk/software config, 0002 install.sh as source of truth, 0003 all-during-live-CD, 0004 core configs as base layer.
- Module breakdown agreed: `install.sh`, `configs.sh` (deep, testable), `profiles.sh`, `shell-stdlib.sh`. Modifications: `chroot.sh`, `config.sh`, `03-install.sh`, `install.jsonc` template.
- Tests scoped: shellcheck across all of `.os/`, bats unit tests for `configs.sh` only.

**Why ready-for-human, not ready-for-agent:**

- Next action is breaking this PRD into implementation issues (`/to-issues`). Slicing decisions affect what lands first and where risk concentrates — the install flow can brick a real machine if a faulty change reaches it untested.
- Each resulting implementation issue is a candidate for `ready-for-agent` once the slicing is settled.

**Suggested next step:** invoke `/to-issues` against this PRD when ready to start implementation.
