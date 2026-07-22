# Arch Linux Installer

A fully scripted, config-driven Arch Linux installer. ZFS is the
default root filesystem, with `btrfs`, `ext4`, and `xfs` selectable
per install via a filesystem-keyed adapter axis (ADR 0040/0043).
Supports single-disk laptops, multi-disk RAID desktops, optional
encryption (ZFS-native AES or dm-crypt/LUKS), declarative host/user
profiles, KDE or Hyprland desktops, SOPS-encrypted secrets, and
optional impermanence (rollback-to-blank on every boot, on the
snapshotting filesystems ZFS and btrfs).

Three front-ends drive one back-end (ADR 0036/0039): `install.sh
--profile <name>` (author a profile, pick disks at install time),
`install.sh <config-file>` (unattended, pre-assembled config), and a
bare `install.sh` **Guided Installer** (an fzf TUI that builds an
install from scratch).

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
install.sh                  Entry point. Front-ends (--profile /
│                           --guided / config-file) → back-end.
│                           Forwards -y/--unattended + a config path.
│
├─ 01-bootstrap-zfs.sh      Add archzfs repo, install ZFS DKMS.
│                           Skipped for a pure non-ZFS install.
├─ 02-wipe.sh               Wipe only the install's target disks.
└─ 03-install.sh            Thin orchestrator. Sources lib/.
    │
    ├─ lib/config/          Config core (schema, load, merge, guided)
    │   ├─ profile.sh       Load profile, closed-schema validate,
    │   │                   assemble the effective config.
    │   ├─ accessors.sh     Schema-driven typed field readers.
    │   ├─ layers.sh        JSONC core+specific merge + program refs.
    │   ├─ validation.sh    Config-contract checks (fs, impermanence,
    │   │                   programs, owners …).
    │   ├─ environment.sh   Resolve environment.desktop / .gpu.
    │   ├─ post-install.sh  Security & Backup Extras resolution.
    │   └─ state.sh…menu.sh Guided Installer Config-State + fzf nav.
    ├─ lib/secrets.sh       Locate operator age key (USB or
    │                       options.age_key_url), decrypt secrets.
    ├─ lib/layout/          Filesystem/mode-keyed layout dispatch
    │   ├─ dispatch.sh      root_adapter_source / data_formatter_source
    │   ├─ core.sh          Phase-ordering seam wrappers.
    │   ├─ zfs/{single,multi,common,plan,data}.sh
    │   ├─ btrfs/{single,multi,data,boot,subvol}.sh
    │   ├─ ext4|xfs/{single,data}.sh
    │   └─ nonzfs/{root,boot,data,plan,devices,datacrypt}.sh
    ├─ lib/zfs/             pools.sh, module.sh, verify.sh,
    │                       pool-owners.sh
    ├─ lib/packages/        list.sh (collect+pacstrap), kernel.sh,
    │                       microcode.sh, iso-resolver.sh
    ├─ lib/boot/            esp-kernel-sync.sh, stray-kernel.sh,
    │                       zswap.sh
    ├─ lib/wipe/            targets.sh, method.sh, execute.sh, …
    ├─ lib/chroot.sh        Write fstab, stage scripts, run
    │   └─ lib/chroot/      arch-chroot. Runs inside chroot (below).
    ├─ lib/profiles/        runner.sh (users + programs + DE),
    │                       program-runner.sh (per-program wrapper)
    └─ lib/finalize.sh      Unmount ESPs, zpool export.
