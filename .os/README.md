# Arch Linux ZFS Installer

A fully scripted, config-driven Arch Linux installer with ZFS as the root filesystem. Supports single-disk laptops, multi-disk RAID desktops, optional encryption, custom packages, KDE desktop, automated backups, and system hardening.

---

## Architecture

```
install.sh  (entry point — runs phases in order)
│
├─ 01-bootstrap-zfs.sh ── Add archzfs repo → install ZFS DKMS → load module
│
├─ 02-wipe.sh ─────────── Detect physical disks → teardown (LVM/RAID/ZFS) → dd zero-fill
│
└─ 03-install.sh ─────── (sources lib/ modules, thin orchestrator)
    │
    ├─ lib/config.sh ──── Load install.jsonc → validate → detect mode (single | multi)
    │
    ├─ lib/layout-single.sh   (single disk)
    │   └─ ESP (512 M) + rpool (OS+home+var+swap) + dpool (storage)
    │
    ├─ lib/layout-multi.sh    (N disks)
    │   ├─ rpool  topology: mirror | stripe | none
    │   └─ dpool  storage_groups: mirror | stripe | raidz1 | raidz2
    │
    ├─ lib/packages.sh ─── Collect package lists → pacstrap base system
    │
    ├─ lib/chroot.sh ───── Write install-state.json → stage scripts → arch-chroot
    │   └─ lib/chroot/
    │       ├─ configure.sh            (sub-script orchestrator)
    │       ├─ identity.sh             (locale, timezone, hostname, mkinitcpio.conf)
    │       ├─ initcpio.sh             (ZFS hooks → mkinitcpio -P)
    │       ├─ bootloader-systemd-boot.sh  ─┐ selected by
    │       ├─ bootloader-grub.sh          ─┘ options.bootloader
    │       ├─ password.sh             (root password)
    │       └─ extras.sh               (post_install flags → extras/ scripts)
    │
    ├─ lib/profiles.sh ─── Create users → bootstrap paru → install programs
    │
    └─ lib/finalize.sh ─── Unmount ESPs → zfs umount -a → zpool export
```

### Multi-disk ESP mirroring

Each OS disk gets its own ESP. A pacman hook (`95-esp-mirror.hook`) rsyncs the primary ESP to secondaries after every kernel update. Each secondary is also registered as an independent UEFI boot entry via `efibootmgr`, so any OS disk can boot the machine standalone.

---

## Quick Start

### 1. Boot the Arch ISO

