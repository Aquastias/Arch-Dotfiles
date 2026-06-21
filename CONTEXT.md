# Dotfiles Context

## Glossary

### Host Profile (`profile.jsonc`)
The single, self-contained file describing one machine —
`.os/hosts/<name>/profile.jsonc`, merged under `.os/hosts/core/profile.jsonc`
(Host Core). Its directory basename is the profile name, the identity passed as
`install.sh --profile <name>`; there is no `host_profile` field. Collapses the
previous schema's three files (`install.jsonc` + `install.template.jsonc` + host
`config.jsonc`) into one (ADR 0036), so "the profile" is finally the whole
machine. Declares everything about the machine **except its disks**: `system`
(hostname, locale, timezone, keymap — `locale`/`keymap` accept a string or an
array whose element 0 is the default), `options` (kernel, bootloader,
encryption, swap, `ssh.enabled`, `impermanence.*`, optional `age_key_url`),
`environment` (desktop, gpu), `users` (names; `users[0]` is the Primary User),
`system_programs`, `packages` (`repo` + `aur`, both Categorized Lists), and the
full pool skeleton — `mode` plus `os_pool` / `storage_groups[]` / `data_pools[]`
carrying names, topology, mount, ashift, and `disk_count`, but **no device
paths**. Disks are machine-physical and operator-picked at install time; the
Pre-Install Picker maps them onto the declared groups to build the Effective
Config. Validated against a closed schema at load — any unknown key at any depth
aborts with its path (ADR 0036, amending ADR 0015). Independent of the machine's
hostname (ADR 0020): a profile may pin one via `system.hostname`, or let the
profile name serve as the default. Optionally ships Host Secrets alongside.

### Effective Config
The ephemeral, fully-resolved install config the installer back-end consumes —
never a committed file. `assemble_profile_config` builds it from a Host Profile
(merged with Host Core) plus the operator's disk assignment, adding the device
paths the profile deliberately omits. Written to tmpfs by `install.sh
--profile`, or injected by the VM seed on the unattended `install.sh
<config-file>` path. Carries exactly the shape `03-install.sh` read from the
retired `install.jsonc`, so the back-end never changed. The committed audit
artifact is the Host Profile (disks excluded); this assembled artifact is
transient by design (ADR 0036).

