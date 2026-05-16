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
`.os/lib/shell-stdlib.sh`. Shared utility library. Sourced once per program by the Program Runner (not by the install.sh itself), so program scripts get its helpers without their own source line.

### Program Install Script
`install.sh` inside each `.os/programs/<category>/<name>/`. Source of truth for all installation logic: package install, file copying, service enabling. Invoked by the Program Runner via `lib/run-program.sh`, which validates staging, sources Shell Stdlib, then sources the install.sh in the same shell. Receives env vars `$OS_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` pre-exported. Programs are referenced by name only across all categories (names are unique).

### Layout Module
`.os/lib/layout-<mode>.sh` (`layout-single.sh`, `layout-multi.sh`). Each implements the layout interface (`layout_plan`, `layout_partition`, `layout_create_pools`, `layout_mount_esp`) and publishes a normalized state record consumed by chroot/finalize: `LAYOUT_ESP_PARTS[]` (resolved ESP device paths, primary at index 0), `LAYOUT_OS_POOL_NAME`, `LAYOUT_DATA_POOL_NAME` (empty when no data pool). The active module is selected by `INSTALL_MODE` and sourced from `03-install.sh`. Mode-private globals (`SINGLE_*`, `MULTI_*`, `OS_ESP_PARTS`, `STORAGE_PARTS`, `RESOLVED_TOPOLOGIES`) stay inside the module — consumers only read `LAYOUT_*`.

### Program Runner
`.os/lib/run-program.sh`. Wrapper invoked by the Runner inside arch-chroot for every Program Install Script. Verifies the chroot-side staged tree (Shell Stdlib readable, install.sh readable) and exits 99 with a clear message on mismatch. Sources Shell Stdlib once and sources the install.sh in the same shell, so install.sh files inherit `set -Eeuo pipefail` and the stdlib helpers without a per-script source line.

### Chroot Configuration Module
`.os/lib/chroot/`. Set of shell scripts copied into `/mnt/root/lib-chroot/` before `arch-chroot` and orchestrated by `configure.sh` inside the chroot. Each sub-script owns one concern: identity (locale/timezone/keymap/hostname), pacman config, initcpio (ZFS hook + mkinitcpio), root password, an extras runner (KDE/backup/security), plus a Bootloader Adapter. `lib/chroot.sh` shrinks to live-ISO concerns: write_fstab, write_esp_mirror_hook, collect_passwords, and the single `arch-chroot` invocation that stages and runs `configure.sh`.

### Bootloader Module
The seam selecting between Bootloader Adapters. The active adapter is chosen by `options.bootloader` in the Install Config (`systemd-boot` or `grub`). The chroot orchestrator invokes `bash /root/lib-chroot/bootloader-${BOOTLOADER}.sh`. Adding a new bootloader means dropping in a new Bootloader Adapter — no `if/elif` branches grow.

### Bootloader Adapter
`.os/lib/chroot/bootloader-<name>.sh`. Concrete bootloader implementation: package install, config file generation, kernel-image entry registration. Two adapters today: `bootloader-systemd.sh` and `bootloader-grub.sh`. Each adapter reads the same env vars from the orchestrator (`KERNEL`, `ROOT_DATASET`, ESP info, etc.) and is interchangeable from the orchestrator's view.

### Environment Config
The `"environment"` key in `install.jsonc`. Declares desktop environment selection and GPU driver selection. Audio is not declared — it is auto-derived (PipeWire when any desktop is selected, omitted for server installs). Processed at config-load time; populates `packages.groups.gpu` and `packages.groups.audio` before pacstrap. Valid desktop values: `"kde"`, `"hyprland"`, or `["kde", "hyprland"]`. Valid GPU values: `"amd"`, `"nvidia"`, `"intel"`, `["amd", "nvidia"]`, or `"auto"`. Replaces `post_install.desktop` from the previous schema.

### Desktop Environment Adapter
Script at `extras/desktop/<name>/<name>.sh` with a companion `install-<name>.jsonc` for per-component toggles. Invoked dynamically by the Environment Runner based on `environment.desktop`. Each adapter installs its packages, writes its display manager config, and enables its services. Adding a new DE requires only a new `extras/desktop/<name>/` directory — no runner code changes.

### Environment Runner
The extras dispatcher in `lib/chroot/extras.sh`. Iterates the resolved `environment.desktop` array and invokes each Desktop Environment Adapter by directory convention (`extras/desktop/<de>/<de>.sh`). No DE names are hardcoded in the runner — dispatch is purely by convention. Also runs `post_install.backup` and `post_install.security` extras.

