# Dotfiles Context

## Glossary

### Install Config (`install.jsonc`)
Declarative JSONC file at `.os/install.jsonc`. Covers live-CD-time concerns: disk layout, ZFS pool topology, partitioning, bootloader, locale, timezone, keymap, hostname, and base package groups (kernel, bootloader packages, extras). Does not define users.

### Host Config
Declarative JSONC file at `.os/hosts/<hostname>/config.jsonc`. Declares which users are created on the host and which system-level programs are installed. References users and programs by name. The hostname in `install.jsonc` implicitly links to the matching host config directory. Applied on top of Host Core.

### Host Core
Declarative JSONC file at `.os/hosts/core/config.jsonc`. Declares the base set of users and system programs shared across all hosts. Every host config is merged with core — core is applied first, then the host config adds on top.

### User Config
Declarative JSONC file at `.os/users/<username>/config.jsonc`. Declares a user's shell, sudo access, groups, and which user-level programs are installed. Optional fields: git identity, SSH authorized keys. `git` must be declared explicitly as a user program — it is not installed by default. Passwords are not stored in config — hardcoded as `12345` by default. A user config that references a program marked `system: true` is a validation error and aborts the install. Applied on top of User Core.

### User Core
Declarative JSONC file at `.os/users/core/config.jsonc`. Declares the base set of programs, shell defaults, and groups shared across all users. Every user config is merged with core — core is applied first, then the user config adds on top.

### Program Config
Declarative JSONC file at `.os/programs/<category>/<name>/config.jsonc`. Contains orchestration metadata only: display name, `system` flag, and optional description. The adjacent `install.sh` is the source of truth for installation logic.

### System Program
A program that requires root and is installed via pacman during the chroot phase. Declared in host config or host core. Marked `"system": true` in its program config. Only official repo packages (no AUR) should be system programs.

### User Program
A program installed for a specific user via paru inside the chroot. Declared in user config or user core. Marked `"system": false` in its program config. Paru is bootstrapped per user before any user programs are installed. `base-devel` is hardcoded into pacstrap and always available in the chroot.

### Runner
`.os/lib/profiles.sh`. Reads host core + host config (merged), validates program references (aborts if a user config references a system program), installs system programs via `arch-chroot`, then for each user merges user core + user config and installs programs via `arch-chroot /mnt su - <username>`. Called by `03-install.sh` after `configure_system()`.

### Single Entry Point
`.os/install.sh`. The one script a user runs from the Arch live CD after cloning the repo and providing configs. Orchestrates: ZFS bootstrap → disk wipe → partition → pacstrap → system config → system programs → user programs → cleanup and pool export.

### Shell Stdlib
`.os/lib/shell-stdlib.sh`. Shared utility library sourced by all program `install.sh` scripts inside `.os/programs/`. Mirrors the role of `.pkglist/shell-commons/shell-stdlib.sh`, which is reference-only and not modified.

### Program Install Script
`install.sh` inside each `.os/programs/<category>/<name>/`. Source of truth for all installation logic: package install, file copying, service enabling. Called by the runner with env vars `$OS_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` pre-exported. Programs are referenced by name only across all categories (names are unique).