Download the latest ISO from [archlinux.org/download](https://archlinux.org/download/) and boot in UEFI mode.

### 2. Connect to the internet

**Ethernet** — works automatically via DHCP.

**Wi-Fi:**
```bash
iwctl
device list
station wlan0 connect "Your Network"
exit
```

### 3. Copy the scripts to the live environment

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

### 4. Edit the configs

```bash
vim install.jsonc                            # disk layout, ZFS, locale, hostname
vim hosts/<hostname>/config.jsonc            # system programs (optional)
vim users/<username>/config.jsonc            # shell, sudo, user programs (optional)
```

See the examples inside the files and `REFERENCE.md` for all options.

### 5. Install

```bash
chmod +x install.sh
./install.sh
```

`install.sh` runs the three numbered scripts in order — bootstrap, wipe, then install — confirming destructive steps as it goes. Each numbered script is also individually runnable for debugging.

### 6. Reboot

```bash
reboot
```

Remove the installation media when prompted.

---


## Secrets Management (SOPS)

Secrets are optional. Without any `secrets.json` files the installer works exactly as before — user passwords default to `12345` (changed on first login) and no SSH identity is deployed.

### Prerequisites (operator machine)

```bash
pacman -S age sops        # or: brew install age sops
```

### 1. Generate your age key

```bash
age-keygen -o age-key.txt
# Public key is printed to stdout: age1...
# Keep this public key — it goes in .sops.yaml
```

Encrypt the key with a passphrase so it is safe to carry on a USB stick:

```bash
age -p -o age-key.age age-key.txt
rm age-key.txt            # keep only the encrypted copy
```

### 2. Copy the key to your install USB

The installer scans removable devices for a file at `/age/key.age`:

```bash
mount /dev/sdX1 /mnt/usb
mkdir -p /mnt/usb/age
cp age-key.age /mnt/usb/age/key.age
```

### 3. Configure `.sops.yaml`

Create `.sops.yaml` at the repo root, listing your age public key as recipient:

```yaml
creation_rules:
  - path_regex: .os/(users|hosts)/.*secrets.json$
    age: "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Replace the `age1...` value with the public key printed in step 1.

### 4. Create secrets files

```bash
# User secrets
sops .os/users/<username>/secrets.json
```

Add content (values are encrypted on save; keys remain plaintext):

```json
{
    "password": "your-real-password",
    "ssh_identity_private_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n...",
    "ssh_identity_key_type": "ed25519"
}
```

```bash
# Host secrets (root password)
sops .os/hosts/<hostname>/secrets.json
```

```json
{
    "root_password": "your-real-root-password"
}
```

### 5. Install

Plug in the USB carrying `age-key.age` **before** running `./install.sh`. The Secrets Module will find the key, prompt for its passphrase, decrypt secrets, and proceed. At the end of the install, the machine's age public key is printed:

```
==> Machine age public key: age1yyyyyy...
==> Add it to .sops.yaml and run: sops updatekeys .os/users/*/secrets.json .os/hosts/*/secrets.json
```

### 6. Add the machine key and re-encrypt

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
git add .sops.yaml .os/users/<username>/secrets.json .os/hosts/<hostname>/secrets.json
git commit -m "secrets: add machine age key for <hostname>"
```

After this commit, the runtime SOPS service on the machine can decrypt secrets on every boot without the USB.

---


## File Layout

```
.os/
├── install.sh                  # Entry point — runs 01 → 02 → 03
├── 01-bootstrap-zfs.sh         # ZFS DKMS on the live ISO
├── 02-wipe.sh                  # Wipe disks (dd + wipefs + sgdisk)
├── 03-install.sh               # Partition, pacstrap, configure, profiles
├── install.jsonc               # Primary config (disk, ZFS, locale, packages)
│
├── lib/                        # Installer modules
│   ├── common.sh               # Colors, output helpers, JSON helpers (cfg/cfgo)
│   ├── config.sh               # Config loading, validation, mode detection
│   ├── configs.sh              # Host/user config merging
│   ├── zfs-pools.sh            # Pool/dataset creation primitives
│   ├── layout-single.sh        # Single-disk partitioning + pool logic
│   ├── layout-multi.sh         # Multi-disk partitioning + pool logic
│   ├── packages.sh             # Package collection + pacstrap
│   ├── chroot.sh               # Stage chroot scripts + run arch-chroot
│   ├── chroot/                 # Scripts executed inside arch-chroot
│   │   ├── configure.sh        #   Sub-script orchestrator
│   │   ├── identity.sh         #   Locale, timezone, hostname
│   │   ├── initcpio.sh         #   mkinitcpio ZFS hooks
│   │   ├── bootloader-systemd-boot.sh
│   │   ├── bootloader-grub.sh
│   │   ├── password.sh         #   Root password
│   │   └── extras.sh           #   post_install hooks
│   ├── profiles.sh             # User creation + program installation
│   ├── finalize.sh             # Unmount + pool export
│   ├── iso-resolver.sh         # Arch ISO version selection (archzfs-aware)
│   ├── seed-generator.sh       # Cloud-init seed generation for VM tests
│   ├── sentinel-watcher.sh     # Log sentinel detection for VM tests
│   ├── shell-stdlib.sh         # Shared helpers for program install.sh files
│   └── run-program.sh          # Program installation wrapper
│
├── hosts/                      # Host-level config (system programs per hostname)
│   ├── core/                   # Shared base for all hosts
│   └── <hostname>/             # Host-specific overrides
│
├── users/                      # User-level config (user programs per user)
│   ├── core/                   # Shared base for all users
│   └── <username>/             # User-specific overrides
│
├── programs/                   # Self-contained program installers
│   ├── bootloader/grub/        # GRUB installer program
│   ├── communication/          # TeamSpeak3
│   ├── privacy/                # SearXNG
│   ├── security/               # Firewalld, AppArmor, ClamAV, rkhunter, UFW
│   └── virtualization/         # Docker, virt-manager
│
├── extras/                     # Optional post-install scripts
│   ├── desktop/kde/kde.sh      # KDE Plasma 6, SDDM, PipeWire, Bluetooth
│   ├── backup.sh               # ZFS auto-snapshots + Borg encrypted backups
│   └── security.sh             # UFW firewall (deny-all-in) + ClamAV weekly scans
│
├── tests/                      # BATS unit test suite + VM integration tests
│   ├── run.sh                  # Test runner
│   ├── shellcheck.sh           # Code quality checks
│   ├── *.bats                  # Test files (configs, iso-resolver, ...)
│   └── vm/                     # Disposable VM integration tests
│       ├── _harness.sh         #   Shared test infrastructure
│       ├── testing-single-disk.sh          # 1 × 40 GiB SATA
│       ├── testing-multi-os-mirror.sh      # 2 × 40 GiB, rpool mirror
│       ├── testing-multi-os-stripe.sh      # 2 × 40 GiB, rpool stripe
│       ├── testing-multi-os-none.sh        # 2 × 40 GiB, topology=none
│       └── testing-multi-os-mirror-storage.sh  # 2 × 40 GiB OS + 3 × 40 GiB dpool raidz1
│
├── vm/                         # Persistent usable VMs (manual testing / dev)
│   ├── _harness.sh             # Shared infrastructure (ISO pick, libvirt, HTTP)
│   ├── vm-kde.sh               # 1 × 60 GiB, KDE Plasma + SDDM
│   ├── vm-hyprland.sh          # 1 × 40 GiB, Hyprland + greetd
│   └── vm-kde-hyprland.sh      # 1 × 80 GiB, KDE + Hyprland (SDDM)
│
├── README.md                   # This file
└── REFERENCE.md                # Full config reference + VM testing guide
```

---

## Common Configurations

### Laptop (single disk)

```json
"mode":    "single",
"disk":    "/dev/nvme0n1",
"ashift":  13,
"os_size": "auto"
```

### Desktop (2 NVMes mirrored + 3 SSDs storage)

```json
"mode": "multi",
"os_pool": {
  "pool_name": "rpool",
  "topology":  "mirror",
  "ashift":    13,
  "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
},
"storage_groups": [
  { "name": "ssd", "mount": "/data/ssd", "ashift": 12,
    "topology": "raidz1",
    "disks": ["/dev/sda", "/dev/sdb", "/dev/sdc"] }
]
```

### Desktop (2 NVMes, pick one for OS — other goes to storage)

```json
"mode": "multi",
"os_pool": {
  "pool_name": "rpool",
  "topology":  "none",
  "ashift":    13,
  "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
}
```

At runtime you'll be asked which NVMe to install on. The other is automatically added to `dpool`.

---

## Optional Components

Enable in `install.jsonc` under `post_install`:

| Key | Script | What it does |
|---|---|---|
| `"kde": true` | `extras/desktop/kde/kde.sh` | KDE Plasma 6, SDDM, PipeWire, Bluetooth, printing |
| `"backup": true` | `extras/backup.sh` | ZFS auto-snapshots + Borg/Vorta encrypted backups |
| `"security": true` | `extras/security.sh` | UFW firewall (deny-all-in) + ClamAV weekly scans |

---

## VM Testing

The `tests/vm/` directory contains a disposable integration test harness built on `libvirt` + cloud-init. Each test script spins up a throwaway VM, runs the installer unattended, and exits with the installer's exit code.

> For **persistent, reusable VMs** (manual testing / dev), see [`vm/`](vm/).

**Prerequisites:** `virt-install`, `virsh`, `cloud-localds`, `jq`, `libvirtd` running, user in `libvirt` group.

```bash
# Single-disk smoke test
bash tests/vm/testing-single-disk.sh

# Multi-disk mirror
bash tests/vm/testing-multi-os-mirror.sh

# Multi-disk mirror OS + raidz1 storage
bash tests/vm/testing-multi-os-mirror-storage.sh
```

Each script writes a timestamped log to `tests/vm/<vm-name>.log`. The harness watches for an `===INSTALLER-EXIT-N===` sentinel line (written by cloud-init) and propagates the installer's exit code. Timeout defaults to 1800 s (`VM_TEST_TIMEOUT` env var overrides).

The ISO is auto-resolved to the newest archzfs-compatible Arch release (cached in `tests/vm/.vm-test/`).

---

## After Installation

### First boot checklist

1. Verify ZFS pools: `zpool status`
2. Check datasets mounted: `zfs list`
3. Verify swap: `swapon --show`
4. Set up networking if needed: `nmtui`
5. Update the system: `sudo pacman -Syu`

### If ZFS fails to import on boot

Boot from the live ISO, run `01-bootstrap-zfs.sh` again, then:
```bash
zpool import -f rpool
zpool import -f dpool
```

### ESP backup (single-disk, no RAID)

```bash
sudo rsync -a /boot/efi/ /mnt/backup-esp/
```

---

See `REFERENCE.md` for the complete config reference, all topology options, and advanced VM testing instructions.