```

Scripts inside `lib/chroot/` (staged into the new root and run by
`configure.sh`):

- `configure.sh`        — sub-script orchestrator
- `identity.sh`         — locale, timezone, keymap, hostname,
                          mkinitcpio.conf
- `initcpio.sh`         — ZFS/encryption hooks, `mkinitcpio -P`
- `base-services.sh`    — NetworkManager, cron, ssh, etc.
- `zfs-import.sh`       — boot-time ZFS import wiring
- `udisks.sh`           — udisks/mount policy
- `bootloader-systemd-boot.sh` — selected by `options.bootloader`
- `bootloader-grub.sh`  — selected by `options.bootloader`
- `password.sh`         — root password (host secrets or prompt)
- `create-user.sh`      — per-user creation (shell, groups,
                          sudo, password, SSH identity)
- `impermanence.sh`     — rollback datasets/subvols, `@blank`,
                          persist mounts, initramfs hook
- `extras-common.sh`    — shared helpers for the extras stage
- `extras.sh`           — Environment Runner: dispatches to
                          `extras/desktop/<de>/<de>.sh`

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
./install.sh                                   # Guided Installer (fzf TUI)
./install.sh --profile <name>                  # interactive (picks disks)
./install.sh --profile <name> -y               # unattended (hostname preset)
./install.sh /path/to/effective.jsonc          # positional config seam
./install.sh --profile <name> --print-config   # validate + print, no install
```