### Pre-Install Picker
The interactive disk-resolution front-end of `install.sh --profile <name>`
(`lib/picker.sh`) — no longer a separate `tools/pick.sh`. Because the Host
Profile already carries every machine property, the picker prompts only for what
it cannot: which disk(s) to install onto. It validates the named profile against
the closed schema, enumerates `/dev/disk/by-id/*` candidates with a
`lsblk`/`smartctl` fzf preview pane, and filters out the live medium via the
shared multi-signal Live-Medium Detector (`lib/live-medium.sh`, same one the
Disk Wipe uses — boot-mount parent disk, `iso9660`/`ARCH_*` label, not
string-matching). Single mode resolves one device; multi slices the picked set
across the profile's declared `os_pool` / `storage_groups[]` / `data_pools[]`
groups by each group's `disk_count`, in declared order, rendering the per-group
mapping to stderr so a multi assignment is never implicit (ADR 0037). The
assignment is validated against the min-disk table (mirror/stripe ≥2, raidz1 ≥3,
raidz2 ≥4, none ≥2) and assembled into the Effective Config in tmpfs — `mode`
and topology come from the profile, never re-prompted. `install.sh
<config-file>` is the parallel unattended seam (the VM seed's path): it consumes
a pre-assembled Effective Config directly and skips the picker.

### Guided Installer
The interactive, menu-driven front-end of the Single Entry Point that builds an
Effective Config through a TUI instead of from a committed Host Profile — the
on-ramp for ad-hoc installs (archinstall's role). Merges operator choices over
Host Core (so the shared base — `cups`, swappiness, base users — still applies)
and covers the full host schema. Unlike the Pre-Install Picker, which only
resolves disks against an already-authored profile, the Guided Installer also
authors the pool skeleton and every other machine property interactively.
Navigation is non-destructive: a single in-session **Config State** holds only
the operator's overrides over the computed defaults, so every screen is
re-entrant, edits commit on confirm (never on `Esc`), changes survive moving
between sections, and validation is deferred to the terminal actions. fzf is the uniform selection/navigation surface, now a **two-level** menu: a top
list of **Configuration Categories** (Host, Disks, Options, Environment,
Packages, Security, Backup, Users), each opening a submenu of its fields, so a
section name never repeats per row. Every value list is an fzf list, and
multi-select re-entry pre-marks prior picks; only free-text fields with nothing
to enumerate (hostname, package names, sizes, URLs, `sysctl` pairs, persist
paths) drop to a typed prompt. Terminal actions (Proceed / Save / Export) are
selectable rows under a divider; the edit-history toolbar (Undo / Redo / Reset
field|section|all) is bound to footer keybindings, not rows. Computed defaults
seed an untouched run: hostname `eterniox`, `users[0]` = `aquastias` (Primary
User), single-disk ZFS layout, locale `en_US.UTF-8` / timezone
`Europe/Bucharest` / keymap `us`. A typed `packages.extra` entry that
resolves to a `programs/<category>/<name>/` is promoted to a System Program
(installed via the Program Runner — pacman + config + services) rather than
pacstrapped raw; non-matching names stay plain repo packages, and on an
ambiguous name the program wins. Mistakes
are recoverable three ways — re-edit, **Reset** (field / section / all, the last
itself undoable), and **Undo/Redo** over a snapshot stack. Ends in one of three
terminal actions: **Proceed** (assemble the Effective Config in
tmpfs from the choices plus the picked disks, then install now), **Save Profile**
(write `hosts/<name>/profile.jsonc` — the committed, device-less audit artifact,
replayed via `--profile`), or **Export Effective Config** (write the
device-baked artifact to an operator-chosen path *outside* the repo's `hosts/`
tree, replayed via `install.sh <config-file>`). The committed save strips disks;
only the export carries them — preserving 0036's invariant that device paths are
never committed as repo source of truth. The third front-end over the one
back-end.

### Host Core
Declarative JSONC file at `.os/hosts/core/profile.jsonc`. Declares the base set
of users, system programs, and Sysctl Defaults shared across all hosts (never a
package list — ADR 0007). Every Host Profile is merged with core — core is
applied first, then the host profile adds on top.

### User Profile
Declarative JSONC file at `.os/users/<username>/profile.jsonc` (renamed from
`config.jsonc` in step with the host side — profile = a host/user, config = a
program spec; ADR 0036). Declares a user's shell, sudo access, groups, which
user-level programs are installed, and an optional `user_services` list enabled
via `systemctl --user enable` after the user's programs and dotfiles are placed
(a unit missing at enable time aborts with an actionable message). Optional
fields: git identity, SSH authorized keys. `git` must be declared explicitly as
a user program — it is not installed by default. Passwords are not stored in the
profile — hardcoded as `12345` by default unless User Secrets override. User ↔
system-program references (refining the old always-abort rule, ADR 0036): a
user-level program may shadow a host program; referencing a System Program the
host already installs is a no-op; referencing one no host installs aborts with
an actionable message — the `system` flag stays host-owned (ADR 0002). Applied
on top of User Core.

### User Core
Declarative JSONC file at `.os/users/core/profile.jsonc`. Declares the base set
of programs, shell defaults, groups, and House Defaults shared across all users.
Every User Profile is merged with core — core is applied first, then the user
profile adds on top.

### Primary User
The first entry in a host's `users` array (`users[0]` in
`.os/hosts/<profile>/profile.jsonc`, merged with Host Core) — the same user the
Runner uses for the shared AUR/paru pass (`profiles.sh` gates host + GPU AUR
installs on `users[0]`). Purely positional: there is no `primary: true` flag, so
ordering the `users` array chooses it. A host that declares no users has no
Primary User. The conventional default owner for host-wide, user-facing
resources: it is the AUR/paru user, and the default owner of a data pool whose
`owners` field is omitted (see Pool Owners). Exactly one per host; distinct from
root.

### Program Config
Declarative JSONC file at `.os/programs/<category>/<name>/config.jsonc`.
Contains orchestration metadata only: display name, `system` flag, and optional
description. The adjacent `install.sh` is the source of truth for installation
logic.

### System Program
A program that requires root and is installed via pacman during the chroot
phase. Declared in a Host Profile or Host Core. Marked `"system": true` in its
program config. Only official repo packages (no AUR) should be system programs.
One documented exception to the "declared" rule: the sops Program is
secrets-activated, not declared — the Runner selects it implicitly when
install-state records secrets (see SOPS Runtime Service, ADR 0025).

### User Program
A program installed for a specific user via paru inside the chroot. Declared in
a User Profile or User Core. Marked `"system": false` in its program config.
Paru is bootstrapped per user before any user programs are installed.
`base-devel` is hardcoded into pacstrap and always available in the chroot.

### Runner
`.os/lib/profiles.sh`. Reads host core + host profile (merged), validates
program references (a user referencing a System Program no host installs aborts;
one the host already installs is a no-op — ADR 0036), installs system programs
via `arch-chroot`, then for each user merges user core + user profile and
installs programs via `arch-chroot /mnt su - <username>`. Called by
`03-install.sh` after `configure_system()`.

### Single Entry Point
`.os/install.sh`. The one script a user runs from the Arch live CD after cloning
the repo. Three front-ends over one back-end (ADR 0036): `install.sh --profile
<name>` (interactive — the Pre-Install Picker resolves disks and assembles the
Effective Config in tmpfs; the user-facing path), `install.sh <config-file>`
(the unattended seam consuming a pre-assembled Effective Config; the VM seed's
path), and the **Guided Installer** (a from-scratch menu that builds an
Effective Config interactively when no profile exists yet). Orchestrates: ZFS bootstrap → disk wipe → partition → pacstrap → system
config → system programs → user programs → cleanup and pool export.

### Disk Wipe
`.os/02-wipe.sh`, the install flow's **make-blank** step — not a secure-erase.
It clears partition tables, filesystem signatures, and ZFS/LVM/MD labels so a
target disk looks pristine to the partitioner. Method is device-aware:
`blkdiscard` on SSD/NVMe (instant), a single zero-pass on HDDs (the slow case,
shown as a per-disk progress bar; disks wiped in parallel). Multi-pass/forensic
erase (`shred`, ATA secure-erase) is deliberately out of scope. Two safety
invariants hold: the **live medium is never listed, selectable, or wipeable**
(detected by multiple signals — boot-mount parent disk, `iso9660`/`ARCH_*` label
— not string-matching), and an **install-driven wipe touches only the install's
target disks** (`os_pool` + `storage_groups` + `data_pools` disks resolved from
the Effective Config and passed in explicitly), never an unrelated disk that
holds data. Run standalone it wipes only an explicitly selected target set,
defaulting to nothing.

### Shell Stdlib
`.os/lib/shell-stdlib.sh`. Shared utility library. Sourced once per program by
the Program Runner (not by the install.sh itself), so program scripts get its
helpers without their own source line.

### Program Install Script
`install.sh` inside each `.os/programs/<category>/<name>/`. Source of truth for
all installation logic: package install, file copying, service enabling. Invoked
by the Program Runner via `lib/run-program.sh`, which validates staging, sources
Shell Stdlib, then sources the install.sh in the same shell. Receives env vars
`$OS_DIR`, `$PROGRAMS`, `$SHELL_COMMONS` pre-exported. Programs are referenced
by name only across all categories (names are unique).

### Layout Module
`.os/lib/layout-<mode>.sh` (`layout-single.sh`, `layout-multi.sh`). Each
implements the layout interface (`layout_validate`, `layout_plan`,
`layout_partition`, `layout_create_pools`, `layout_mount_esp`) and publishes a
normalized state record consumed by chroot/finalize: `LAYOUT_ESP_PARTS[]`
(resolved ESP device paths, primary at index 0), `LAYOUT_OS_POOL_NAME`,
`LAYOUT_DATA_POOL_NAME` (empty when no data pool). `layout_validate` is a pure
check (no state writes) — called by `validate_install_context` to gate disk
paths and mode-specific topology before any work begins; exits via `error` on
first failure. The active module is selected by `INSTALL_MODE` and sourced from
`03-install.sh` **before** `validate_install_context` runs, so the dispatcher
can call `layout_validate` on the active adapter. The seam wrappers enforce
phase ordering via `_layout_enter_phase` / `_layout_exit_phase` in
`layout-common.sh` (phases: validate→plan→partition→pools→esp); a verb called
out of order aborts via `error` before any destructive operation. Mode-private
globals (`SINGLE_*`, `MULTI_*`, `OS_ESP_PARTS`, `STORAGE_PARTS`,
`RESOLVED_TOPOLOGIES`) stay inside the module — consumers only read `LAYOUT_*`.
Reframed as the ZFS **Filesystem Adapter** once the filesystem axis lands: the
mode-keyed split *is* ZFS today (ADR 0040).

### Filesystem Adapter
The reserved seam that selects the on-disk filesystem, keyed on a top-level
`filesystem` discriminator (default `zfs`; reserved `btrfs`, `ext4`, `xfs`).
Generalizes the current mode-keyed Layout Module — today `lib/layout/<mode>.sh`
(single/multi) *is* the ZFS adapter, and ZFS is the only implemented filesystem.
Each adapter owns its volume model (ZFS pools + datasets; btrfs subvolumes;
ext4/xfs bare partitions ± mdadm/LVM), its RAID story (ZFS/btrfs native;
ext4/xfs via mdadm/LVM), and how the encryption method is realized — ZFS native
AES-256-GCM vs dm-crypt/LUKS *under* the filesystem. Impermanence (ZFS dataset
rollback) and the Bootloader Adapter's `root=` become filesystem-conditional;
non-snapshotting filesystems (ext4/xfs) offer no Impermanence. Only the ZFS
adapter exists today — the discriminator, the additive `options.encryption_method`
(`native` | `luks`, default derived from `filesystem`), and the fs-keyed dispatch
are landed up front so a future filesystem is an additive adapter, never a schema
migration (ADR 0040).

### Storage Group
A vdev (or set of per-disk vdevs) folded into the single Combined Data Pool in
multi-disk mode. Declared in `storage_groups[]` in the Host Profile (`name`,
`disk_count`, `mount`, optional `topology`/`ashift`/`owners`) — devices are
operator-picked and assigned to the group by the Pre-Install Picker, never
committed. Each group surfaces as datasets under `dpool/DATA/<name>`; all groups
share one pool and therefore one failure domain. Use a Storage Group when you
want several disks pooled together (with redundancy) under one name. Contrast
Standalone Data Pool.

### Combined Data Pool
The single `dpool` assembled from every Storage Group (and any leftover OS disks
folded in when OS topology is `none`) in multi-disk mode. One pool, one failure
domain. Optional — absent when there are no Storage Groups and no folded
leftovers. Contrast Standalone Data Pool.

### Standalone Data Pool
A ZFS pool that owns its disk(s) outright rather than folding into the Combined
Data Pool — its own name, mountpoint, topology, and **failure domain**, so one
pool losing a disk never affects another. Declared per-entry in `data_pools[]`
in the Host Profile (`name` = the zpool name and `disk_count` required; optional
`topology`/`mount`/`ashift`/`owners`); operator-picked devices are assigned by
the Pre-Install Picker. Topology is limited to
`stripe`/`mirror`/`raidz1`/`raidz2`; `none` and `independent` are rejected —
"each disk separate" is expressed as multiple entries, and "all disks, no
redundancy" is `stripe`. Encryption inherits the global `options.encryption`.
Multi-disk only. Also producible interactively: when OS topology is `none`, each
leftover disk may be chosen per-disk as its own Standalone Data Pool (named at
the prompt) instead of folding into the Combined Data Pool. Contrast Storage
Group.

### Pool Owners
The optional `owners` field on a `data_pools[]` or `storage_groups[]` entry —
the principals granted read/write to that pool's mountpoint, so a human (not
just `root`) can use it. Each element is a username or a `@group` (the `@`
distinguishes the two namespaces; groups come from a User Profile's `groups`).
Omitted → the Primary User. A single bare user → a plain `chown` (mode `0755`).
More than one principal, or any `@group` → POSIX ACLs (`acltype=posixacl`): the
first listed user is the nominal owner, and every user / `@group` gets an `rwx`
entry plus a default-ACL so new files inherit it; group grants stay dynamic
(membership lives in a User Profile, not a snapshot). Every user with access —
listed users plus members of listed groups — gets a `~/Disks/<pool>` symlink so
any file manager (GUI or TUI) reaches it without per-app bookmarks. Validated at
install: a bare name must be a declared user, a `@group` must have ≥1 declared
member. Applied install-time after the Runner creates users + groups, on the
host against the altroot-mounted paths, resolving each owner to a numeric
UID/GID from the installed `/etc/passwd` + `/etc/group` (the live ISO has no
knowledge of the chroot's users); ACL group grants use `g:<gid>:rwx` so
membership stays dynamic. (ADR 0031.)

### Program Runner
`.os/lib/run-program.sh`. Wrapper invoked by the Runner inside arch-chroot for
every Program Install Script. Verifies the chroot-side staged tree (Shell Stdlib
readable, install.sh readable) and exits 99 with a clear message on mismatch.
Sources Shell Stdlib once and sources the install.sh in the same shell, so
install.sh files inherit `set -Eeuo pipefail` and the stdlib helpers without a
per-script source line.

### Chroot Configuration Module
`.os/lib/chroot/`. Set of shell scripts copied into `/mnt/root/lib-chroot/`
before `arch-chroot` and orchestrated by `configure.sh` inside the chroot. Each
sub-script owns one concern: identity (locale/timezone/keymap/hostname), pacman
config, initcpio (ZFS hook + mkinitcpio), root password, an extras runner
(KDE desktop adapters), plus a Bootloader Adapter. `lib/chroot.sh` shrinks to
live-ISO concerns: write_fstab, write_esp_mirror_hook, collect_passwords, and
the single `arch-chroot` invocation that stages and runs `configure.sh`.

### Bootloader Module
The seam selecting between Bootloader Adapters. The active adapter is chosen by
`options.bootloader` in the Host Profile (`systemd-boot` or `grub`). The chroot
orchestrator invokes `bash /root/lib-chroot/bootloader-${BOOTLOADER}.sh`. Adding
a new bootloader means dropping in a new Bootloader Adapter — no `if/elif`
branches grow.

### Bootloader Adapter
`.os/lib/chroot/bootloader-<name>.sh`. Concrete bootloader implementation:
package install, config file generation, kernel-image entry registration. Two
adapters today: `bootloader-systemd.sh` and `bootloader-grub.sh`. Each adapter
reads the same env vars from the orchestrator (`KERNEL`, `ROOT_DATASET`, ESP
info, etc.) and is interchangeable from the orchestrator's view.

### ESP Kernel Sync
The systemd-boot-only pacman hook (`94-esp-kernel-sync.hook` →
`/usr/local/lib/archzfs/esp-kernel-sync.sh`, installed from the shared
`lib/boot/esp-kernel-sync.sh`) that copies the kernel image, microcode, and
initramfs from the ZFS `/boot` onto the FAT32 ESP after every kernel
transaction — required because systemd-boot cannot read ZFS. The files mirrored
are driven by the loader entries: only files an entry references (its
`linux`/`initrd` lines) that exist in `/boot` are copied, so a Stray Kernel —
having no entry — is never mirrored, and a missing file is never referenced.
Numbered `94` so it runs before the ESP Mirror Hook. Distinct from it (ADR
0038).

### ESP Mirror Hook
The pacman hook (`95-esp-mirror.hook` → `/usr/local/sbin/esp-mirror`) installed
only on multi-disk OS layouts (≥2 ESPs); it rsyncs the primary ESP
(`/boot/efi`) onto every secondary ESP (`/boot/efi1`, …) so each OS disk stays
independently bootable. Bootloader-agnostic. Runs after the ESP Kernel Sync
(`94` < `95`) so secondaries receive freshly-synced images. Distinct from the
ESP Kernel Sync.

### Environment Config
The `"environment"` key in the Host Profile. Declares desktop environment
selection and GPU driver selection. Audio is not declared — it is auto-derived
(PipeWire when any desktop is selected, omitted for server installs). Processed
at config-load time; populates `packages.groups.gpu` and `packages.groups.audio`
before pacstrap. Valid desktop values: `"kde"`, `"hyprland"`, or `["kde",
"hyprland"]`. Valid GPU values: `"amd"`, `"nvidia"`, `"intel"`, `["amd",
"nvidia"]`, or `"auto"`. Replaces `post_install.desktop` from the previous
schema.

### Desktop Environment Adapter
Script at `extras/desktop/<name>/<name>.sh` with a companion
`install-<name>.jsonc` for per-component toggles. Invoked dynamically by the
Environment Runner based on `environment.desktop`. Each adapter owns every
DE-tied package (apps, Qt plugins, AUR theming bridges): it installs its repo
packages via pacman, writes its display manager config, and enables its
services. AUR dependencies are not installed by the adapter — they are declared
in an optional top-level `aur` field of `install-<name>.jsonc` (same 2-level
Categorized List `{ category: { pkg: bool } }` shape as `apps_list`, validated
in bool mode; absent field contributes nothing) and installed by the Profiles
Runner's paru pass. Adding a new DE requires only a new `extras/desktop/<name>/`
directory — no runner code changes.

### Environment Runner
The extras dispatcher in `lib/chroot/extras.sh`. Iterates the resolved
`environment.desktop` array and invokes each Desktop Environment Adapter by
directory convention (`extras/desktop/<de>/<de>.sh`). No DE names are hardcoded
in the runner — dispatch is purely by convention. Security & Backup Extras are
no longer dispatched here — they install via the Profile Runner's Primary-User
paru pass (see Security & Backup Extras). AUR discovery for the
selected DEs lives alongside this: for each desktop in the resolved array the
installer reads that adapter's `aur` list and unions it (deduped) with the
host's `packages.aur` into the Profiles Runner's single paru invocation, so
DE-tied AUR packages land only when their DE is selected.

### GPU Resolution
Translation of `environment.gpu` into driver packages at config-load time.
`"auto"` uses `lspci` on the live ISO to detect all GPU vendors and resolves to
a string or array. Hybrid configs (e.g., `["amd", "nvidia"]`) install per-vendor
drivers plus `envycontrol`. Resolved packages populate `packages.groups.gpu`
before pacstrap.

Vendor → package mapping:
- `"amd"` → `vulkan-radeon xf86-video-amdgpu mesa libva-mesa-driver`
- `"nvidia"` → `nvidia-open-dkms nvidia-utils lib32-nvidia-utils
  libva-nvidia-driver egl-wayland` (open kernel module only; requires
  Turing+/RTX 20xx+; DKMS used so it builds against both `linux` and
  `linux-lts`)
- `"intel"` → `intel-media-driver` (Broadwell/5th-gen+) or `libva-intel-driver`
  (pre-Broadwell), auto-selected by parsing `lspci` device ID
- VM GPU (VMware/VirtualBox/virtio-gpu) → `mesa` only (software rendering);
  detection logs a notice and continues without aborting

### Display Manager
Auto-selected by each Desktop Environment Adapter based on the full resolved
desktop array — not a config key. KDE-only or KDE+Hyprland → SDDM (enabled by
the KDE adapter). Hyprland-only → greetd + greetd-tuigreet (enabled by the
Hyprland adapter, config written to `/etc/greetd/config.toml`).

### User Secrets
SOPS-encrypted JSON file at `.os/users/<username>/secrets.json`. Contains
sensitive per-user data: `password`, `ssh_identity_private_key`, and
`ssh_identity_key_type` (`ed25519` | `rsa` | `ecdsa`; defaults to `ed25519`).
Values are encrypted (keys remain plaintext). Optional — if absent, user
password defaults to `12345` and no SSH identity is deployed. Parallel to the
User Profile; read by the Secrets Module at install time and consumed by user
creation and SSH provisioning. Not merged with User Core — secrets are always
user-specific.

### Host Secrets
SOPS-encrypted JSON file at `.os/hosts/<profile>/secrets.json`. Contains
`root_password` for the host. Parallel to the Host Profile; read by the Secrets
Module at install time and consumed by root password provisioning. Optional — if
absent, root password falls back to interactive prompt.

### Secrets Module
`lib/secrets.sh`. Runs immediately after config load in `03-install.sh`. Locates
the passphrase-encrypted Operator Age Key via two sources in priority order: (1)
a removable USB device scanned for `/age/key.age`; (2) an HTTPS download from
`options.age_key_url` in the Host Profile (live-CD fallback when no USB is
present). Prompts for the passphrase, decrypts all User Secrets and Host Secrets
to a tmpfs, and writes the tmpfs paths into `install-state.json` for consumption
by chroot scripts. Clears the tmpfs after the chroot phase completes.

### Machine Age Key
Age private key stored at `/etc/secrets/age/keys.txt` on the installed system.
Derived at install time from the machine's `ssh_host_ed25519_key` via
`ssh-to-age`. Used exclusively by the SOPS Runtime Service for boot-time
decryption. Must be added as a recipient in `.sops.yaml` and secrets
re-encrypted via `sops updatekeys` after first install.

### SOPS Runtime Service
Systemd service installed by `.os/programs/security/sops/install.sh`. Runs early
in boot (before user services), mounts a tmpfs at `/run/secrets/`, decrypts all
SOPS-encrypted secret files using the Machine Age Key, and sets declared
ownership and permissions. Programs that need runtime secrets reference
`/run/secrets/<name>` paths. The sops Program is secrets-activated: the Runner
installs it (deriving the Machine Age Key and building `ssh-to-age` via `go`)
only when the host or one of its declared users ships a `secrets.json` —
consistent with secrets being optional. It is therefore not a member of any
host's declared System Programs, including Host Core; a host with no secrets
gets neither the service nor `go`.

### Base Package List
The hardcoded set pacstrapped onto every host regardless of config, defined in
`lib/packages.sh:collect_packages` (e.g. `base`, `base-devel`, the selected
kernel + headers, `linux-firmware`, `intel-ucode`/`amd-ucode`,
`zfs-dkms`/`zfs-utils`, `networkmanager`, `openssh`, `efibootmgr`, `dosfstools`,
`vim`, `git`, `sudo`, `rsync`, `jq`, `pacman-contrib`, `man-db`, `cronie`). The
**only** cross-host package base — Host Core carries no package list. A Host
Package List is deduplicated against it at install time. Universal
infrastructure daemons whose package lives here (NetworkManager, cron) are
enabled by the Chroot Configuration Module, not by a Program (ADR 0026).

### Host Package List
`packages` object in a Host Profile with two fields: `repo` (official-repo
packages installed via pacstrap) and `aur` (AUR packages installed via paru for
the primary user). `repo` is a 2-level categorized object — kebab-case category
keys mapped to string arrays — flattened to a sorted-unique list by the
Categorized List Parser at install time. Categories are cosmetic; renaming
`media` to `multimedia` does not change what installs. Shape, leaf-type, or
category-name violations abort at config-load with the offending path. `aur` is
likewise a Categorized List (the categorized shape landed — e.g. `{ "misc":
[...] }`). Declared in the host-specific Host Profile — not in Host Core —
because the list differs per machine. Deduplicated against base packages by the
installer. AUR packages are installed once for the system via the first declared
user's paru instance before any user programs run.

### Sysctl Defaults
`sysctl` object in Host Core (or a host-specific Host Profile), containing
key-value pairs written verbatim to `/etc/sysctl.d/99-os.conf` during the
profiles phase. Applied to every host via Host Core. A host-specific config can
add keys (they deep-merge per the core merge rules) but cannot remove keys
declared in core.

### Security & Backup Extras
The `post_install.security` and `post_install.backup` objects in a Host
Profile — the host's hardening and backup tool selection, authored by hand or by
the Guided Installer's Security / Backup categories. `security` picks one
firewall (`firewalld` | `ufw` | none; the two are mutually exclusive) plus
`clamav` (antivirus), `rkhunter` (rootkit scanner), and `apparmor` (MAC);
`backup` picks `zfs-auto-snapshot` and/or `borg`. The selected tools are
paru-based User Programs (`system:false`; paru refuses root), so they are
**not** installed as System Programs — the Runner unions the resolved program
names into the **Primary User's** paru pass (the seam host AUR packages already
use), and each tool's existing Program Install Script runs unchanged. Supersedes
the former boolean `post_install.*` extras, which dispatched to never-shipped
`extras/security.sh` / `extras/backup.sh` (ADR 0041). A host with no users
cannot carry these — the Guided Installer aborts at the terminal action.

### Tools
`.os/tools/`. Utility scripts for managing a running system or preparing an
install — not part of the install flow itself. Currently: `save-pkglist.sh`
(writes current packages to `hosts/<hostname>/pkglist-repo.txt` and
`pkglist-aur.txt`), `install-pkglist.sh` (installs packages from those files),
`impermanence.sh` (see Impermanence Tool), and `fetch-iso.sh` (downloads +
sha256-verifies the archzfs-Compatible ISO for USB prep). The pkglist tools
default to `$(hostname)` but accept a hostname argument.

### archzfs-Compatible ISO
Newest archived Arch ISO (from `archive.archlinux.org`) whose kernel major.minor
matches a kernel `archzfs` ships a prebuilt `zfs-linux` for. The prebuilt-kernel
list is used as a proxy for "the current ZFS source is known to compile against
this kernel" — even though the installer always builds ZFS via DKMS, not the
prebuilt. Resolved by `iso_resolver_get_zfs_compatible` in
`lib/iso-resolver.sh`. The installer cannot use the latest Arch ISO when its
kernel is newer than `archzfs` tracks: DKMS then fails to build the ZFS module
against that kernel.

### Kernel Selection
`options.kernel` in the Host Profile: one or more kernel flavour tokens naming
which kernels the installed system gets. Accepts a single token (string) or a
list. Tokens map to a kernel package plus its matching headers:
`lts`→`linux-lts`, `default`→`linux`, `zen`→`linux-zen`,
`hardened`→`linux-hardened`. Every selected kernel is installed, and `zfs-dkms`
builds the ZFS module against each. `lts` is the only token `archzfs` is
guaranteed to track; any other (notably `default`, the rolling kernel) may
temporarily outrun `archzfs` and is caught by the ZFS Module Guard. Defaults to
`lts`.

### Primary Kernel
The first token in the Kernel Selection. Drives the bootloader default boot
entry and the initramfs preset/fallback logic — exposed to chroot modules as the
scalar `KERNEL` (the full list is `KERNELS`). When more than one kernel is
selected, the others are still installed and `mkinitcpio -P` builds their
presets, but the bootloader default and the custom fallback-preset injection
track only the Primary Kernel until full multi-kernel preset wiring lands.

### ZFS Module Guard
Post-pacstrap check, host-side, run before chroot configuration begins. Verifies
a loadable `zfs` module exists for every kernel installed into the target,
aborting the install with archzfs-support guidance if any kernel lacks one.
Turns the otherwise opaque mid-`mkinitcpio` "module not found" failure into an
early, explicit error naming the unsupported kernel. Necessary because Kernel
Selection may include kernels newer than `archzfs` tracks (see
archzfs-Compatible ISO).

### Stray Kernel
A kernel installed on a host but **not** in its Kernel Selection — e.g. a
rolling `linux` pulled in out-of-band on an lts-only host. Boot-harmless under
the hardened path: the ESP Kernel Sync mirrors only entry-referenced kernels, so
a stray never reaches the ESP, systemd-boot entries name only the Primary
Kernel, and under GRUB `GRUB_TOP_LEVEL` pins the Primary Kernel as default so a
higher-sorting stray cannot auto-boot. It still wastes ZFS `/boot` space and,
lacking a buildable `zfs.ko`,
would be a trap if booted. Surfaced — warned, never removed — by a non-blocking
PostTransaction hook (`97-stray-kernel-warn.hook`) that reuses the ZFS Module
Guard's `zfs.ko`-presence check (ADR 0038).

### Impermanence
Optional install-time feature that resets selected system directories to a clean
state on every boot via ZFS dataset rollback. Enabled by `options.impermanence`
in the Host Profile. When enabled, the installer creates a Persist Dataset,
splits a set of Rollback Datasets out of the OS pool, takes a Blank Snapshot of
each, and installs a Rollback Hook in initramfs. Inspired by NixOS impermanence;
deliberately narrower in scope — Arch lacks a `/nix/store`-equivalent, so
rolling back all of `/` would erase every pacman update, hence Impermanence
targets `/etc`, `/root`, `/opt`, `/srv`, `/usr/local` only.

### Persist Dataset
ZFS dataset (default `rpool/persist`, mounted at `/persist`) that holds all
state surviving across reboots when Impermanence is enabled. Name and mountpoint
configurable via `options.impermanence.dataset` and `options.impermanence.mount`
in the Host Profile. Must live on the same pool as `rpool/ROOT/arch` so the
early-boot bind-mounts complete before `local-fs.target`. Holds the Persist
Payload (operator-editable `.mount` units + tmpfiles snippets) plus the actual
data of every persisted path.

### Rollback Datasets
The set of ZFS datasets reverted to their Blank Snapshot on every boot when
Impermanence is enabled: `rpool/ROOT/etc` (`/etc`), `rpool/ROOT/root` (`/root`),
`rpool/ROOT/opt` (`/opt`), `rpool/ROOT/srv` (`/srv`), `rpool/ROOT/usrlocal`
(`/usr/local`). Deliberately excludes `rpool/ROOT/arch` (so pacman writes to
`/usr` survive reboots without re-snapshot), `rpool/home`, `rpool/var`,
`rpool/var/log`, `rpool/var/cache`, `rpool/tmp` (already separate datasets,
naturally persistent except `/tmp` which is intended ephemeral). Created by the
installer when Impermanence is enabled; absent otherwise.

### Blank Snapshot
ZFS snapshot named `@blank` on each Rollback Dataset, taken at the end of the
chroot phase after Curated Persist Defaults have been moved off the dataset onto
the Persist Dataset. The Rollback Hook reverts each Rollback Dataset to its
Blank Snapshot at every boot. Re-created by the Pacman Resnapshot Hook after
every successful pacman transaction so that pacman's writes to `/etc/<pkg>/`
etc. survive across reboots. If `@blank` is missing on any Rollback Dataset, the
Rollback Hook drops to emergency shell — fail-closed.

### Rollback Hook
mkinitcpio hook pair installed under `/etc/initcpio/hooks/` and
`/etc/initcpio/install/` and added to `HOOKS=` in `mkinitcpio.conf` between the
`zfs` and `filesystems` hooks. Runs in initramfs after the ZFS module loads and
pool is imported (and decrypted, if `options.encryption=true`), and before
`zfs-mount-generator` mounts the Rollback Datasets. Hardcoded at install time
with the list of Rollback Datasets to revert. Fails closed if any Blank Snapshot
is missing — drops to emergency shell rather than continuing with stale state.

### Bootstrap Mount
Pair of files baked into `/usr/lib` at install time that bridge the Persist
Dataset into systemd's standard discovery paths.
`/usr/lib/tmpfiles.d/impermanence-bootstrap.conf` creates `/etc/systemd/system/`
and `/etc/tmpfiles.d/` as empty directories at early boot.
`/usr/lib/systemd/system/persist-etc-systemd-system.mount` and
`persist-etc-tmpfiles-d.mount` bind `/persist/etc/systemd/system` and
`/persist/etc/tmpfiles.d` over those placeholders. Lives on `rpool/ROOT/arch`
(non-rolled-back) so it persists across reboots without snapshot manipulation.

### Persist Mount
`.mount` unit named `persist-<slug>.mount`, one per persisted path. Each unit
bind-mounts `/persist/<path>` over `<path>` early in boot. Ordered
`After=systemd-tmpfiles-setup.service` and `Before=local-fs.target` with
`RequiredBy=local-fs.target` so a failed bind cascades to emergency. Curated
Persist Defaults ship as units under `/usr/lib/systemd/system/` (vendor-owned,
snapshot-immune); host-declared Persist Extensions ship as units under
`/persist/etc/systemd/system/` (operator-editable). Live data is staged onto the
Persist Dataset before the unit activates — moved at install time (the live path
will be reset on next boot), copied at runtime (the bind mount activates
immediately and covers the original).

### Curated Persist Defaults
Fixed list of system-identity paths the installer always persists when
Impermanence is enabled. Files: `/etc/machine-id`, `/etc/hostname`,
`/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/adjtime`, `/etc/fstab`.
Directories: `/etc/ssh`, `/etc/secrets`,
`/etc/NetworkManager/system-connections`, `/etc/sudoers.d`, `/etc/pacman.d`,
`/root`. Loss of any of these breaks first reboot — host keys, Machine Age Key,
hostname, network connections, fstab. Shipped as Persist Mount units under
`/usr/lib/systemd/system/` so they're stable across operator edits.

### Persist Extensions
`persist` object in a Host Profile or Host Core with two arrays: `directories`
and `files`. Each entry is an absolute path. Deep-merged across Host Core and
the specific Host Profile per the standard merge rules. Translated by the
installer into Persist Mount units under `/persist/etc/systemd/system/` and
tmpfiles entries placed under `/persist/etc/tmpfiles.d/`. Only meaningful when
`options.impermanence.enabled=true`. Validation warns on paths already covered
by an always-persistent dataset (`/home`, `/var`, `/var/log`, `/var/cache`,
`/tmp`) or by a Curated Persist Default.

### Pacman Resnapshot Hook
Pacman post-transaction hook at
`/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook` (or shipped under
`/usr/share/libalpm/hooks/`) that destroys and re-takes the Blank Snapshot on
every Rollback Dataset after a successful pacman transaction. Necessary because
pacman writes config defaults under `/etc/<pkg>/` etc.; without this hook those
writes would vanish on next reboot. Known v1 limitation: user edits to
non-persisted paths under a Rollback Dataset made *before* a pacman transaction
get baked into the new Blank Snapshot and survive one additional reboot. A
future opt-in pre-transaction drift check (`zfs diff` fails loudly if dirty)
closes this leak.

### Impermanence Tool
`.os/tools/impermanence.sh`. Runtime utility for managing Persist Extensions on
a system where Impermanence is enabled. Verbs: `add <path>` (writes the path
into the host's `persist.directories` or `persist.files` in
`hosts/<hostname>/profile.jsonc`, copies current data onto the Persist Dataset,
generates the Persist Mount, daemon-reloads); `remove <path>` (reverses);
`status` (lists active Persist Mounts and runs `zfs diff` against `@blank` for
each Rollback Dataset); `apply-defaults` (regenerates Curated Persist Defaults'
unit files under `/usr/lib/systemd/system/` from the installer's current curated
list, used after pulling an updated dotfiles repo). Does not edit Curated
Persist Defaults directly — those are vendor-shipped.

### Stow Tree
Top-level dotfile dirs in the repo (`.config/`, `.zsh/`, `.claude/`, plus loose
home-relative files like `.zshrc`, `.p10k.zsh`) that GNU stow symlinks into each
user's `$HOME` via `stow --no-folding */` during the Runner's dotfiles step.
Layout groups files by destination path, not by program. Legacy as of ADR 0012 —
being migrated program-by-program into Program Config Trees, but remains
supported indefinitely. Path collisions with the Generated Stow Tree abort the
Config Generator.

### Program Config Tree
Per-program user-side config files under
`.os/programs/<category>/<name>/configs/`. The unsuffixed `configs/` is the
default; sibling `configs@<variant>/` directories hold alternates (Config
Variants). Optional — programs without user-side config omit the dir entirely.
Manifest scope is user paths only; system paths stay in the program's
`install.sh`. Authoring location only — never directly symlinked or copied; the
Config Generator materializes the Generated Stow Tree from these.

### Config Variant
An alternate version of a program's Program Config Tree, named by the suffix on
`configs@<variant>/`. Variant names match `[a-z0-9-]+`; `default` is reserved
and refers to the unsuffixed `configs/`. Selected per-user via a `variants`
object in a User Profile (with House Defaults inheritable from User Core,
overridden per-key by the User Profile). Unselected variants fall back to
`configs/`; programs with only `configs@*/` and no `configs/` require an
explicit selection or the generator aborts.

### Config Manifest
`manifest.jsonc` inside each `configs[@variant]/` directory. Declares file
placement only — `files` is an array of `{ src, dst, mode? }` entries. `src` is
relative to the manifest's directory; `dst` is a `~/`-rooted user path. No
templating, no conditionals, no hooks, no system paths, no encrypted entries.
Constraints exist so that complexity is forced into the Config Variant axis
instead of into per-file metadata.

### Generated Stow Tree
Per-user materialized tree at `~/.dotfiles/.stow/<user>/` produced by the Config
Generator on the target machine. Mirrors destination paths (`.config/<...>`,
`.local/<...>`, home-relative files at root). Gitignored — never committed,
always regenerable from the repo + User Profile + Config Variants. Consumed by
`stow -d ~/.dotfiles/.stow/<user> --no-folding .`, which runs after the legacy
Stow Tree pass.

### Config Generator
`.os/tools/generate-configs.sh`. Reads the merged User Core + User Profile for a
target user and the merged Host Core + Host Profile for the machine (hostname
looked up at runtime). Resolves each program's Config Variant via the Variant
Resolver, validates all relevant Config Manifests, builds a per-user plan via
the Plan Builder, and materializes the Generated Stow Tree. Invoked by the
Runner inside `arch-chroot` per user between the dotfiles clone and the stow
invocation. Also runnable standalone after install (`--user <name>`) to
re-render after variant edits. Flags `--validate-only` and `--dry-run` are
supported. Aborts if a planned destination is already owned by the legacy Stow
Tree.

### Plan Builder
Pure function inside the Config Generator. Inputs: the resolved Config Variant
map, the per-user `~/.dotfiles/.stow/<user>/` stow root, and the declared
program set (User Programs from User Core + User Profile, unioned with System
Programs from Host Core + Host Profile). Output: a deterministically-ordered
flat list of `{ src_abs, dst_in_stow_tree, mode? }` entries. No writes. Programs
with a Program Config Tree on disk but not in the declared set are silently
omitted — mid-migration is a normal state.

### House Defaults
Variants declared in User Core's `variants` object, applied to every user unless
overridden per-key in their own User Profile. Same merge semantics as the rest
of the User Core / User Profile relationship — core first, user adds on top,
individual keys can be replaced without replacing the whole object.

### VM Profile
A JSON file describing one virtual machine to provision for install testing or
dev use, consumed by the VM Harness — never installed onto real hardware
(distinct from a Host Profile). Carries a `hardware` block (disk sizes, RAM,
vCPUs) and names the machine's install source via exactly one of two top-level
keys (`host_profile` xor `install`): a `host_profile` reference names a real
host directory, resolved through the unified Profile Loader — the picker
assembles its Effective Config against the VM's virtual disks, keeping one
source of truth; or an `install` block, either an inline Effective Config (a
full assembled config, for test-only permutations with no real Host Profile) or
the string `"repo"`, meaning the repo's designated default Host Profile named by
the single harness constant `VM_DEFAULT_HOST_PROFILE` (default `arch-kde`),
hostname patched — the smoke test that the shipped default installs (ADR 0036,
amending ADR 0035). Profiles for persistent/usable VMs live under
`.os/vm/profiles/<category>/`; test profiles live under
`.os/tests/vm/profiles/<category>/` and additionally carry verification
expectations (pools, mounts, owners, boot checks). Grouped into Profile
Categories (subdirectories).

### VM Harness
`.os/vm/vm.sh`. The single profile-driven entry point that provisions a libvirt
VM from a VM Profile and runs `install.sh --unattended` inside it. Default flow
builds a persistent, reusable VM (spice graphics, reboots into the installed
system for interactive use via virt-manager). `--testing` selects the disposable
test flow (headless, serial-console capture, sentinel watcher, installer
exit-code propagation, opt-in boot-verify). Validates the profile up front
(schema, exactly one install source, and that any referenced `host_profile`
names a real host directory) before doing any work, mirroring the repo's
fail-fast config validation. Shared host-side core (dependency checks, ISO
resolution, Effective Config assembly, libvirt domain create/boot) and the two
divergent flows live in `vm/lib/`. A test profile run **without** `--testing`
yields a persistent VM of that exact config — the supported way to interactively
debug a failing test case.

### Profile Category
The subdirectory grouping VM Profiles within a `profiles/` tree. The axis
differs per tree: persistent profiles (`.os/vm/profiles/`) are categorized by
desktop/use (`desktop/`, `headless/`); test profiles (`.os/tests/vm/profiles/`)
are categorized by the install path they exercise (`single/`, `multi/`,
`data-pools/`, `impermanence/`, `env/`). Each profile lives in exactly one
category; when a feature category fits (e.g. `impermanence/`, `env/`) it wins
over the bare layout-mode category.

## Flagged ambiguities

- "base packages" vs "core packages" — resolved: the **Base Package List**
  (hardcoded in `lib/packages.sh`) is the only shared package base. **Host
  Core** carries **no** `packages` object — only `system_programs` and `sysctl`;
  package lists live per-host (ADR 0007). The ADR 0021 clause placing
  `extra-cmake-modules` in Host Core is withdrawn (see ADR 0021 amendment); ECM
  is dropped entirely since paru resolves makedepends at build time.
- DE packages in host configs — resolved: every package derivable from
  `environment.desktop` belongs to its **Desktop Environment Adapter**, not a
  Host Profile (ADR 0021). Applies to Hyprland as of the 0021 amendment, not
  only KDE.
- `host_profile` now lives at one layer only (ADR 0036): it is a **VM Profile**
  key naming a real host directory, which the unified Profile Loader resolves to
  that machine's **Host Profile** (the picker assembles the **Effective Config**
  against the VM's virtual disks). The former install-config `host_profile`
  *field* is gone — a machine's identity is its profile directory name, i.e. the
  `install.sh --profile <name>` argument.
