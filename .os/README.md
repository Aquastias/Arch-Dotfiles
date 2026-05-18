# Arch Linux ZFS Installer

A fully scripted, config-driven Arch Linux installer with ZFS as the
root filesystem. Supports single-disk laptops, multi-disk RAID
desktops, optional encryption, custom packages, KDE desktop,
automated backups, and system hardening.

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Quick Start](#2-quick-start)
3. [Secrets Management (SOPS)](#3-secrets-management-sops)
4. [File Layout](#4-file-layout)
5. [Common Configurations](#5-common-configurations)
6. [Optional Components](#6-optional-components)
7. [VM Testing](#7-vm-testing)
8. [After Installation](#8-after-installation)

---

## 1. Architecture

```
install.sh                  Entry point. Runs phases in order.
│
├─ 01-bootstrap-zfs.sh      Add archzfs repo, install ZFS DKMS.
├─ 02-wipe.sh               Tear down LVM/RAID/ZFS, zero disks.
└─ 03-install.sh            Thin orchestrator. Sources lib/.
    │
    ├─ lib/config.sh        Load install.jsonc, validate.
    │                       Detect mode (single | multi).
    ├─ lib/layout-single.sh ESP + rpool + optional dpool.
    ├─ lib/layout-multi.sh  ESP per disk, rpool topology,
    │                       storage_groups (mirror/stripe/raidz).
    ├─ lib/packages.sh      Collect packages, pacstrap base.
    ├─ lib/chroot.sh        Stage scripts, run arch-chroot.
    │   └─ lib/chroot/      Runs inside chroot (see below).
    ├─ lib/profiles.sh      Create users, bootstrap paru,
    │                       install programs.
    └─ lib/finalize.sh      Unmount ESPs, zpool export.
```

Scripts inside `lib/chroot/`:

- `configure.sh` — sub-script orchestrator
- `identity.sh` — locale, timezone, hostname, mkinitcpio.conf
- `initcpio.sh` — ZFS hooks, `mkinitcpio -P`
- `bootloader-systemd-boot.sh` — selected by `options.bootloader`
- `bootloader-grub.sh` — selected by `options.bootloader`
- `password.sh` — root password
- `extras.sh` — `post_install` flags → `extras/` scripts

### Multi-disk ESP mirroring

Each OS disk gets its own ESP. A pacman hook
(`95-esp-mirror.hook`) rsyncs the primary ESP to secondaries
after every kernel update. Each secondary is also registered as
an independent UEFI boot entry via `efibootmgr`, so any OS disk
can boot the machine standalone.

---

## 2. Quick Start

### 2.1 Boot the Arch ISO

Download the latest ISO from
[archlinux.org/download](https://archlinux.org/download/) and
boot in UEFI mode.

### 2.2 Connect to the internet

**Ethernet** — works automatically via DHCP.

**Wi-Fi:**

```bash
iwctl
device list
station wlan0 connect "Your Network"
exit
```

### 2.3 Copy the scripts to the live environment

**From a USB stick:**

```bash
mount /dev/sdX1 /mnt/usb
cp -r /mnt/usb/arch-zfs-installer/* /root/
```

**From a URL (if you have network):**

```bash
curl -LO https://your-host/arch-zfs-installer.tar.gz
tar -xzf arch-zfs-installer.tar.gz
cd arch-zfs-installer
```

### 2.4 Edit the configs

```bash
vim install.jsonc                     # disk, ZFS, locale, host
vim hosts/<hostname>/config.jsonc     # system programs (optional)
vim users/<username>/config.jsonc     # shell, sudo, user progs
```

See the examples inside the files and `REFERENCE.md` for all
options.

### 2.5 Install

```bash
chmod +x install.sh
./install.sh
```

`install.sh` runs the three numbered scripts in order —
bootstrap, wipe, then install — confirming destructive steps as
it goes. Each numbered script is also individually runnable for
debugging.

### 2.6 Reboot

```bash
reboot
```

Remove the installation media when prompted.

---

## 3. Secrets Management (SOPS)

Secrets are optional. Without any `secrets.json` files the
installer works exactly as before — user passwords default to
`12345` (changed on first login) and no SSH identity is
deployed.

### 3.1 Prerequisites (operator machine)

```bash
pacman -S age sops        # or: brew install age sops
```

### 3.2 Generate your age key

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

### 3.3 Copy the key to your install USB

The installer scans removable devices for a file at
`/age/key.age`:

```bash
mount /dev/sdX1 /mnt/usb
mkdir -p /mnt/usb/age
cp age-key.age /mnt/usb/age/key.age
```

### 3.4 Configure `.sops.yaml`

Create `.sops.yaml` at the repo root, listing your age public
key as recipient:

```yaml
creation_rules:
  - path_regex: .os/(users|hosts)/.*secrets.json$
    age: "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Replace the `age1...` value with the public key printed in
step 3.2.

### 3.5 Create secrets files

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

### 3.6 Install

Plug in the USB carrying `age-key.age` **before** running
`./install.sh`. The Secrets Module finds the key, prompts for
its passphrase, decrypts secrets, and proceeds.

At the end of the install, the machine's age public key is
printed:

```
==> Machine age public key: age1yyyyyy...
==> Add it to .sops.yaml and run:
==>   sops updatekeys .os/users/*/secrets.json \
==>                   .os/hosts/*/secrets.json
```

### 3.7 Add the machine key and re-encrypt

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

After this commit, the runtime SOPS service on the machine can
decrypt secrets on every boot without the USB.

---

## 4. File Layout

```
.os/
├── install.sh              # Entry. Runs 01 → 02 → 03.
├── 01-bootstrap-zfs.sh     # ZFS DKMS on the live ISO
├── 02-wipe.sh              # Wipe disks (dd + wipefs + sgdisk)
├── 03-install.sh           # Partition, pacstrap, configure
├── install.jsonc           # Primary config (disk, ZFS, locale)
│
├── lib/                    # Installer modules
│   ├── common.sh           # Colors, output, JSON helpers
│   ├── config.sh           # Config loading and validation
│   ├── configs.sh          # Host/user config merging
│   ├── zfs-pools.sh        # Pool/dataset primitives
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
│   │   ├── extras.sh
│   │   └── impermanence.sh   # Rollback datasets + persist mounts
│   ├── profiles.sh         # Users + program installation
│   ├── finalize.sh         # Unmount + pool export
│   ├── iso-resolver.sh     # Arch ISO version selection
│   ├── seed-generator.sh   # Cloud-init seed for VM tests
│   ├── sentinel-watcher.sh # Log sentinel for VM tests
│   ├── shell-stdlib.sh     # Shared install.sh helpers
│   ├── run-program.sh      # Program installation wrapper
│   └── impermanence-common.sh # Shared by chroot module + runtime tool
│
├── hosts/                  # Per-hostname config
│   ├── core/               # Shared base for all hosts
│   └── <hostname>/         # Host-specific overrides
│
├── users/                  # Per-user config
│   ├── core/               # Shared base for all users
│   └── <username>/         # User-specific overrides
│
├── programs/               # Self-contained installers
│   ├── bootloader/grub/
│   ├── communication/      # TeamSpeak3
│   ├── privacy/            # SearXNG
│   ├── security/           # Firewalld, AppArmor, ClamAV, ...
│   └── virtualization/     # Docker, virt-manager
│
├── extras/                 # Optional post-install scripts
│   ├── desktop/kde/kde.sh  # KDE Plasma 6 + SDDM
│   ├── backup.sh           # ZFS snapshots + Borg backups
│   └── security.sh         # UFW + ClamAV weekly scans
│
├── tools/                  # Operator utilities
│   ├── save-pkglist.sh     # Snapshot current packages
│   ├── install-pkglist.sh  # Restore packages from txt
│   └── impermanence.sh     # Runtime add/remove/status/apply-defaults
│
├── tests/                  # BATS + VM integration tests
│   ├── run.sh              # Test runner
│   ├── shellcheck.sh       # Code quality checks
│   ├── *.bats              # Unit test files
│   └── vm/                 # Disposable VM tests
│
├── vm/                     # Persistent reusable VMs
│   ├── _harness.sh
│   ├── vm-kde.sh           # KDE Plasma + SDDM
│   ├── vm-hyprland.sh      # Hyprland + greetd
│   └── vm-kde-hyprland.sh  # KDE + Hyprland (SDDM)
│
├── README.md               # This file
└── REFERENCE.md            # Full config + VM testing
```

---

## 5. Common Configurations

### 5.1 Laptop (single disk)

```json
"mode":    "single",
"disk":    "/dev/nvme0n1",
"ashift":  13,
"os_size": "auto"
```

### 5.2 Desktop (2 NVMes mirrored + 3 SSDs storage)

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

### 5.3 Desktop (2 NVMes, pick one for OS)

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

## 6. Optional Components

Enable in `install.jsonc` under `post_install`:

| Key                | Script                      | What it does          |
| ------------------ | --------------------------- | --------------------- |
| `"kde": true`      | `extras/desktop/kde/kde.sh` | KDE Plasma 6, SDDM,   |
|                    |                             | PipeWire, Bluetooth,  |
|                    |                             | printing              |
| `"backup": true`   | `extras/backup.sh`          | ZFS auto-snapshots +  |
|                    |                             | Borg/Vorta encrypted  |
|                    |                             | backups               |
| `"security": true` | `extras/security.sh`        | UFW (deny-all-in) +   |
|                    |                             | ClamAV weekly scans   |

Enable in `install.jsonc` under `options`:

| Key                    | Module               | What it does            |
| ---------------------- | -------------------- | ----------------------- |
| `impermanence.enabled` | `lib/chroot/`        | ZFS rollback to `@blank`|
|                        | `impermanence.sh`    | on every boot. See      |
|                        |                      | `REFERENCE.md`.         |

---

## 7. VM Testing

The `tests/vm/` directory contains a disposable integration
test harness built on `libvirt` + cloud-init. Each test script
spins up a throwaway VM, runs the installer unattended, and
exits with the installer's exit code.

> For **persistent, reusable VMs** (manual testing / dev), see
> [`vm/`](vm/).

**Prerequisites:** `virt-install`, `virsh`, `cloud-localds`,
`jq`, `libvirtd` running, user in `libvirt` group.

```bash
# Single-disk smoke test
bash tests/vm/testing-single-disk.sh

# Multi-disk mirror
bash tests/vm/testing-multi-os-mirror.sh

# Multi-disk mirror OS + raidz1 storage
bash tests/vm/testing-multi-os-mirror-storage.sh
```

Each script writes a timestamped log to
`tests/vm/<vm-name>.log`. The harness watches for an
`===INSTALLER-EXIT-N===` sentinel line (written by cloud-init)
and propagates the installer's exit code. Timeout defaults to
1800 s (`VM_TEST_TIMEOUT` env var overrides).

The ISO is auto-resolved to the newest archzfs-compatible Arch
release (cached in `tests/vm/.vm-test/`).

---

## 8. After Installation

### 8.1 First boot checklist

1. Verify ZFS pools: `zpool status`
2. Check datasets mounted: `zfs list`
3. Verify swap: `swapon --show`
4. Set up networking if needed: `nmtui`
5. Update the system: `sudo pacman -Syu`
6. If impermanence is enabled, run `bash tools/impermanence.sh
   status` to confirm `@blank` snapshots exist on every Rollback
   Dataset. Missing snapshots fail-close on the next reboot.

### 8.2 If ZFS fails to import on boot

Boot from the live ISO, run `01-bootstrap-zfs.sh` again, then:

```bash
zpool import -f rpool
zpool import -f dpool
```

### 8.3 ESP backup (single-disk, no RAID)

```bash
sudo rsync -a /boot/efi/ /mnt/backup-esp/
```

---

See `REFERENCE.md` for the complete config reference, all
topology options, and advanced VM testing instructions.