A bare `./install.sh` (no `--profile`, no config file) launches the
**Guided Installer** — an fzf menu that authors the whole machine
interactively and assembles the effective config from your choices
(ADR 0039). Use it for ad-hoc installs when no profile exists yet.

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
│   ├── jsonc.sh            # JSONC parser
│   ├── install-state.sh    # install-state.json read/write
│   ├── secrets.sh          # Age key + SOPS decryption
│   ├── picker.sh           # Disk enumeration + group assignment
│   ├── live-medium.sh      # Live-medium detector (shared)
│   ├── prompt.sh           # Interactive prompt helpers
│   ├── finalize.sh         # Unmount + pool export
│   ├── guided*.sh          # Guided Installer entry/controller/save
│   ├── config/             # Schema, load, merge, validation, guided
│   ├── layout/             # fs/mode-keyed dispatch (zfs/btrfs/ext4/
│   │                       #   xfs/nonzfs) + core.sh + dispatch.sh
│   │                       #   + data-pools.sh (standalone pools)
│   ├── zfs/                # pools, module guard, verify, pool-owners
│   ├── packages/           # list (collect+pacstrap), kernel,
│   │                       #   microcode, iso-resolver
│   ├── boot/               # esp-kernel-sync, stray-kernel, zswap
│   ├── wipe/               # targets, method, execute, progress
│   ├── profiles/           # runner + program-runner
│   ├── matrix/             # Combination Matrix test harness
│   │                       #   (assemble/cells/pairwise/synth/run)
│   ├── chroot.sh           # Stage scripts, run arch-chroot
│   ├── chroot/             # Scripts run inside the chroot
│   ├── shell-stdlib.sh     # Facade over lib/shell/*
│   ├── shell/              # Stdlib submodules
│   └── impermanence-common.sh  # Shared by chroot module +
│                               # runtime tool
│
├── hosts/                  # Per-machine profiles
│   ├── core/               # Shared base for all hosts
│   ├── desktop/            # eterniox
│   ├── laptop/
│   └── vm/                 # arch-kde, arch-hyprland, arch-secure, …
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
│   ├── office/
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
│   ├── impermanence.sh     # add/remove/status/apply-defaults
│   ├── fetch-iso.sh        # Download + verify archzfs ISO
│   ├── generate-configs.sh # Materialize per-user stow tree
│   ├── harden-boot.sh      # Boot-path hardening
│   ├── guided-preview.sh   # Live-fzf render harness
│   ├── guided-fzf-smoke.py # Headless fzf-render smoke helper
│   └── matrix.sh           # Combination Matrix runner (ADR 0046)
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
│   ├── lib/                # core.sh + flow-{persistent,test,guided}
│   │                       #   + seed/sentinel/console + verifiers
│   ├── profiles/           # Persistent VM Profiles (desktop/, headless/)
│   └── fixtures/           # Staged install fixtures (e.g. key.age)
│
├── README.md               # This file
└── REFERENCE.md            # Full config + VM testing
```

---

## 6. Common Configurations

Profiles declare the pool **skeleton** — each group's `disk_count`,
never device paths. `install.sh --profile` slices operator-picked
disks onto the groups in declared order (ADR 0036/0037). See
`REFERENCE.md` § Profile Layout Examples for the full skeletons.

### 6.1 Laptop (single disk)

```jsonc
"mode":   "single",
"ashift": 13
// filesystem defaults to "zfs"; add "filesystem": "btrfs" etc. to switch
```

### 6.2 Desktop (2 NVMes mirrored + 3 SSDs storage)

```jsonc
"mode": "multi",
"os_pool": {
  "pool_name":  "rpool",
  "topology":   "mirror",
  "ashift":     13,
  "disk_count": 2
},
"storage_groups": [
  { "name": "ssd", "mount": "/data/ssd", "ashift": 12,
    "topology": "raidz1", "disk_count": 3 }
]
```

### 6.3 Desktop (2 NVMes, pick one for OS)

```jsonc
"mode": "multi",
"os_pool": { "pool_name": "rpool", "topology": "none", "disk_count": 2 }
```

With OS topology `none` you're asked at install which picked disk is
the OS disk; each leftover folds into `dpool` (or becomes its own
Standalone Data Pool — see REFERENCE.md).

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

Hardening and backup tools are declared as **Security & Backup
Extras** — structured `post_install` objects in the host profile
(ADR 0041), not booleans and not `extras/` scripts. They are
paru-based user programs (paru refuses root), so the Runner unions
them into the **Primary User's** paru pass:

```jsonc
// .os/hosts/<name>/profile.jsonc
"post_install": {
  "security": {
    "firewall": "firewalld",   // "firewalld" | "ufw" | null (pick one)
    "clamav":   true,          // antivirus
    "rkhunter": true,          // rootkit scanner
    "apparmor": true           // mandatory access control
  },
  "backup": {
    "zfs-auto-snapshot": true,
    "borg":              true
  }
}
```

Each tool's existing Program Install Script runs unchanged. A host
with no users cannot carry these — the Guided Installer aborts at
the terminal action. (`sops` is separate — it is *secrets-activated*,
not declared: the Runner installs it only when a `secrets.json`
ships. See ADR 0025.)

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

# Filesystems (btrfs / ext4 / xfs roots, plain + encrypted)
bash vm/vm.sh --testing --profile single/btrfs
bash vm/vm.sh --testing --profile single/btrfs-raid1
bash vm/vm.sh --testing --profile single/ext4-plain
bash vm/vm.sh --testing --profile single/xfs

# Impermanence / encryption / SOPS (ZFS + btrfs)
bash vm/vm.sh --testing --profile impermanence/single
bash vm/vm.sh --testing --profile impermanence/mirror
bash vm/vm.sh --testing --profile impermanence/btrfs
bash vm/vm.sh --testing --profile impermanence/kde-encrypted
bash vm/vm.sh --testing --profile impermanence/kde-sops

# Guided Installer (headless replay)
bash vm/vm.sh --testing --profile single/guided
bash vm/vm.sh --testing --profile single/guided-multi

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

### Combination Matrix (`tools/matrix.sh`)

Two-tier "no menu combo errors on install" testing over the config
axes derived from the menu (ADR 0046). Tier-1 is a no-VM exhaustive
storage sweep (assemble + validate, always-on bats); Tier-2 runs a
pairwise-reduced + pinned set of cells as real VM installs through the
positional config seam. `matrix.sh` mirrors `vm.sh` with three
subcommands over a generated cell manifest:

```bash
bash tools/matrix.sh gen              # emit the cell manifest
bash tools/matrix.sh emit <cell-id>   # materialize one cell → VM Profile
bash tools/matrix.sh run              # install cell(s) in a VM
```

Generator/adapter logic lives in `lib/matrix/` so it is unit-testable
without the driver. Re-run `matrix.sh gen` and commit after any menu
change (a drift-guard bats fails otherwise).

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
