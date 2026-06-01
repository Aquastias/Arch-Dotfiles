# Dotfiles Context

## Glossary

### Install Config (`install.jsonc`)
Declarative JSONC file at `.os/install.jsonc`. Covers live-CD-time concerns: disk layout, ZFS pool topology, partitioning, bootloader, locale, timezone, keymap, `system.hostname` (machine identity), `host_profile` (which Host Profile to apply — defaults to `system.hostname` when omitted), and base package groups (kernel, bootloader packages, extras). Does not define users. Authored by hand or generated on the live CD by the Pre-Install Picker from an Install Template.

### Pre-Install Picker (`tools/pick.sh`)
Live-CD config builder that generates `.os/install.jsonc` from a fzf-driven wizard. Prompts the operator for two things only: which Host Profile to install (1-of-N from `.os/hosts/<name>/`) and which disk(s) to install onto. The picker writes the chosen profile name to `host_profile`, and writes `system.hostname` from the template's `system.hostname` when set, else falls back to the profile name. Hosts without an Install Template are silently omitted from the picker list. Every other field (bootloader, locale, timezone, keymap, kernel, ZFS pool/dataset names, `environment.desktop`, `environment.gpu`, `options.encryption`, `options.impermanence.*`, `options.age_key_url`) is loaded from the chosen template and copied through unchanged — never re-prompted, since those are properties of the machine, not of the install. Self-installs `fzf` and `jq` via `pacman -Sy` at start. Disk picker uses `/dev/disk/by-id/*` with a `lsblk`/`smartctl` preview pane and filters out the live medium; ZFS layout is mode-then-disks (pick `INSTALL_MODE` first — single / mirror / raidz — then multi-select disks against that mode). Always shows a final review screen (diff vs. any existing `install.jsonc`) and offers four actions — write-and-install, write-only, edit, abort. Write-and-install hands off to `install.sh` in the same shell after writing; write-only stops so the operator can review/commit `install.jsonc` before invoking the installer. The operator-visible single-key bindings are picker-internal and documented in `tools/pick.sh`. Validates the operator-driven layout via `picker_validate_layout` (mode-vs-disk-count) before assembly; no further config-shape validation runs at picker time, so a malformed template can still fail at install time. Not part of the install flow — parallel to `tools/save-pkglist.sh` and `tools/impermanence.sh`.

### Install Template
Declarative JSONC file at `.os/hosts/<profile>/install.template.jsonc`. Holds every per-host field consumed by the Pre-Install Picker: locale, timezone, keymap, kernel, ZFS pool/dataset names, `ashift`, `os_size`, `bootloader`, `environment.desktop`, `environment.gpu`, `options.encryption`, `options.impermanence.*`, optionally `options.age_key_url`, and optionally `system.hostname` (pins the machine hostname for this profile; when omitted, the picker falls back to the profile name). Merged with `.os/hosts/core/install.template.jsonc` following the same merge rules as Host Config / Host Core. Only consumed by the picker — `install.sh` reads `.os/install.jsonc`, not the template. Absent in repos that don't use the picker; absent templates also make the profile invisible to `pick.sh`.

### Host Profile
The bundle defined by `.os/hosts/<name>/` — Host Config, Install Template, and optional Host Secrets. The directory's basename is the profile name. Selected at install time via `host_profile` in `install.jsonc` (or by `pick.sh`). Independent of the machine's hostname: a profile may pin a hostname via its Install Template's `system.hostname`, or leave it open and let the profile name serve as the default hostname.

### Host Config
Declarative JSONC file at `.os/hosts/<profile>/config.jsonc`. Declares which users are created on the host and which system-level programs are installed. References users and programs by name. The `host_profile` in `install.jsonc` (defaulting to `system.hostname`) selects the matching directory under `.os/hosts/`. Applied on top of Host Core.

### Host Core
Declarative JSONC file at `.os/hosts/core/config.jsonc`. Declares the base set of users and system programs shared across all hosts. Every host config is merged with core — core is applied first, then the host config adds on top.

### User Config
Declarative JSONC file at `.os/users/<username>/config.jsonc`. Declares a user's shell, sudo access, groups, and which user-level programs are installed. Optional fields: git identity, SSH authorized keys. `git` must be declared explicitly as a user program — it is not installed by default. Passwords are not stored in config — hardcoded as `12345` by default. A user config that references a program marked `system: true` is a validation error and aborts the install. Applied on top of User Core.