### GPU Resolution
Translation of `environment.gpu` into driver packages at config-load time. `"auto"` uses `lspci` on the live ISO to detect all GPU vendors and resolves to a string or array. Hybrid configs (e.g., `["amd", "nvidia"]`) install per-vendor drivers plus `envycontrol`. Resolved packages populate `packages.groups.gpu` before pacstrap.

Vendor → package mapping:
- `"amd"` → `vulkan-radeon xf86-video-amdgpu mesa libva-mesa-driver`
- `"nvidia"` → `nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver egl-wayland` (open kernel module only; requires Turing+/RTX 20xx+; DKMS used so it builds against both `linux` and `linux-lts`)
- `"intel"` → `intel-media-driver` (Broadwell/5th-gen+) or `libva-intel-driver` (pre-Broadwell), auto-selected by parsing `lspci` device ID
- VM GPU (VMware/VirtualBox/virtio-gpu) → `mesa` only (software rendering); detection logs a notice and continues without aborting

### Display Manager
Auto-selected by each Desktop Environment Adapter based on the full resolved desktop array — not a config key. KDE-only or KDE+Hyprland → SDDM (enabled by the KDE adapter). Hyprland-only → greetd + greetd-tuigreet (enabled by the Hyprland adapter, config written to `/etc/greetd/config.toml`).

### User Secrets
SOPS-encrypted JSON file at `.os/users/<username>/secrets.json`. Contains sensitive per-user data: `password`, `ssh_identity_private_key`, and `ssh_identity_key_type` (`ed25519` | `rsa` | `ecdsa`; defaults to `ed25519`). Values are encrypted (keys remain plaintext). Optional — if absent, user password defaults to `12345` and no SSH identity is deployed. Parallel to User Config; read by the Secrets Module at install time and consumed by user creation and SSH provisioning. Not merged with User Core — secrets are always user-specific.

### Host Secrets
SOPS-encrypted JSON file at `.os/hosts/<hostname>/secrets.json`. Contains `root_password` for the host. Parallel to Host Config; read by the Secrets Module at install time and consumed by root password provisioning. Optional — if absent, root password falls back to interactive prompt.

### Secrets Module
`lib/secrets.sh`. Runs immediately after config load in `03-install.sh`. Locates the passphrase-encrypted Operator Age Key via two sources in priority order: (1) a removable USB device scanned for `/age/key.age`; (2) an HTTPS download from `options.age_key_url` in `install.jsonc` (live-CD fallback when no USB is present). Prompts for the passphrase, decrypts all User Secrets and Host Secrets to a tmpfs, and writes the tmpfs paths into `install-state.json` for consumption by chroot scripts. Clears the tmpfs after the chroot phase completes.

### Machine Age Key
Age private key stored at `/etc/secrets/age/keys.txt` on the installed system. Derived at install time from the machine's `ssh_host_ed25519_key` via `ssh-to-age`. Used exclusively by the SOPS Runtime Service for boot-time decryption. Must be added as a recipient in `.sops.yaml` and secrets re-encrypted via `sops updatekeys` after first install.

### SOPS Runtime Service
Systemd service installed by `.os/programs/security/sops/install.sh`. Runs early in boot (before user services), mounts a tmpfs at `/run/secrets/`, decrypts all SOPS-encrypted secret files using the Machine Age Key, and sets declared ownership and permissions. Programs that need runtime secrets reference `/run/secrets/<name>` paths.

### Host Package List
`packages` object in a Host Config with two arrays: `repo` (official-repo packages installed via pacstrap) and `aur` (AUR packages installed via paru for the primary user). Declared in the host-specific config — not in Host Core — because the list differs per machine. Deduplicated against base packages by the installer. AUR packages are installed once for the system via the first declared user's paru instance before any user programs run.

### Sysctl Defaults
`sysctl` object in Host Core (or a host-specific config), containing key-value pairs written verbatim to `/etc/sysctl.d/99-os.conf` during the profiles phase. Applied to every host via Host Core. A host-specific config can add keys (they deep-merge per the core merge rules) but cannot remove keys declared in core.

### Tools
`.os/tools/`. Utility scripts for managing a running system — not part of the install flow. Currently: `save-pkglist.sh` (writes current packages to `hosts/<hostname>/pkglist-repo.txt` and `pkglist-aur.txt`) and `install-pkglist.sh` (installs packages from those files). Both default to `$(hostname)` but accept a hostname argument.
