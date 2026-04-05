# Arch Linux ZFS Installer — Reference

Complete configuration reference, concept explanations, and VM testing guide.

---

## Table of Contents

1. [Concepts](#concepts)
2. [install.json Reference](#installjson-reference)
3. [Disk Layout Modes](#disk-layout-modes)
4. [Topology Options](#topology-options)
5. [OS Partition Sizing (single-disk)](#os-partition-sizing-single-disk)
6. [Custom Packages](#custom-packages)
7. [Post-Install Components](#post-install-components)
8. [Testing in Virtual Machines (virt-manager)](#testing-in-virtual-machines)
9. [Troubleshooting](#troubleshooting)

---

## Concepts

### Why ZFS?

ZFS is a combined filesystem and volume manager with features not available in ext4/btrfs:

- **Copy-on-write** — data is never overwritten in place; consistent state on power loss
- **Checksumming** — every block is checksummed; silent data corruption is detected and (with RAID) repaired automatically
- **Snapshots** — instant, space-efficient snapshots of any dataset; rollback in seconds
- **Compression** — transparent LZ4 compression is on by default; typically saves 20–40% space with near-zero CPU cost
- **RAID-Z** — software RAID built into the filesystem; no separate mdadm layer needed
- **Native encryption** — AES-256-GCM per-pool or per-dataset

### ZFS Terminology

| Term | Meaning |
|---|---|
| **pool** | Top-level storage container spanning one or more physical devices |
| **vdev** | Virtual device — a disk, mirror set, or RAID-Z group within a pool |
| **dataset** | A mountable filesystem inside a pool (e.g. `rpool/home`) |
| **zvol** | A block device inside a pool (used for swap here) |
| **ashift** | Log₂ of the physical sector size. 12 = 4096 bytes (SSD/HDD), 13 = 8192 bytes (some NVMe) |
| **rpool** | Conventional name for the root/OS pool |
| **dpool** | Conventional name for the data/storage pool |

### Pool Topology

A pool is built from one or more **vdevs**. The vdev type determines redundancy:

- **Single disk** — no redundancy, full capacity
- **Mirror** — 2+ disks, all identical copies; survives N-1 failures
- **Stripe** — 2+ disks treated as one; no redundancy, full combined capacity
- **RAID-Z1** — 3+ disks, 1 parity; survives 1 disk failure; N-1 usable disks
- **RAID-Z2** — 4+ disks, 2 parity; survives 2 disk failures; N-2 usable disks
- **Independent** — each disk is its own single-disk vdev in the pool; no RAID across them

### ESP Mirroring

When multiple OS disks are used, each gets its own EFI System Partition (FAT32). A pacman hook (`/etc/pacman.d/hooks/95-esp-mirror.hook`) rsyncs the primary ESP to all secondaries after every kernel or bootloader update. Each secondary is also registered as a UEFI boot entry via `efibootmgr`, so the machine can boot from any OS disk independently if another fails.

---

## install.json Reference

### `system`

| Field | Type | Default | Description |
|---|---|---|---|
| `hostname` | string | `"archzfs"` | Machine hostname |
| `username` | string | `"user"` | Primary non-root user |
| `locale` | string | `"en_US.UTF-8"` | System locale |
| `timezone` | string | `"UTC"` | Timezone path under `/usr/share/zoneinfo/` |
| `keymap` | string | `"us"` | Console keymap (see `localectl list-keymaps`) |

### `options`

| Field | Type | Default | Description |
|---|---|---|---|
| `encryption` | bool | `false` | ZFS native AES-256-GCM encryption on all pools |
| `swap` | bool | `true` | Create a swap zvol on rpool |
| `swap_size` | string | `"auto"` | Swap size. `"auto"` = RAM×2. Or fixed: `"8G"`, `"16G"` |
| `esp_size` | string | `"512M"` | EFI partition size per OS disk |

### `mode`

| Value | Behaviour |
|---|---|
| `"single"` | One disk, auto-partitioned |
| `"multi"` | Multi-disk with separate OS pool and storage groups |
| *(omitted)* | Auto-detected from which keys are present |

### Single-disk fields

Used when `mode = "single"`:

| Field | Type | Default | Description |
|---|---|---|---|
| `disk` | string | — | Target disk device path, e.g. `"/dev/nvme0n1"` |
| `ashift` | int | `12` | Sector size exponent (12=4K, 13=8K) |
| `os_size` | string | `"auto"` | OS partition size. `"auto"` or fixed e.g. `"80G"` |
| `os_pool_name` | string | `"rpool"` | Name for the OS ZFS pool |
| `storage_pool_name` | string | `"dpool"` | Name for the storage ZFS pool |
| `storage_mount` | string | `"/data"` | Mount point for the storage pool |

### `os_pool` (multi-disk)

| Field | Type | Default | Description |
|---|---|---|---|
| `pool_name` | string | — | Name for the OS pool |
| `topology` | string | *(prompted)* | `mirror`, `stripe`, or `none`. Omit to be prompted. |
| `ashift` | int | `13` | Sector size exponent |
| `disks` | array | — | List of disk device paths |

**topology = `"none"`**: The script will ask which disk to install the OS on. All other disks from this list are automatically added to `dpool` as the `extra` storage group, with their own topology prompt.

### `storage_groups` (multi-disk)

Array of storage group objects. Each group becomes a vdev in `dpool`:

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Group identifier (used in dataset name and logs) |
| `mount` | string | — | Mount point, e.g. `"/data/ssd"` |
| `ashift` | int | `12` | Sector size exponent |
| `topology` | string | *(prompted)* | Storage topology. Omit to be auto-suggested and prompted. |
| `disks` | array | — | List of disk device paths in this group |

### `packages`

| Field | Type | Description |
|---|---|---|
| `extra` | array | Flat list of any pacman packages, e.g. `["htop", "firefox"]` |
| `groups.cli` | array | CLI tools, e.g. `["tmux", "zsh", "fzf"]` |
| `groups.dev` | array | Development tools, e.g. `["python", "nodejs", "docker"]` |
| `groups.gui` | array | GUI applications, e.g. `["firefox", "vlc", "gimp"]` |

All lists are merged and deduplicated at install time. Use exact pacman package names.

### `post_install`

| Field | Type | Default | Description |
|---|---|---|---|
| `kde` | bool | `false` | Run `extras/kde.sh` — KDE Plasma 6 + SDDM |
| `backup` | bool | `false` | Run `extras/backup.sh` — ZFS snapshots + Borg |
| `security` | bool | `false` | Run `extras/security.sh` — UFW + ClamAV |

---

## Disk Layout Modes

### Single-disk mode

```
/dev/sda
├── p1  [ESP  512M ]  → /boot/efi   (FAT32, systemd-boot)
├── p2  [rpool Xg  ]  → /           (ZFS: /, /home, /var, swap)
└── p3  [dpool rest]  → /data        (ZFS: storage)
```

### Multi-disk mode — mirror

```
/dev/nvme0n1                 /dev/nvme1n1
├── p1 [ESP] → /boot/efi     ├── p1 [ESP] → /boot/efi1  (synced)
└── p2 [ZFS] ──────────────── └── p2 [ZFS]
                 ↓
           rpool (mirror vdev)
           ├── ROOT/arch  → /
           ├── home       → /home
           ├── var        → /var
           └── swap       (zvol)

/dev/sda  /dev/sdb  /dev/sdc
└──────────────────────────── dpool (raidz1 vdev)
                               └── DATA/ssd → /data/ssd
```

### Multi-disk mode — topology=none (no OS RAID)

```
/dev/nvme0n1  (chosen for OS)     /dev/nvme1n1  (leftover → dpool)
├── p1 [ESP] → /boot/efi           └── p1 [ZFS] ─────────────────────┐
└── p2 [ZFS] → rpool (single)                                         │
               ├── ROOT/arch                                    dpool  │
               ├── home                                         ├── DATA/extra/disk1
               └── swap                                         └── DATA/ssd
```

---

## Topology Options

### OS pool topologies

| Topology | Min disks | Redundancy | Notes |
|---|---|---|---|
| `mirror` | 2 | Full (1 failure) | Recommended for OS. Uses half the combined capacity. |
| `stripe` | 2 | None | Full capacity + speed. Single disk failure = total data loss. |
| `none` | 1 | None | No vdev grouping. One disk for OS; others fold into dpool. |

### Storage group topologies

| Topology | Min disks | Usable | Survives | Notes |
|---|---|---|---|---|
| `mirror` | 2 | 1× | 1 failure | Best for 2-disk groups |
| `stripe` | 2 | N× | 0 | Speed/capacity, no safety |
| `raidz1` | 3 | N-1 | 1 failure | Recommended for 3–4 disks |
| `raidz2` | 4 | N-2 | 2 failures | Recommended for 5+ disks |
| `independent` | 1 | N× | 0 per disk | Each disk its own vdev. No cross-disk redundancy but each disk can be managed separately. |

**Auto-suggestion rules** (when topology is omitted):

| Disk count | Recommended topology |
|---|---|
| 1 | independent |
| 2 | mirror |
| 3 | raidz1 |
| 4 | raidz1 or raidz2 |
| 5+ | raidz2 |

---

## OS Partition Sizing (single-disk)

When `os_size = "auto"`, the installer calculates the OS partition size as the **maximum** of three values:

```
floor     = 40 GiB              (absolute minimum, avoids cramped installs)
ram-based = RAM_GiB × 2 + 30   (accommodates swap zvol + reasonable root headroom)
percentage = disk_GiB × 20%    (scales with larger disks)

os_size = max(floor, ram-based, percentage)
```

**Examples:**

| Disk | RAM | floor | ram-based | 20% | Chosen |
|---|---|---|---|---|---|
| 256 GiB | 8 GiB | 40 G | 46 G | 51 G | **51 G** |
| 512 GiB | 16 GiB | 40 G | 62 G | 102 G | **102 G** |
| 1 TiB | 32 GiB | 40 G | 94 G | 204 G | **204 G** |
| 128 GiB | 64 GiB | 40 G | 158 G | 25 G | **158 G** *(RAM-heavy machine)* |

Override with a fixed value to take full control: `"os_size": "80G"`.

---

## Custom Packages

Packages are collected from three sources and deduplicated before pacstrap:

```json
"packages": {
  "extra":  ["htop", "neofetch", "rsync", "wget"],
  "groups": {
    "cli":  ["tmux", "bat", "ripgrep", "fzf", "zsh"],
    "dev":  ["python", "nodejs", "npm", "docker", "go"],
    "gui":  ["firefox", "vlc", "gimp", "thunderbird"]
  }
}
```

All packages must be valid pacman package names. Use `pacman -Ss <keyword>` on a running Arch system to find package names.

**Useful package suggestions:**

| Category | Packages |
|---|---|
| Shells | `zsh` `fish` |
| Terminal tools | `tmux` `screen` `bat` `eza` `fd` `ripgrep` `fzf` `delta` |
| Editors | `neovim` `helix` `emacs-nox` |
| Network | `nmap` `traceroute` `mtr` `iperf3` `wireguard-tools` |
| System | `htop` `btop` `iotop` `lsof` `strace` `perf` |
| Dev | `python` `python-pip` `nodejs` `npm` `go` `rustup` `jdk-openjdk` |
| Containers | `docker` `docker-compose` `podman` |
| GUI browsers | `firefox` `chromium` |
| Media | `vlc` `mpv` `ffmpeg` |

---

## Post-Install Components

### `extras/kde.sh` — KDE Plasma 6

Installs:

- `plasma-meta` — full KDE Plasma 6 desktop
- `sddm` — display manager (graphical login screen)
- `plasma-wayland-session` — Wayland support alongside X11
- PipeWire audio stack (replaces PulseAudio)
- BlueDevil Bluetooth integration
- CUPS printing
- Noto fonts (covers Latin, CJK, emoji)

Enables: `sddm.service`, `bluetooth.service`, `cups.service`

### `extras/backup.sh` — Backup

**Timeshift via zfs-auto-snapshot:**

- Installs `zfs-auto-snapshot` (AUR)
- Enables systemd timers: hourly (24 kept), daily (31), weekly (8), monthly (12)
- Tags `rpool/ROOT/arch` and `rpool/home` with `com.sun:auto-snapshot=true`
- Snapshots are browsable at `.zfs/snapshot/` under each dataset

**Borg + Vorta:**

- `borgbackup` — deduplicated, encrypted, compressed backup engine
- `vorta` — KDE/Qt GUI for managing Borg repositories
- `python-borgmatic` — CLI wrapper for automated Borg jobs
- Writes a starter `~/.config/borgmatic/config.yaml` for the first user

**After install, to set up Borg:**

```bash
# Initialise a local repo
borg init --encryption=repokey-blake2 /mnt/backup/borg

# Run first backup
borgmatic --verbosity 1

# Or open the Vorta GUI
vorta
```

### `extras/security.sh` — Security

**UFW Firewall:**

- Default policy: deny incoming, allow outgoing
- Allows: SSH (rate-limited), mDNS (UDP 5353), DHCP client (UDP 68)
- KDE Connect ports (1714–1764) added if KDE is detected
- Backed by nftables (modern kernel firewall)

**ClamAV:**

- `clamd` daemon + `freshclam` definition updater
- Daily automatic virus definition updates
- Weekly scheduled full scan of `/home` and `/tmp` (Sundays 02:30)
- Results logged to `/var/log/clamav/weekly-scan.log`
- On-access scanning available but disabled by default (high I/O cost)

To enable real-time scanning:

```bash
sudo systemctl enable --now clamav-daemon
```

---

## Testing in Virtual Machines

Testing the installer in virtual machines before running on real hardware is strongly recommended. The following instructions use **virt-manager** with **QEMU/KVM**.

### Prerequisites

Install virt-manager and enable the libvirt daemon on your host:

```bash
# Arch Linux host
sudo pacman -S virt-manager qemu-full libvirt dnsmasq

sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
# Log out and back in for group membership to take effect
```

### Creating a test VM for single-disk install

1. Open virt-manager (`virt-manager` in terminal or app launcher)
2. Click **"New Virtual Machine"**
3. Select **"Local install media (ISO image)"**
4. Browse to the Arch Linux ISO
5. Set memory: **2048 MB** minimum, 4096 MB recommended
6. Set CPUs: **2**
7. Storage:
   - **Uncheck** "Enable storage for this virtual machine"
   - We'll add disks manually in the next step
8. Click **"Customize configuration before install"**, then **Finish**

**Adding virtual disks in the VM details:**

- Click **"Add Hardware"** → **"Storage"**
- Device type: **VirtIO Disk**
- Size: **40 GiB** (for single-disk test) or appropriate size
- Bus type: **VirtIO** (or SATA if you want to test `/dev/sda` style names)
- Repeat to add more disks for multi-disk testing

**Enable UEFI firmware:**

- In VM details, click **"Overview"**
- Firmware: select **"UEFI x86_64: /usr/share/edk2/x64/OVMF_CODE.fd"**
- This is required — the installer uses systemd-boot which needs UEFI

1. Click **"Begin Installation"**

### Disk device names in VMs

| Bus type | Device names | Use for |
|---|---|---|
| VirtIO | `/dev/vda`, `/dev/vdb`, ... | Best performance, use for most tests |
| SATA | `/dev/sda`, `/dev/sdb`, ... | Tests the SATA path in scripts |
| NVMe | `/dev/nvme0n1`, `/dev/nvme1n1`, ... | Add via "NVMe" bus type in virt-manager |

Update `install.json` with the correct device names for your VM.

### Test scenario: single-disk (no RAID)

1. Create one VM with one 40 GiB VirtIO disk (`/dev/vda`)
2. Boot the Arch ISO
3. Inside the VM, copy the scripts (e.g. via shared folder or download)
4. Set `install.json`:

   ```json
   "mode": "single",
   "disk": "/dev/vda",
   "ashift": 12
   ```

5. Run `./01-bootstrap-zfs.sh` then `./03-install.sh`
6. Reboot and verify the system boots

### Test scenario: multi-disk with mirror (RAID-1)

1. Create a VM with **two 20 GiB** VirtIO disks (`/dev/vda`, `/dev/vdb`)
2. Set `install.json`:

   ```json
   "mode": "multi",
   "os_pool": {
     "pool_name": "rpool",
     "topology":  "mirror",
     "ashift":    12,
     "disks":     ["/dev/vda", "/dev/vdb"]
   },
   "storage_groups": []
   ```

3. Run the installer and verify

**Testing mirror failover:**

```bash
# After install, in the running VM:
zpool status rpool        # should show mirror, both disks online

# Simulate a disk failure (detach one vdev)
zpool offline rpool /dev/vdb2

zpool status rpool        # should show DEGRADED, vdb2 OFFLINE

# The system should still boot and work from /dev/vda alone
```

### Test scenario: multi-disk with storage groups

1. Create a VM with **5 disks**: 2 × 10 GiB (OS) + 3 × 8 GiB (storage)
2. Set `install.json`:

   ```json
   "mode": "multi",
   "os_pool": {
     "pool_name": "rpool",
     "topology":  "mirror",
     "ashift":    12,
     "disks":     ["/dev/vda", "/dev/vdb"]
   },
   "storage_groups": [
     { "name": "data", "mount": "/data",
       "ashift": 12, "topology": "raidz1",
       "disks": ["/dev/vdc", "/dev/vdd", "/dev/vde"] }
   ]
   ```

### Test scenario: topology=none (no OS RAID, leftovers to storage)

1. Create a VM with **2 OS disks** + **1 storage disk**
2. Set `install.json` with `"topology": "none"` in `os_pool`
3. During install, select `/dev/vda` as the OS disk
4. Verify `/dev/vdb` is added to dpool as `extra`

### Verifying a successful install

After rebooting into the installed system, run these checks:

```bash
# ZFS pool status — should show all pools ONLINE
zpool status

# Dataset list — all expected mountpoints present
zfs list

# Swap active
swapon --show

# Boot worked from correct pool
cat /proc/cmdline    # should contain root=ZFS=rpool/ROOT/arch

# systemd services
systemctl status zfs-mount zfs-import-cache NetworkManager

# Disk layout
lsblk -f

# ESP contents
ls /boot/efi/
```

### Cleaning up a VM for a fresh test run

Rather than recreating the VM, run `02-wipe.sh` on the booted ISO to zero all disks and start over. This is much faster than creating new VMs.

---

## Troubleshooting

### ZFS module not loading after bootstrap

```bash
# Check if module exists
ls /lib/modules/$(uname -r)/extra/zfs/

# Try loading manually with verbose output
modprobe -v zfs

# If DKMS failed, check build log
dkms status
cat /var/lib/dkms/zfs/*/build/make.log
```

### Pool not importing on first boot

Boot from the live ISO, run `01-bootstrap-zfs.sh`, then:

```bash
# Force import by scanning all devices
zpool import -f rpool
zpool import -f dpool

# If hostid mismatch:
zgenhostid
zpool import -f -o cachefile=/etc/zfs/zpool.cache rpool
```

### Wrong disk device name in config

Run `lsblk` on the live ISO to see current device names:

```bash
lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,TRAN
```

Device names can shift between boots if disks are added/removed. Using `/dev/disk/by-id/` paths in the config is more stable for permanent installs.

### systemd-boot not showing menu

```bash
# Re-install bootloader from live ISO:
mount /dev/nvme0n1p1 /mnt/boot/efi
bootctl --esp-path=/mnt/boot/efi install

# Verify entries exist:
ls /mnt/boot/efi/loader/entries/
```

### Encryption passphrase not accepted on boot

```bash
# Load the key manually:
zfs load-key rpool
zfs mount -a

# Make sure keylocation is correct:
zfs get keylocation rpool
```

### pacstrap fails with GPG errors

```bash
# Refresh keys on the live ISO:
pacman-key --refresh-keys
pacman -Sy archlinux-keyring
```

### KDE does not start after install

```bash
journalctl -b -u sddm    # Check SDDM startup errors
systemctl status sddm
journalctl -b | grep -i "plasma\|kwin\|sddm"
```