### User Core
Declarative JSONC file at `.os/users/core/config.jsonc`. Declares the base set of programs, shell defaults, and groups shared across all users. Every user config is merged with core — core is applied first, then the user config adds on top.

### Program Config
Declarative JSONC file at `.os/programs/<category>/<name>/config.jsonc`. Contains orchestration metadata only: display name, `system` flag, and optional description. The adjacent `install.sh` is the source of truth for installation logic.

### System Program
A program that requires root and is installed via pacman during the chroot phase. Declared in host config or host core. Marked `"system": true` in its program config. Only official repo packages (no AUR) should be system programs. One documented exception to the "declared" rule: the sops Program is secrets-activated, not declared — the Runner selects it implicitly when install-state records secrets (see SOPS Runtime Service, ADR 0025).

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
`.os/lib/layout-<mode>.sh` (`layout-single.sh`, `layout-multi.sh`). Each implements the layout interface (`layout_validate`, `layout_plan`, `layout_partition`, `layout_create_pools`, `layout_mount_esp`) and publishes a normalized state record consumed by chroot/finalize: `LAYOUT_ESP_PARTS[]` (resolved ESP device paths, primary at index 0), `LAYOUT_OS_POOL_NAME`, `LAYOUT_DATA_POOL_NAME` (empty when no data pool). `layout_validate` is a pure check (no state writes) — called by `validate_install_context` to gate disk paths and mode-specific topology before any work begins; exits via `error` on first failure. The active module is selected by `INSTALL_MODE` and sourced from `03-install.sh` **before** `validate_install_context` runs, so the dispatcher can call `layout_validate` on the active adapter. The seam wrappers enforce phase ordering via `_layout_enter_phase` / `_layout_exit_phase` in `layout-common.sh` (phases: validate→plan→partition→pools→esp); a verb called out of order aborts via `error` before any destructive operation. Mode-private globals (`SINGLE_*`, `MULTI_*`, `OS_ESP_PARTS`, `STORAGE_PARTS`, `RESOLVED_TOPOLOGIES`) stay inside the module — consumers only read `LAYOUT_*`.

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
SOPS-encrypted JSON file at `.os/hosts/<profile>/secrets.json`. Contains `root_password` for the host. Parallel to Host Config; read by the Secrets Module at install time and consumed by root password provisioning. Optional — if absent, root password falls back to interactive prompt.

### Secrets Module
`lib/secrets.sh`. Runs immediately after config load in `03-install.sh`. Locates the passphrase-encrypted Operator Age Key via two sources in priority order: (1) a removable USB device scanned for `/age/key.age`; (2) an HTTPS download from `options.age_key_url` in `install.jsonc` (live-CD fallback when no USB is present). Prompts for the passphrase, decrypts all User Secrets and Host Secrets to a tmpfs, and writes the tmpfs paths into `install-state.json` for consumption by chroot scripts. Clears the tmpfs after the chroot phase completes.

### Machine Age Key
Age private key stored at `/etc/secrets/age/keys.txt` on the installed system. Derived at install time from the machine's `ssh_host_ed25519_key` via `ssh-to-age`. Used exclusively by the SOPS Runtime Service for boot-time decryption. Must be added as a recipient in `.sops.yaml` and secrets re-encrypted via `sops updatekeys` after first install.

### SOPS Runtime Service
Systemd service installed by `.os/programs/security/sops/install.sh`. Runs early in boot (before user services), mounts a tmpfs at `/run/secrets/`, decrypts all SOPS-encrypted secret files using the Machine Age Key, and sets declared ownership and permissions. Programs that need runtime secrets reference `/run/secrets/<name>` paths. The sops Program is secrets-activated: the Runner installs it (deriving the Machine Age Key and building `ssh-to-age` via `go`) only when the host or one of its declared users ships a `secrets.json` — consistent with secrets being optional. It is therefore not a member of any host's declared System Programs, including Host Core; a host with no secrets gets neither the service nor `go`.

### Host Package List
`packages` object in a Host Config with two fields: `repo` (official-repo packages installed via pacstrap) and `aur` (AUR packages installed via paru for the primary user). `repo` is a 2-level categorized object — kebab-case category keys mapped to string arrays — flattened to a sorted-unique list by the Categorized List Parser at install time. Categories are cosmetic; renaming `media` to `multimedia` does not change what installs. Shape, leaf-type, or category-name violations abort at config-load with the offending path. `aur` is still a flat string array (categorized shape arrives in a later slice). Declared in the host-specific config — not in Host Core — because the list differs per machine. Deduplicated against base packages by the installer. AUR packages are installed once for the system via the first declared user's paru instance before any user programs run.

