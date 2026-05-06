# Arch Linux ZFS Installer

A fully scripted, config-driven Arch Linux installer with ZFS as the root filesystem. Supports single-disk laptops, multi-disk RAID desktops, optional encryption, custom packages, KDE desktop, automated backups, and system hardening.

---

## Quick Start

### 1. Boot the Arch ISO

Download the latest ISO from [archlinux.org/download](https://archlinux.org/download/) and boot it in UEFI mode.

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
vim hosts/<hostname>/config.jsonc            # users + system programs (optional)
vim users/<username>/config.jsonc            # shell, sudo, user programs (optional)
```

See the examples inside the files and `REFERENCE.md` for all options.

### 5. Install

```bash
chmod +x install.sh
./install.sh
```

`install.sh` runs the three numbered scripts in order — bootstrap, wipe, then install — confirming destructive steps as it goes. The numbered scripts (`01-bootstrap-zfs.sh`, `02-wipe.sh`, `03-install.sh`) remain individually runnable for debugging.

### 6. Reboot

```bash
reboot
```

Remove the installation media when prompted.

---

## File Layout

```
arch-zfs-installer/
├── install.sh             # Entry point — runs 01 → 02 → 03 in order
├── 01-bootstrap-zfs.sh    # Bootstrap ZFS on the live ISO
├── 02-wipe.sh             # Wipe all disks
├── 03-install.sh          # Partition, pacstrap, configure, run profiles
├── install.jsonc          # Disk + ZFS + locale config
├── hosts/                 # Host configs (users + system programs per host)
│   └── core/              # Shared base layer for every host
├── users/                 # User configs (shell, sudo, user programs)
│   └── core/              # Shared base layer for every user
├── programs/              # Self-contained programs (config.jsonc + install.sh)
├── lib/                   # Installer modules (configs, profiles, chroot, ...)
├── extras/                # Optional post-install scripts (kde, backup, security)
├── README.md              # This file — quickstart
└── REFERENCE.md           # Full config reference + VM testing guide
```

---

## Common Configurations

### Laptop (single disk)

```json
"mode":   "single",
"disk":   "/dev/nvme0n1",
"ashift": 13,
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

### Desktop (2 NVMes, no RAID — pick one for OS, other goes to storage)

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

Enable in `install.json` under `post_install`:

| Key | Script | What it does |
|---|---|---|
| `"kde": true` | `extras/kde.sh` | KDE Plasma 6, SDDM, PipeWire, Bluetooth, printing |
| `"backup": true` | `extras/backup.sh` | ZFS auto-snapshots + Borg/Vorta encrypted backups |
| `"security": true` | `extras/security.sh` | UFW firewall (deny-all-in) + ClamAV weekly scans |

---

## After Installation

### First boot checklist

1. Log in and verify ZFS pools: `zpool status`
2. Check all datasets mounted: `zfs list`
3. Verify swap: `swapon --show`
4. Set up networking if needed: `nmtui`
5. Update the system: `sudo pacman -Syu`

### If ZFS fails to import on boot

Boot from the live ISO, run bootstrap again, then:
```bash
zpool import -f rpool
zpool import -f dpool
```

### Backing up your ESP (if not using RAID)

```bash
sudo rsync -a /boot/efi/ /mnt/backup-esp/
```

---

See `REFERENCE.md` for the complete config reference, all topology options explained, and VM testing instructions.
