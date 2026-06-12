# Arch Linux ZFS Installer

A fully scripted, config-driven Arch Linux installer with ZFS as the
root filesystem. Supports single-disk laptops, multi-disk RAID
desktops, optional encryption, declarative host/user profiles, KDE
or Hyprland desktops, SOPS-encrypted secrets, and optional ZFS
impermanence (rollback-to-blank on every boot).

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Quick Start](#2-quick-start)
3. [Resolving disks (`install.sh --profile`)](#3-resolving-disks-installsh---profile)
4. [Secrets Management (SOPS)](#4-secrets-management-sops)
5. [File Layout](#5-file-layout)
6. [Common Configurations](#6-common-configurations)
7. [Optional Components](#7-optional-components)
8. [VM Testing](#8-vm-testing)
9. [After Installation](#9-after-installation)

---

## 1. Architecture

> Config-altitude view (lifecycle flow, config→effect map, merge
> model) lives in [`ARCHITECTURE.md`](ARCHITECTURE.md). The tree
> below is the module-altitude view.

```
install.sh                  Entry point. Runs phases in order.
│                           Forwards -y/--unattended and an
│                           optional config path.
│
├─ 01-bootstrap-zfs.sh      Add archzfs repo, install ZFS DKMS.
├─ 02-wipe.sh               Tear down LVM/RAID/ZFS, zero disks.
└─ 03-install.sh            Thin orchestrator. Sources lib/.
    │
    ├─ lib/config/profile.sh  Load the profile, closed-schema
    │                         validate, assemble the effective config.
    ├─ lib/config/layers.sh   JSONC merge + program resolution.
    ├─ lib/environment.sh   Resolve environment.desktop / .gpu
    │                       into package groups.
    ├─ lib/secrets.sh       Locate operator age key (USB or
    │                       options.age_key_url), decrypt
    │                       host/user secrets to tmpfs.
    ├─ lib/layout-single.sh ESP + rpool + optional dpool.
    ├─ lib/layout-multi.sh  ESP per disk, rpool topology,
    │                       storage_groups (mirror/stripe/raidz).
    ├─ lib/packages.sh      Collect packages, pacstrap base.
    ├─ lib/chroot.sh        Write fstab, ESP-mirror hook, stage
    │                       scripts, run arch-chroot.
    │   └─ lib/chroot/      Runs inside chroot (see below).
    ├─ lib/configs.sh       Merge host/user core + specific
    │                       configs; validate program refs.
    ├─ lib/profiles.sh      Install system programs, create
    │                       users, bootstrap paru, install user
    │                       programs.
    ├─ lib/validation.sh    Single seam for config-contract
    │                       checks (impermanence, programs, …).
    └─ lib/finalize.sh      Unmount ESPs, zpool export.
```

Scripts inside `lib/chroot/`:

- `configure.sh`        — sub-script orchestrator
- `identity.sh`         — locale, timezone, hostname,
                          mkinitcpio.conf
- `initcpio.sh`         — ZFS hooks, `mkinitcpio -P`
- `bootloader-systemd-boot.sh` — selected by `options.bootloader`
- `bootloader-grub.sh`  — selected by `options.bootloader`
- `password.sh`         — root password (uses host secrets if
                          present, else prompts)
- `create-user.sh`      — per-user creation (shell, groups,
                          sudo, password, SSH identity)
- `impermanence.sh`     — rollback datasets, `@blank` snapshots,
                          persist mounts, initramfs hook
- `extras-common.sh`    — shared helpers for the extras stage
- `extras.sh`           — Environment Runner: dispatches to
                          `extras/desktop/<de>/<de>.sh` plus
                          `post_install` toggles

### Multi-disk ESP mirroring

Each OS disk gets its own ESP. A pacman hook
(`95-esp-mirror.hook`) rsyncs the primary ESP to secondaries
after every kernel update. Each secondary is also registered as
an independent UEFI boot entry via `efibootmgr`, so any OS disk
can boot the machine standalone.

---

## 2. Quick Start

### 2.1 Prepare the install media

On your **current machine** (Arch), from this repo, download the ISO
the installer can build ZFS against:

```bash
bash .os/tools/fetch-iso.sh
#   → ~/Downloads/archlinux-<ver>-x86_64.iso
# or pass a directory:
bash .os/tools/fetch-iso.sh /path/to/dir
```

Then flash it to a USB stick with `dd` (or Ventoy / Impression /
Rufus):

```bash
sudo dd if=~/Downloads/archlinux-<ver>-x86_64.iso of=/dev/sdX \
  bs=4M status=progress oflag=sync
```

> **Why not the latest Arch ISO?** ZFS will not build against a kernel
> newer than `archzfs` tracks, so the latest ISO breaks the
> installer's DKMS step. `fetch-iso.sh` resolves the newest
> **archzfs-Compatible ISO** instead — see the term in `CONTEXT.md`
> and ADR 0023.

### 2.2 Boot the Arch ISO

Boot the USB stick you just flashed in **UEFI mode**.

### 2.3 Connect to the internet

**Ethernet** — works automatically via DHCP.

**Wi-Fi:**

```bash
iwctl
device list
station wlan0 connect "Your Network"
exit
```

### 2.4 Copy the scripts to the live environment

**From a USB stick:**

```bash
mount /dev/sdX1 /mnt/usb
cp -r /mnt/usb/dotfiles /root/
cd /root/dotfiles/.os
```

**From a URL (if you have network):**

```bash
curl -LO https://your-host/dotfiles.tar.gz
tar -xzf dotfiles.tar.gz
cd dotfiles/.os
```

### 2.5 Pick or author the host profile

A machine is described by one file — `hosts/<name>/profile.jsonc`,
merged over `hosts/core/profile.jsonc`. It carries everything: the
pool skeleton (devices excluded), ZFS/locale/bootloader/encryption/
impermanence options, packages, environment, users, and system
programs. The one field that can't be committed — the physical disks
— is resolved at install time (§3).

```bash
vim hosts/<name>/profile.jsonc        # the whole machine
vim users/<name>/profile.jsonc        # shell, sudo, groups, programs
```

Every authored profile is validated against a single closed schema
at load: an unknown key at any depth aborts with its path before any
disk is touched. See `REFERENCE.md` for the full schema.

### 2.6 Install

```bash
chmod +x install.sh
./install.sh --profile <name>                  # interactive (picks disks)
./install.sh --profile <name> -y               # unattended (hostname preset)
./install.sh /path/to/effective.jsonc          # positional config seam
./install.sh --profile <name> --print-config   # validate + print, no install
```

`install.sh --profile <name>` validates the named Host Profile,
resolves the disks interactively (§3), assembles the effective
config in tmpfs (never committed — ADR 0036), then runs the three
numbered scripts in order — bootstrap, wipe, install — confirming
destructive steps as it goes. `-y` / `--unattended` bypasses every
confirmation prompt (the hostname must already be set in the
profile). The positional `<config-file>` form is the unattended seam
the VM seed injects. Each numbered script remains individually
runnable for debugging.

### 2.7 Reboot

```bash
reboot
```

Remove the installation media when prompted.

---

## 3. Resolving disks (`install.sh --profile`)

The profile declares the pool *skeleton* — `os_pool` plus optional
`storage_groups[]` / `data_pools[]` with topology, ashift, owners,
and a per-group `disk_count` — but no devices. `install.sh --profile
<name>` resolves the physical disks at install time and never commits
them, so a profile is portable across machines of the same shape.

### 3.1 Run it

Prerequisites: a live CD with network (`fzf` and `jq` self-install
via `pacman -Sy`) and a committed `hosts/<name>/profile.jsonc`.

```bash
./install.sh --profile <name>
```

The front-end:

1. **Validates** the profile (plus its users and referenced program
   configs) against the closed schema — a typo'd key aborts with its
   path before any disk write.
2. **Picks disks** — fzf multi-select over `/dev/disk/by-id/*` with an
   `lsblk`/`smartctl` preview pane; the live medium is filtered out.
3. **Assigns** the picked disks onto the declared groups by
   `disk_count`, in declared order (`os_pool` → `storage_groups[]` →
   `data_pools[]`), validated against the min-disk table (mirror /
   stripe ≥2, raidz1 ≥3, raidz2 ≥4). Single mode resolves one device.
4. **Assembles** the effective config in tmpfs and hands it to the
   back-end. The hostname falls back to the profile directory name
   when `system.hostname` is unset (ADR 0036).

Everything else — bootloader, locale, timezone, keymap, kernel,
environment, encryption, impermanence, pool/dataset names, ashift —
comes from the committed profile. They are properties of the machine,
not of the install: change them by editing `profile.jsonc`, not at
the prompt.

To preview the resolved config without installing:

```bash
./install.sh --profile <name> --print-config
```

---

## 4. Secrets Management (SOPS)

Secrets are optional. Without any `secrets.json` files the
installer works exactly as before — user passwords default to
`12345` (changed on first login) and no SSH identity is
deployed.

### 4.1 Prerequisites (operator machine)

```bash
pacman -S age sops
```

### 4.2 Generate your age key

```bash
age-keygen -o age-key.txt
# Public key is printed to stdout: age1...
# Keep this public key — it goes in .sops.yaml
```

Encrypt the key with a passphrase so it is safe to carry on a
USB stick:

```bash
age -p -o age-key.age age-key.txt
rm age-key.txt            # keep only the encrypted copy
```

### 4.3 Copy the key to your install USB

The installer scans removable devices for a file at
`/age/key.age`:

```bash
mount /dev/sdX1 /mnt/usb
mkdir -p /mnt/usb/age
cp age-key.age /mnt/usb/age/key.age
```

As a live-CD fallback (no USB available) you can also set
`options.age_key_url` in the host profile to an HTTPS URL serving
the same passphrase-encrypted `.age` file.

### 4.4 Configure `.sops.yaml`

Create `.sops.yaml` at the repo root, listing your age public
key as recipient:

```yaml
creation_rules:
  - path_regex: .os/(users|hosts)/.*secrets.json$
    age: "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Replace the `age1...` value with the public key printed in
step 4.2.

### 4.5 Create secrets files

User secrets:

```bash
sops .os/users/<username>/secrets.json
```

Add content (values are encrypted on save; keys remain
plaintext):

```json
{
    "password": "your-real-password",
    "ssh_identity_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
    "ssh_identity_key_type": "ed25519"
}
```

Host secrets (root password):

```bash
sops .os/hosts/<hostname>/secrets.json
```

```json
{
    "root_password": "your-real-root-password"
}
```

### 4.6 Install

Plug in the USB carrying `age-key.age` **before** running
`./install.sh` (or set `options.age_key_url`). The Secrets
Module finds the key, prompts for its passphrase, decrypts
secrets to tmpfs, and proceeds.

At the end of the install, the machine's age public key is
printed:

```
==> Machine age public key: age1yyyyyy...
==> Add it to .sops.yaml and run:
==>   sops updatekeys .os/users/*/secrets.json \
==>                   .os/hosts/*/secrets.json
```

### 4.7 Add the machine key and re-encrypt

```yaml
# .sops.yaml — add the machine key alongside yours
creation_rules:
  - path_regex: .os/(users|hosts)/.*secrets.json$
    age: |
      age1xxxxxx...   # your personal key
      age1yyyyyy...   # machine key (from install output)
```

```bash
sops updatekeys .os/users/<username>/secrets.json
sops updatekeys .os/hosts/<hostname>/secrets.json
git add .sops.yaml \
        .os/users/<username>/secrets.json \
        .os/hosts/<hostname>/secrets.json
git commit -m "secrets: add machine age key for <hostname>"
```

After this commit, the runtime SOPS service on the machine
(installed by `programs/security/sops`) can decrypt secrets on
every boot without the USB.

---

## 5. File Layout

```
.os/
├── install.sh              # Entry. Runs 01 → 02 → 03.
├── 01-bootstrap-zfs.sh     # ZFS DKMS on the live ISO
├── 02-wipe.sh              # Wipe disks (dd + wipefs + sgdisk)
├── 03-install.sh           # Partition, pacstrap, configure
│
├── lib/                    # Installer modules
│   ├── common.sh           # Colors, output, JSON helpers
│   ├── globals.sh          # Shared runtime globals
│   ├── config.sh           # Top-level config load + summary
│   ├── install-config.sh   # Schema, defaults, template gen
│   ├── install-state.sh    # install-state.json read/write
│   ├── jsonc.sh            # JSONC parser
│   ├── configs.sh          # Host/user config merging
│   ├── validation.sh       # Config-contract checks
│   ├── environment.sh      # Desktop + GPU resolution
│   ├── secrets.sh          # Age key + SOPS decryption
│   ├── zfs-pools.sh        # Pool/dataset primitives
│   ├── layout-common.sh    # Shared layout helpers
│   ├── layout-single.sh    # Single-disk layout
│   ├── layout-multi.sh     # Multi-disk layout
│   ├── packages.sh         # Package collection + pacstrap
│   ├── chroot.sh           # Stage scripts, run arch-chroot
│   ├── chroot/             # Scripts run inside the chroot
│   │   ├── configure.sh
│   │   ├── identity.sh
│   │   ├── initcpio.sh
│   │   ├── bootloader-systemd-boot.sh
│   │   ├── bootloader-grub.sh
│   │   ├── password.sh
│   │   ├── create-user.sh
│   │   ├── impermanence.sh
│   │   ├── extras-common.sh
│   │   └── extras.sh
│   ├── picker.sh           # Disk enumeration + group assignment
│   ├── profiles.sh         # Users + program installation
│   ├── run-program.sh      # Program-install wrapper
│   ├── finalize.sh         # Unmount + pool export
│   ├── iso-resolver.sh     # Arch ISO version selection
│   ├── shell-stdlib.sh     # Shared helpers for program scripts
│   ├── shell/              # Stdlib submodules
│   └── impermanence-common.sh  # Shared by chroot module +
│                               # runtime tool
│
├── hosts/                  # Per-hostname config
│   ├── core/               # Shared base for all hosts
│   ├── desktop/
│   ├── laptop/
│   └── vm/
│
├── users/                  # Per-user config
│   ├── core/               # Shared base for all users
│   └── <username>/         # User-specific overrides
│
├── programs/               # Self-contained installers
│   ├── PROGRAM_SPEC.md
│   ├── backup/             # borg, zfs-auto-snapshot
│   ├── bootloader/         # grub
│   ├── communication/      # teamspeak3
│   ├── privacy/            # searxng
│   ├── security/           # apparmor, clamav, firewalld,
│   │                       # rkhunter, sops, ufw
│   └── virtualization/     # docker, podman, virt-manager
│
├── extras/                 # In-chroot extras (DE adapters)
│   └── desktop/
│       ├── kde/kde.sh      # KDE Plasma 6 + SDDM
│       └── hyprland/hyprland.sh  # Hyprland + greetd
│
├── tools/                  # Operator utilities (runtime)
│   ├── save-pkglist.sh     # Snapshot current packages
│   ├── install-pkglist.sh  # Restore packages from txt
│   └── impermanence.sh     # add/remove/status/apply-defaults
│
├── tests/                  # BATS + VM integration tests
│   ├── run.sh              # BATS runner
│   ├── shellcheck.sh       # Code quality checks
│   ├── audit.sh
│   ├── *.bats              # Unit + chroot test files
│   ├── bats/               # Bundled BATS sources
│   └── vm/                 # Test VM Profiles + harness unit tests
│
├── vm/                     # Profile-driven VMs (vm.sh --profile)
│   ├── vm.sh               # Single entry point (+ --testing)
│   ├── lib/                # core.sh + flow-persistent/flow-test
│   ├── profiles/           # Persistent VM Profiles (desktop/, headless/)
│   └── fixtures/           # Staged install fixtures (e.g. key.age)
│
├── README.md               # This file
└── REFERENCE.md            # Full config + VM testing
```

---

## 6. Common Configurations

### 6.1 Laptop (single disk)

```json
"mode":    "single",
"disk":    "/dev/nvme0n1",
"ashift":  13,
"os_size": "auto"
```

### 6.2 Desktop (2 NVMes mirrored + 3 SSDs storage)

```json
"mode": "multi",
"os_pool": {
  "pool_name": "rpool",
  "topology":  "mirror",
  "ashift":    13,
  "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
},
"storage_groups": [
  {
    "name": "ssd",
    "mount": "/data/ssd",
    "ashift": 12,
    "topology": "raidz1",
    "disks": ["/dev/sda", "/dev/sdb", "/dev/sdc"]
  }
]
```

### 6.3 Desktop (2 NVMes, pick one for OS)

```json
"mode": "multi",
"os_pool": {
  "pool_name": "rpool",
  "topology":  "none",
  "ashift":    13,
  "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
}
```

At runtime you'll be asked which NVMe to install on. The other
is automatically added to `dpool`.

---

## 7. Optional Components

### Desktop environment

Set under `environment` in the host profile:

```json
"environment": {
  "desktop": "kde",          // or "hyprland",
                             // or ["kde","hyprland"], or null
  "gpu":     "auto"          // or "amd"/"nvidia"/"intel"/array
}
```

Each desktop dispatches dynamically to `extras/desktop/<de>/
<de>.sh`. Audio (PipeWire) is auto-derived when any desktop is
selected; GPU drivers are auto-detected with `"auto"`. Display
manager is chosen per the adapter (SDDM for KDE / KDE+Hyprland;
greetd for Hyprland-only).

### Impermanence

Set under `options` in the host profile:

```json
"options": {
  "impermanence": {
    "enabled": true,
    "dataset": "rpool/persist",
    "mount":   "/persist"
  }
}
```

When enabled, the installer creates rollback datasets for
`/etc`, `/root`, `/opt`, `/srv`, `/usr/local`, snapshots each as
`@blank`, and installs an initramfs hook that reverts them on
every boot. Curated defaults (machine-id, fstab, NM connections,
etc.) are bind-mounted from the Persist Dataset. See
`REFERENCE.md` § Impermanence for the full list.

### Backup / security programs

Backups and security hardening are now declared as system
programs in your host profile, not as `extras/` scripts:

```jsonc
// .os/hosts/<name>/profile.jsonc
"system_programs": [
  "zfs-auto-snapshot", "borg",   // backups
  "ufw", "clamav", "apparmor",   // security
  "firewalld", "rkhunter", "sops"
]
```

The `post_install.backup` and `post_install.security` toggles in
the profile remain as gates for any operator-supplied
`extras/backup.sh` / `extras/security.sh`; if those files are
absent (the default), the toggles are no-ops.

---

## 8. VM Testing

The same `vm.sh` entry point runs disposable integration tests
with `--testing`: it boots a throwaway VM headless, runs the
installer unattended from a **VM Profile**, and exits with the
installer's exit code (0 ok / 124 timeout / 125 boot-fail).
Test profiles live under `tests/vm/profiles/<category>/`.

> For **persistent, reusable VMs** (manual testing / dev), drop
> `--testing`; see [`vm/`](vm/). A test profile run without
> `--testing` builds a persistent VM of that exact case — the
> supported way to debug a failing test interactively.

**Prerequisites:** `virt-install`, `virsh`, `cloud-localds`,
`jq`, `libvirtd` running, user in `libvirt` group.

```bash
# Single-disk smoke (install:"repo" → the default host profile)
bash vm/vm.sh --testing --profile single/plain
bash vm/vm.sh --testing --profile single/dirty-cache

# Multi-disk topologies
bash vm/vm.sh --testing --profile multi/mirror
bash vm/vm.sh --testing --profile multi/stripe
bash vm/vm.sh --testing --profile multi/none
bash vm/vm.sh --testing --profile multi/mirror-storage

# Impermanence / encryption / SOPS
bash vm/vm.sh --testing --profile impermanence/single
bash vm/vm.sh --testing --profile impermanence/mirror
bash vm/vm.sh --testing --profile impermanence/kde-encrypted
bash vm/vm.sh --testing --profile impermanence/kde-sops

# Standalone data pools (boot-verify with --verify-boot)
bash vm/vm.sh --testing --verify-boot --profile data-pools/plain
bash vm/vm.sh --testing --verify-boot --profile data-pools/reorder

# Desktop environments (real host profiles)
bash vm/vm.sh --testing --profile env/kde
bash vm/vm.sh --testing --profile env/hyprland
bash vm/vm.sh --testing --profile env/kde-hyprland
```

Each run writes a timestamped log to `tests/vm/<vm-name>.log`.
The harness watches for an `===INSTALLER-EXIT-N===` sentinel
line and propagates the installer's exit code. `--verify-boot`
(or a profile's `verify` block) power-cycles to the installed
disk and waits for the first-boot sentinel. Timeout defaults to
1800 s (`TIMEOUT_SEC` env var overrides).

The ISO is auto-resolved to the newest archzfs-compatible Arch
release (cached in `tests/vm/.vm-test/`).

---

## 9. After Installation

### 9.1 First boot checklist

1. Verify ZFS pools: `zpool status`
2. Check datasets mounted: `zfs list`
3. Verify swap: `swapon --show`
4. Set up networking if needed: `nmtui`
5. Update the system: `sudo pacman -Syu`
6. If impermanence is enabled, run `bash tools/impermanence.sh
   status` to confirm `@blank` snapshots exist on every Rollback
   Dataset. Missing snapshots fail-close on the next reboot.

### 9.2 If ZFS fails to import on boot

Boot from the live ISO, run `01-bootstrap-zfs.sh` again, then:

```bash
zpool import -f rpool
zpool import -f dpool
```

### 9.3 ESP backup (single-disk, no RAID)

```bash
sudo rsync -a /boot/efi/ /mnt/backup-esp/
```

---

See `REFERENCE.md` for the complete config reference, all
topology options, and advanced VM testing instructions.