### Sysctl Defaults
`sysctl` object in Host Core (or a host-specific config), containing key-value pairs written verbatim to `/etc/sysctl.d/99-os.conf` during the profiles phase. Applied to every host via Host Core. A host-specific config can add keys (they deep-merge per the core merge rules) but cannot remove keys declared in core.

### Tools
`.os/tools/`. Utility scripts for managing a running system or preparing an install — not part of the install flow itself. Currently: `pick.sh` (see Pre-Install Picker; live-CD config builder), `save-pkglist.sh` (writes current packages to `hosts/<hostname>/pkglist-repo.txt` and `pkglist-aur.txt`), `install-pkglist.sh` (installs packages from those files), `impermanence.sh` (see Impermanence Tool), and `fetch-iso.sh` (downloads + sha256-verifies the archzfs-Compatible ISO for USB prep). The pkglist tools default to `$(hostname)` but accept a hostname argument.

### archzfs-Compatible ISO
Newest archived Arch ISO (from `archive.archlinux.org`) whose kernel major.minor matches a kernel `archzfs` ships a prebuilt `zfs-linux` for. The prebuilt-kernel list is used as a proxy for "the current ZFS source is known to compile against this kernel" — even though the installer always builds ZFS via DKMS, not the prebuilt. Resolved by `iso_resolver_get_zfs_compatible` in `lib/iso-resolver.sh`. The installer cannot use the latest Arch ISO when its kernel is newer than `archzfs` tracks: DKMS then fails to build the ZFS module against that kernel.

### Kernel Selection
`options.kernel` in the Install Config: one or more kernel flavour tokens naming which kernels the installed system gets. Accepts a single token (string) or a list. Tokens map to a kernel package plus its matching headers: `lts`→`linux-lts`, `default`→`linux`, `zen`→`linux-zen`, `hardened`→`linux-hardened`. Every selected kernel is installed, and `zfs-dkms` builds the ZFS module against each. `lts` is the only token `archzfs` is guaranteed to track; any other (notably `default`, the rolling kernel) may temporarily outrun `archzfs` and is caught by the ZFS Module Guard. Defaults to `lts`.

### Primary Kernel
The first token in the Kernel Selection. Drives the bootloader default boot entry and the initramfs preset/fallback logic — exposed to chroot modules as the scalar `KERNEL` (the full list is `KERNELS`). When more than one kernel is selected, the others are still installed and `mkinitcpio -P` builds their presets, but the bootloader default and the custom fallback-preset injection track only the Primary Kernel until full multi-kernel preset wiring lands.

### ZFS Module Guard
Post-pacstrap check, host-side, run before chroot configuration begins. Verifies a loadable `zfs` module exists for every kernel installed into the target, aborting the install with archzfs-support guidance if any kernel lacks one. Turns the otherwise opaque mid-`mkinitcpio` "module not found" failure into an early, explicit error naming the unsupported kernel. Necessary because Kernel Selection may include kernels newer than `archzfs` tracks (see archzfs-Compatible ISO).

### Impermanence
Optional install-time feature that resets selected system directories to a clean state on every boot via ZFS dataset rollback. Enabled by `options.impermanence` in Install Config. When enabled, the installer creates a Persist Dataset, splits a set of Rollback Datasets out of the OS pool, takes a Blank Snapshot of each, and installs a Rollback Hook in initramfs. Inspired by NixOS impermanence; deliberately narrower in scope — Arch lacks a `/nix/store`-equivalent, so rolling back all of `/` would erase every pacman update, hence Impermanence targets `/etc`, `/root`, `/opt`, `/srv`, `/usr/local` only.

### Persist Dataset
ZFS dataset (default `rpool/persist`, mounted at `/persist`) that holds all state surviving across reboots when Impermanence is enabled. Name and mountpoint configurable via `options.impermanence.dataset` and `options.impermanence.mount` in Install Config. Must live on the same pool as `rpool/ROOT/arch` so the early-boot bind-mounts complete before `local-fs.target`. Holds the Persist Payload (operator-editable `.mount` units + tmpfiles snippets) plus the actual data of every persisted path.

