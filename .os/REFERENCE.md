# Arch Linux ZFS Installer — Reference

Complete configuration reference, concept explanations, and VM testing guide.

---

## Table of Contents

1. [Concepts](#concepts)
2. [install.jsonc Reference](#installjsonc-reference)
3. [install.template.jsonc Reference](#installtemplatejsonc-reference)
4. [Disk Layout Modes](#disk-layout-modes)
5. [Topology Options](#topology-options)
6. [OS Partition Sizing (single-disk)](#os-partition-sizing-single-disk)
7. [Custom Packages](#custom-packages)
8. [Post-Install Components](#post-install-components)
9. [Impermanence](#impermanence)
10. [Testing in Virtual Machines (virt-manager)](#testing-in-virtual-machines)
11. [Troubleshooting](#troubleshooting)

---

## Concepts

### Why ZFS?

ZFS is a combined filesystem and volume manager with features not
available in ext4/btrfs:

- **Copy-on-write** — data is never overwritten in place;
  consistent state on power loss
- **Checksumming** — every block is checksummed; silent data
  corruption is detected and (with RAID) repaired automatically
- **Snapshots** — instant, space-efficient snapshots of any dataset;
  rollback in seconds
- **Compression** — transparent LZ4 compression is on by default;
  typically saves 20–40% space with near-zero CPU cost
- **RAID-Z** — software RAID built into the filesystem;
  no separate mdadm layer needed
- **Native encryption** — AES-256-GCM per-pool or per-dataset

### ZFS Terminology

| Term | Meaning |
|---|---|
| **pool** | Top-level storage container spanning one or more physical devices |
| **vdev** | Virtual device — a disk, mirror set, or RAID-Z group |
| **dataset** | A mountable filesystem inside a pool (e.g. `rpool/home`) |
| **zvol** | A block device inside a pool (used for swap here) |
| **ashift** | Log₂ sector size. 12 = 4096B (SSD/HDD), 13 = 8192B (NVMe) |
| **rpool** | Conventional name for the root/OS pool |
| **dpool** | Conventional name for the data/storage pool |

### Pool Topology

A pool is built from one or more **vdevs**. The vdev type determines redundancy:

- **Single disk** — no redundancy, full capacity
- **Mirror** — 2+ disks, all identical copies; survives N-1 failures
- **Stripe** — 2+ disks treated as one; no redundancy, full combined capacity
- **RAID-Z1** — 3+ disks, 1 parity; survives 1 disk failure; N-1 usable disks
- **RAID-Z2** — 4+ disks, 2 parity; survives 2 disk failures; N-2 usable disks
- **Independent** — each disk is its own single-disk vdev in the pool;
  no RAID across them

### ESP Mirroring

When multiple OS disks are used, each gets its own EFI System
Partition (FAT32). A pacman hook
(`/etc/pacman.d/hooks/95-esp-mirror.hook`) rsyncs the primary ESP to
all secondaries after every kernel or bootloader update. Each
secondary is also registered as a UEFI boot entry via `efibootmgr`,
so the machine can boot from any OS disk independently if another
fails.

---

## install.jsonc Reference

### Top-level fields

| Field | Type | Default | Description |
|---|---|---|---|
| `dotfiles_repo` | string | `""` | Cloned to `~/.dotfiles`, stowed |

The disk-layout fields (`mode`, `disk`, `ashift`, `os_size`,
`os_pool_name`, `storage_pool_name`, `storage_mount`, `os_pool`,
`storage_groups`) also live at top level — see § Disk Layout Modes.

### `system`

| Field | Type | Default | Description |
|---|---|---|---|
| `hostname` | string | `""` | Machine hostname. `""` = prompted |
| `locale` | string | `"en_US.UTF-8"` | System locale |
| `timezone` | string | `"UTC"` | Timezone path under `/usr/share/zoneinfo/` |
| `keymap` | string | `"us"` | Console keymap (see `localectl list-keymaps`) |

Users are not declared here — they live in
`hosts/<hostname>/config.jsonc` (`users` array) with one
`users/<username>/config.jsonc` each.

### `options`

| Field | Type | Default | Description |
|---|---|---|---|
| `kernel` | string | `"lts"` | `"lts"` (linux-lts) or `"default"` (linux) |
| `bootloader` | string | `"systemd-boot"` | `"systemd-boot"` or `"grub"` |
| `encryption` | bool | `false` | ZFS AES-256-GCM on all pools |
| `swap` | bool | `true` | Create a swap zvol on rpool |
| `swap_size` | string | `"auto"` | `"auto"` = RAM×2. Or `"8G"`, `"16G"` |
| `esp_size` | string | `"512M"` | EFI partition size per OS disk |
| `age_key_url` | string | `""` | HTTPS URL for `.age` key (live-CD fallback) |
| `impermanence.enabled` | bool | `false` | Rollback to `@blank` on every boot |
| `impermanence.dataset` | string | `"rpool/persist"` | Persist dataset name |
| `impermanence.mount` | string | `"/persist"` | Persist mountpoint |

### `environment`

| Field | Type | Default | Description |
|---|---|---|---|
| `desktop` | varies | `null` | `"kde"`, `"hyprland"`, both, or `null` |
| `gpu` | varies | `"auto"` | `"amd"`/`"nvidia"`/`"intel"`/array, or `"auto"` |

Each selected desktop dispatches to
`extras/desktop/<de>/<de>.sh`. Audio (PipeWire) is auto-derived
when any desktop is selected. Display manager is chosen per
adapter: KDE-only or KDE+Hyprland → SDDM; Hyprland-only →
greetd + greetd-tuigreet. GPU `"auto"` resolves all detected
vendors and installs the right driver set (`vulkan-radeon`,
`nvidia-open-dkms` + `envycontrol` for hybrids, `intel-media-
driver` / `libva-intel-driver` by device generation, `mesa`
only for VM GPUs).

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
| `os_size` | string | `"auto"` | OS partition. `"auto"` or fixed `"80G"` |
| `os_pool_name` | string | `"rpool"` | Name for the OS ZFS pool |
| `storage_pool_name` | string | `"dpool"` | Name for the storage ZFS pool |
| `storage_mount` | string | `"/data"` | Mount point for the storage pool |

### `os_pool` (multi-disk)

| Field | Type | Default | Description |
|---|---|---|---|
| `pool_name` | string | — | Name for the OS pool |
| `topology` | str | *(prompted)* | `mirror`, `stripe`, `none` — or prompted |
| `ashift` | int | `13` | Sector size exponent |
| `disks` | array | — | List of disk device paths |

**topology = `"none"`**: The script will ask which disk to install
the OS on. All other disks from this list are automatically added
to `dpool` as the `extra` storage group, with their own topology
prompt.

### `storage_groups` (multi-disk)

Array of storage group objects. Each group becomes a vdev in `dpool`:

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Group identifier (used in dataset name and logs) |
| `mount` | string | — | Mount point, e.g. `"/data/ssd"` |
| `ashift` | int | `12` | Sector size exponent |
| `topology` | str | *(prompted)* | Storage topology. Auto if omitted |
| `disks` | array | — | List of disk device paths in this group |

### `packages`

| Field | Type | Description |
|---|---|---|
| `extra`           | array | Flat list, e.g. `["htop", "firefox"]` |
| `groups.system`    | array | System management and hardware tools |
| `groups.network`  | array | Network utils (networkmanager included) |
| `groups.security`  | array | Security hardening tools |
| `groups.fs`       | array | Filesystem utils (btrfs-progs, xfsprogs, …) |
| `groups.archive`   | array | Archive support (7zip, unrar, zip, ...) |
| `groups.wayland`   | array | Wayland compositor and tools |
| `groups.audio`    | array | Audio (auto-derived from `environment.desktop`) |
| `groups.gpu`      | array | GPU drivers (auto from `environment.gpu`) |
| `groups.fonts`     | array | Fonts and icon themes |
| `groups.terminal`  | array | Terminal emulators and CLI tools |
| `groups.dev`       | array | Development tools and runtimes |
| `groups.media`     | array | Media players, browsers, communication |
| `groups.gaming`    | array | Gaming (steam, lutris, wine) |
| `groups.virt`      | array | Virtualisation (qemu, virt-manager) |
| `groups.misc`      | array | Anything else |

All lists are merged and deduplicated at install time. Use exact
pacman package names. Host-specific package lists (incl. AUR)
live under `hosts/<hostname>/config.jsonc` `packages.repo` /
`packages.aur` — see CONTEXT.md.

### `post_install`

| Field | Type | Default | Description |
|---|---|---|---|
| `backup`   | bool | `false` | Run `extras/backup.sh` if present (operator) |
| `security` | bool | `false` | Run `extras/security.sh` if present (operator) |

> For production backups and hardening, declare the relevant
> programs under `system_programs` in your host config —
> `borg`, `zfs-auto-snapshot`, `ufw`/`firewalld`, `clamav`,
> `apparmor`, `rkhunter`, `sops`. See § Post-Install
> Components.

---

## install.template.jsonc Reference

Read by the **Pre-Install Picker** (`tools/pick.sh`) — see
README § 3. Defines every per-host field the picker copies into
the generated `install.jsonc`. Authored once per host and
committed alongside `hosts/<hostname>/config.jsonc`.

### Schema

A template is the **same shape as `install.jsonc`** except:

- `hostname` is **never** in the template — derived from the
  hosts/ directory basename when the picker writes
  `install.jsonc`.
- `disks` (single-mode) and `os_pool.disks` / `storage_groups[].disks`
  (multi-mode) are **never** in the template — supplied by the
  operator's interactive disk pick.

> **Planned (ADR 0029):** a template may *pin* OS-pool layout via
> `mode` + `os_pool.topology`; the picker then skips its mode prompt
> and honors that topology (disks still picked). Today the picker
> prompts for mode and overrides any layout fields in the template.

Every other field documented in § `install.jsonc Reference`
applies unchanged, at its canonical (nested) path: `mode`,
`ashift`, `os_size`, `options.kernel`, `system.locale`,
`system.timezone`, `system.keymap`, `environment.desktop`,
`environment.gpu`, `options.bootloader`, `options.encryption`,
`options.impermanence.*`, `options.age_key_url`, ZFS pool/dataset
names, `packages.*`, `post_install.*`.

### Merge with `hosts/core/install.template.jsonc`

The template is merged with `hosts/core/install.template.jsonc`
using the same rules as Host Config / Host Core:

- arrays — concat + dedupe
- objects — deep merge
- scalars — host template wins over core

Put cross-host defaults (e.g. `system.locale`, `system.timezone`,
`system.keymap`, `options.kernel`) in core; put machine-specific
fields (e.g. disk topology `mode`, `environment.desktop`,
`options.impermanence.enabled`) in the host template.

### Validation

The picker validates the operator-driven layout
(`picker_validate_layout`) — mode vs disk count — before assembly.
**No further config-shape check** runs at picker time: a malformed
template can still fail at `install.sh` time. Run a VM test
(README § 8) to catch this early.

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
               ├── home                              ├── DATA/extra/disk1
               └── swap                                         └── DATA/ssd
```

---

## Topology Options

### OS pool topologies

| Topology | Min disks | Redundancy | Notes |
|---|---|---|---|
| `mirror` | 2 | Full (1 fail) | Recommended for OS. Half combined capacity |
| `stripe` | 2 | None | Full capacity + speed. 1 disk = total data loss |
| `none` | 1 | None | No vdev grouping. 1 disk for OS; rest in dpool |

### Storage group topologies

| Topology | Min disks | Usable | Survives | Notes |
|---|---|---|---|---|
| `mirror` | 2 | 1× | 1 failure | Best for 2-disk groups |
| `stripe` | 2 | N× | 0 | Speed/capacity, no safety |
| `raidz1` | 3 | N-1 | 1 failure | Recommended for 3–4 disks |
| `raidz2` | 4 | N-2 | 2 failures | Recommended for 5+ disks |
| `independent` | 1 | N× | 0/disk | Each disk own vdev. No redundancy |

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

When `os_size = "auto"`, the installer calculates the OS partition
size as the **maximum** of three values:

```
floor     = 40 GiB              (absolute minimum, avoids cramped installs)
ram-based = RAM_GiB × 2 + 30   (swap zvol + reasonable root headroom)
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
    "system":   ["smartmontools", "lm_sensors"],
    "terminal": ["tmux", "bat", "ripgrep", "fzf", "zsh"],
    "dev":      ["python", "nodejs", "npm", "go"],
    "media":    ["firefox", "vlc", "gimp"]
  }
}
```

All packages must be valid pacman package names. Use
`pacman -Ss <keyword>` on a running Arch system to find package names.

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

For machine-specific lists (incl. AUR), prefer the host config
`packages.repo` / `packages.aur` over `install.jsonc` — see
CONTEXT.md § Host Package List.

---

## Post-Install Components

### Desktop environments — `environment.desktop`

The Environment Runner (`lib/chroot/extras.sh`) dispatches to
`extras/desktop/<de>/<de>.sh` for each entry in
`environment.desktop`. Two adapters ship today.

**KDE Plasma 6 — `extras/desktop/kde/kde.sh`**

- `plasma-meta` — full KDE Plasma 6 desktop
- `sddm` — display manager (graphical login screen)
- PipeWire audio stack (replaces PulseAudio)
- BlueDevil Bluetooth integration
- CUPS printing
- Noto fonts (covers Latin, CJK, emoji)

Enables: `sddm.service`, `bluetooth.service`, `cups.service`.
Per-component toggles live in
`extras/desktop/kde/install-kde.jsonc`.

**Hyprland — `extras/desktop/hyprland/hyprland.sh`**

- `hyprland` — Wayland compositor
- `greetd` + `greetd-tuigreet` — text-mode login
- Default config under `/etc/greetd/config.toml`
- PipeWire audio stack

Enables: `greetd.service`. Per-component toggles in
`extras/desktop/hyprland/install-hyprland.jsonc`.

Selecting both (`"desktop": ["kde","hyprland"]`) installs both
adapters; the KDE adapter wins on display manager (SDDM).

### Backup — `programs/backup/`

Declared as system programs in your host config:

```jsonc
// .os/hosts/<hostname>/config.jsonc
"system_programs": ["zfs-auto-snapshot", "borg"]
```

**`zfs-auto-snapshot`** — hourly / daily / weekly / monthly ZFS
snapshots via systemd timers (24 / 31 / 8 / 12 kept by default).
Tags `rpool/ROOT/arch` and `rpool/home` with
`com.sun:auto-snapshot=true`. Snapshots are browsable under
`.zfs/snapshot/` on each tagged dataset.

**`borg`** — deduplicated, encrypted, compressed backups via
`borgbackup` + a starter `borgmatic` config. Pair with `vorta`
(installed via your user config) for a Qt GUI.

To set up a Borg repo after install:

```bash
borg init --encryption=repokey-blake2 /mnt/backup/borg
borgmatic --verbosity 1
```

The `post_install.backup` flag in `install.jsonc` is a gate for
an operator-supplied `extras/backup.sh` (not shipped with this
repo). Leave it `false` and use the programs above for the
maintained path.

### Security — `programs/security/`

Declared as system programs in your host config:

```jsonc
"system_programs": [
  "ufw", "firewalld", "clamav", "apparmor", "rkhunter", "sops"
]
```

- **`ufw`** — uncomplicated firewall (default deny incoming).
- **`firewalld`** — alternative dynamic firewall (pick one).
- **`clamav`** — antivirus daemon + freshclam definitions +
  weekly scheduled scan of `/home` and `/tmp`.
- **`apparmor`** — mandatory access control profiles.
- **`rkhunter`** — rootkit scanner.
- **`sops`** — SOPS Runtime Service: decrypts secrets to a
  tmpfs at `/run/secrets/` on every boot using the Machine Age
  Key. Required by any other program that reads
  `/run/secrets/<name>`.

The `post_install.security` flag in `install.jsonc` is a gate
for an operator-supplied `extras/security.sh` (not shipped with
this repo). Leave it `false` and use the programs above for the
maintained path.

---

## Impermanence

ZFS dataset rollback to a Blank Snapshot on every boot. When
enabled, `/etc`, `/root`, `/opt`, `/srv`, and `/usr/local` revert
to `@blank` at every boot; anything not on the Persist Dataset
disappears. Curated system-identity files (machine-id, SSH host
keys, Machine Age Key, NetworkManager connections, ...) survive
by virtue of bind mounts from `/persist`. See
[ADR-0008](../docs/adr/0008-impermanence-via-zfs-dataset-rollback.md)
for the design rationale and
[CONTEXT.md](../CONTEXT.md) for the glossary.

### Enable

In `install.jsonc`:

```jsonc
"options": {
  "impermanence": {
    "enabled": true,
    "dataset": "rpool/persist",
    "mount":   "/persist"
  }
}
```

Impermanence is install-time only. Toggling later requires a
re-install.

### Persist Extensions

Declare additional paths in `hosts/<hostname>/config.jsonc` (or
`hosts/core/config.jsonc` for shared paths). Deep-merged across
Host Core and Host Config.

```jsonc
"persist": {
  "directories": ["/etc/wireguard", "/var/lib/myapp"],
  "files":       ["/etc/foo.conf"]
}
```

Directories and files are declared in separate arrays so the
installer emits the correct tmpfiles type without ambiguity.
Absolute paths only; `..` and `~` are rejected.

### Runtime tool — `tools/impermanence.sh`

Four verbs. Host config is the source of truth: `add` and
`remove` edit the host config jsonc first, then apply.

| Verb              | Effect                                                 |
| ----------------- | ------------------------------------------------------ |
| `add <path>`      | Detect dir vs file, append to host config, copy data   |
|                   | to `/persist`, write `.mount` unit + tmpfiles, start.  |
| `remove <path>`   | Reverse `add`: stop mount, remove unit + tmpfiles,     |
|                   | optionally move data back, edit host config.           |
| `status`          | List active `persist-*.mount` units; `zfs diff` each   |
|                   | Rollback Dataset against `@blank`.                     |
| `apply-defaults`  | Regenerate Curated Persist Defaults from the current   |
|                   | installer list. Idempotent.                            |

Examples:

```bash
# Persist a new directory
sudo bash tools/impermanence.sh add /etc/wireguard

# Remove an experiment
sudo bash tools/impermanence.sh remove /etc/wireguard

# Boot-time health check
sudo bash tools/impermanence.sh status

# Pull updated curated list after `git pull`
sudo bash tools/impermanence.sh apply-defaults
```

### Curated Persist Defaults

A fixed list of system-identity paths persisted automatically:
`/etc/machine-id`, `/etc/ssh`, `/etc/secrets`, `/etc/hostname`,
`/etc/locale.conf`, `/etc/vconsole.conf`, `/etc/adjtime`,
`/etc/NetworkManager/system-connections`, `/etc/pacman.d`,
`/var/lib/systemd`, plus the bootstrap pair. The complete list
lives in `lib/impermanence-common.sh` as `CURATED_DIRS` and
`CURATED_FILES`.

The runtime tool refuses to `add` or `remove` curated paths —
they would silently break system identity. To pick up new
entries after `git pull`, run `apply-defaults`. Edits made
directly to unit files under `/usr/lib/systemd/system/` will be
overwritten on the next `apply-defaults`.

---

## Testing in Virtual Machines

Testing the installer in virtual machines before running on real
hardware is strongly recommended. The following instructions use
**virt-manager** with **QEMU/KVM**.

For automated CI-style runs, see the disposable test harness
under `tests/vm/` (cloud-init driven). The instructions below
cover manual virt-manager runs; the reusable VMs under `vm/`
(see `vm/README.md`) automate the same setup for repeated use.

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
| NVMe | `/dev/nvme0n1`, `/dev/nvme1n1`, ... | Add via "NVMe" bus type |

Update `install.jsonc` with the correct device names for your VM.

### Test scenario: single-disk (no RAID)

1. Create one VM with one 40 GiB VirtIO disk (`/dev/vda`)
2. Boot the Arch ISO
3. Inside the VM, copy the scripts (e.g. via shared folder or download)
4. Set `install.jsonc`:

   ```json
   "mode": "single",
   "disk": "/dev/vda",
   "ashift": 12
   ```

5. Run `./install.sh` (bootstrap → wipe → install)
6. Reboot and verify the system boots

### Test scenario: multi-disk with mirror (RAID-1)

1. Create a VM with **two 20 GiB** VirtIO disks (`/dev/vda`, `/dev/vdb`)
2. Set `install.jsonc`:

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
2. Set `install.jsonc`:

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
2. Set `install.jsonc` with `"topology": "none"` in `os_pool`
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

Rather than recreating the VM, just rerun `./install.sh` — the
wipe step is now mandatory and zeroes all disks before
reinstalling. This is much faster than creating new VMs.

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

Device names can shift between boots if disks are added/removed.
Using `/dev/disk/by-id/` paths in the config is more stable for
permanent installs.

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