### Rollback Datasets
The set of ZFS datasets reverted to their Blank Snapshot on every boot when Impermanence is enabled: `rpool/ROOT/etc` (`/etc`), `rpool/ROOT/root` (`/root`), `rpool/ROOT/opt` (`/opt`), `rpool/ROOT/srv` (`/srv`), `rpool/ROOT/usrlocal` (`/usr/local`). Deliberately excludes `rpool/ROOT/arch` (so pacman writes to `/usr` survive reboots without re-snapshot), `rpool/home`, `rpool/var`, `rpool/var/log`, `rpool/var/cache`, `rpool/tmp` (already separate datasets, naturally persistent except `/tmp` which is intended ephemeral). Created by the installer when Impermanence is enabled; absent otherwise.

### Blank Snapshot
ZFS snapshot named `@blank` on each Rollback Dataset, taken at the end of the chroot phase after Curated Persist Defaults have been moved off the dataset onto the Persist Dataset. The Rollback Hook reverts each Rollback Dataset to its Blank Snapshot at every boot. Re-created by the Pacman Resnapshot Hook after every successful pacman transaction so that pacman's writes to `/etc/<pkg>/` etc. survive across reboots. If `@blank` is missing on any Rollback Dataset, the Rollback Hook drops to emergency shell — fail-closed.

### Rollback Hook
mkinitcpio hook pair installed under `/etc/initcpio/hooks/` and `/etc/initcpio/install/` and added to `HOOKS=` in `mkinitcpio.conf` between the `zfs` and `filesystems` hooks. Runs in initramfs after the ZFS module loads and pool is imported (and decrypted, if `options.encryption=true`), and before `zfs-mount-generator` mounts the Rollback Datasets. Hardcoded at install time with the list of Rollback Datasets to revert. Fails closed if any Blank Snapshot is missing — drops to emergency shell rather than continuing with stale state.

### Bootstrap Mount
Pair of files baked into `/usr/lib` at install time that bridge the Persist Dataset into systemd's standard discovery paths. `/usr/lib/tmpfiles.d/impermanence-bootstrap.conf` creates `/etc/systemd/system/` and `/etc/tmpfiles.d/` as empty directories at early boot. `/usr/lib/systemd/system/persist-etc-systemd-system.mount` and `persist-etc-tmpfiles-d.mount` bind `/persist/etc/systemd/system` and `/persist/etc/tmpfiles.d` over those placeholders. Lives on `rpool/ROOT/arch` (non-rolled-back) so it persists across reboots without snapshot manipulation.

### Persist Mount
`.mount` unit named `persist-<slug>.mount`, one per persisted path. Each unit bind-mounts `/persist/<path>` over `<path>` early in boot. Ordered `After=systemd-tmpfiles-setup.service` and `Before=local-fs.target` with `RequiredBy=local-fs.target` so a failed bind cascades to emergency. Curated Persist Defaults ship as units under `/usr/lib/systemd/system/` (vendor-owned, snapshot-immune); host-declared Persist Extensions ship as units under `/persist/etc/systemd/system/` (operator-editable). Live data is staged onto the Persist Dataset before the unit activates — moved at install time (the live path will be reset on next boot), copied at runtime (the bind mount activates immediately and covers the original).

### Curated Persist Defaults
Fixed list of system-identity paths the installer always persists when Impermanence is enabled. Files: `/etc/machine-id`, `/etc/hostname`, `/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/adjtime`, `/etc/fstab`. Directories: `/etc/ssh`, `/etc/secrets`, `/etc/NetworkManager/system-connections`, `/etc/sudoers.d`, `/etc/pacman.d`, `/root`. Loss of any of these breaks first reboot — host keys, Machine Age Key, hostname, network connections, fstab. Shipped as Persist Mount units under `/usr/lib/systemd/system/` so they're stable across operator edits.

### Persist Extensions
`persist` object in a Host Config or Host Core with two arrays: `directories` and `files`. Each entry is an absolute path. Deep-merged across Host Core and the specific Host Config per the standard merge rules. Translated by the installer into Persist Mount units under `/persist/etc/systemd/system/` and tmpfiles entries placed under `/persist/etc/tmpfiles.d/`. Only meaningful when `options.impermanence.enabled=true`. Validation warns on paths already covered by an always-persistent dataset (`/home`, `/var`, `/var/log`, `/var/cache`, `/tmp`) or by a Curated Persist Default.

### Pacman Resnapshot Hook
Pacman post-transaction hook at `/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook` (or shipped under `/usr/share/libalpm/hooks/`) that destroys and re-takes the Blank Snapshot on every Rollback Dataset after a successful pacman transaction. Necessary because pacman writes config defaults under `/etc/<pkg>/` etc.; without this hook those writes would vanish on next reboot. Known v1 limitation: user edits to non-persisted paths under a Rollback Dataset made *before* a pacman transaction get baked into the new Blank Snapshot and survive one additional reboot. A future opt-in pre-transaction drift check (`zfs diff` fails loudly if dirty) closes this leak.

### Impermanence Tool
`.os/tools/impermanence.sh`. Runtime utility for managing Persist Extensions on a system where Impermanence is enabled. Verbs: `add <path>` (writes the path into the host's `persist.directories` or `persist.files` in `hosts/<hostname>/config.jsonc`, copies current data onto the Persist Dataset, generates the Persist Mount, daemon-reloads); `remove <path>` (reverses); `status` (lists active Persist Mounts and runs `zfs diff` against `@blank` for each Rollback Dataset); `apply-defaults` (regenerates Curated Persist Defaults' unit files under `/usr/lib/systemd/system/` from the installer's current curated list, used after pulling an updated dotfiles repo). Does not edit Curated Persist Defaults directly — those are vendor-shipped.

### Stow Tree
Top-level dotfile dirs in the repo (`.config/`, `.zsh/`, `.claude/`, plus loose home-relative files like `.zshrc`, `.p10k.zsh`) that GNU stow symlinks into each user's `$HOME` via `stow --no-folding */` during the Runner's dotfiles step. Layout groups files by destination path, not by program. Legacy as of ADR 0012 — being migrated program-by-program into Program Config Trees, but remains supported indefinitely. Path collisions with the Generated Stow Tree abort the Config Generator.

### Program Config Tree
Per-program user-side config files under `.os/programs/<category>/<name>/configs/`. The unsuffixed `configs/` is the default; sibling `configs@<variant>/` directories hold alternates (Config Variants). Optional — programs without user-side config omit the dir entirely. Manifest scope is user paths only; system paths stay in the program's `install.sh`. Authoring location only — never directly symlinked or copied; the Config Generator materializes the Generated Stow Tree from these.

### Config Variant
An alternate version of a program's Program Config Tree, named by the suffix on `configs@<variant>/`. Variant names match `[a-z0-9-]+`; `default` is reserved and refers to the unsuffixed `configs/`. Selected per-user via a `variants` object in User Config (with House Defaults inheritable from User Core, overridden per-key by User Config). Unselected variants fall back to `configs/`; programs with only `configs@*/` and no `configs/` require an explicit selection or the generator aborts.

### Config Manifest
`manifest.jsonc` inside each `configs[@variant]/` directory. Declares file placement only — `files` is an array of `{ src, dst, mode? }` entries. `src` is relative to the manifest's directory; `dst` is a `~/`-rooted user path. No templating, no conditionals, no hooks, no system paths, no encrypted entries. Constraints exist so that complexity is forced into the Config Variant axis instead of into per-file metadata.

### Generated Stow Tree
Per-user materialized tree at `~/.dotfiles/.stow/<user>/` produced by the Config Generator on the target machine. Mirrors destination paths (`.config/<...>`, `.local/<...>`, home-relative files at root). Gitignored — never committed, always regenerable from the repo + User Config + Config Variants. Consumed by `stow -d ~/.dotfiles/.stow/<user> --no-folding .`, which runs after the legacy Stow Tree pass.

### Config Generator
`.os/tools/generate-configs.sh`. Reads the merged User Core + User Config for a target user and the merged Host Core + Host Config for the machine (hostname looked up at runtime). Resolves each program's Config Variant via the Variant Resolver, validates all relevant Config Manifests, builds a per-user plan via the Plan Builder, and materializes the Generated Stow Tree. Invoked by the Runner inside `arch-chroot` per user between the dotfiles clone and the stow invocation. Also runnable standalone after install (`--user <name>`) to re-render after variant edits. Flags `--validate-only` and `--dry-run` are supported. Aborts if a planned destination is already owned by the legacy Stow Tree.

### Plan Builder
Pure function inside the Config Generator. Inputs: the resolved Config Variant map, the per-user `~/.dotfiles/.stow/<user>/` stow root, and the declared program set (User Programs from User Core + User Config, unioned with System Programs from Host Core + Host Config). Output: a deterministically-ordered flat list of `{ src_abs, dst_in_stow_tree, mode? }` entries. No writes. Programs with a Program Config Tree on disk but not in the declared set are silently omitted — mid-migration is a normal state.

### House Defaults
Variants declared in User Core's `variants` object, applied to every user unless overridden per-key in their own User Config. Same merge semantics as the rest of the User Core / User Config relationship — core first, user adds on top, individual keys can be replaced without replacing the whole object.
