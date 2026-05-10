# Persistent VMs

Scripts that spin up persistent, reusable libvirt VMs with the installer already run. Use these for manual testing, desktop smoke-testing, or dev work — they survive across reboots.

> For **unattended integration tests** (CI / disposable), see [`tests/vm/`](../tests/vm/).

---

## Quick start

**Prerequisites:** `virt-install`, `virsh`, `cloud-localds`, `python3`, `nc`, `jq`, `libvirtd` running, user in `libvirt` group.

```bash
# KDE Plasma (single disk, 60 GiB)
bash vm/vm-kde.sh

# Hyprland (single disk, 40 GiB)
bash vm/vm-hyprland.sh

# KDE + Hyprland side-by-side (single disk, 80 GiB)
bash vm/vm-kde-hyprland.sh
```

Each script: resolves the latest archzfs-compatible Arch ISO → creates the VM → boots the live ISO → types the install command into the console → waits for the installer to finish and power off → restarts into the installed system.

Once it finishes, open virt-manager and connect to the VM. Default credentials: `aquastias / 12345` (or `root / 12345`).

---

## VM flavors

| Script | VM name | Disk | RAM | Desktop |
|---|---|---|---|---|
| `vm-kde.sh` | `arch-kde` | 1 × 60 GiB | 8 GiB | KDE Plasma 6 + SDDM |
| `vm-hyprland.sh` | `arch-hyprland` | 1 × 40 GiB | 6 GiB | Hyprland + greetd/tuigreet |
| `vm-kde-hyprland.sh` | `arch-kde-hyprland` | 1 × 80 GiB | 8 GiB | KDE + Hyprland (SDDM, Hyprland as session) |

---

## Options

```bash
bash vm/vm-kde.sh --recreate   # destroy existing VM and start fresh
bash vm/vm-kde.sh --help
```

`--recreate` destroys the libvirt domain and deletes its qcow2 disks before creating a new one.

---

## Environment overrides

```bash
ISO_URL_OVERRIDE=https://… bash vm/vm-kde.sh   # pin a specific ISO
VM_RAM_MB=16384 bash vm/vm-kde.sh              # more RAM
BOOT_TIMEOUT_SEC=600 bash vm/vm-kde.sh         # slower hardware
INSTALL_TIMEOUT_SEC=7200 bash vm/vm-kde.sh     # longer install timeout
```

---

## How it works

1. Resolves the newest Arch ISO compatible with the archzfs repo (cached in `.vm-cache/`).
2. Builds a minimal cloud-init seed CDROM (only to satisfy cloud-init datasource; no cloud-init config runs).
3. Creates the libvirt domain with UEFI + OVMF and boots it.
4. Polls `virsh domifaddr` until the VM gets a DHCP IP, then waits for SSH port 22 to respond.
5. Starts a temporary HTTP server on the libvirt bridge (`192.168.122.1:9876`) serving the installer script.
6. Types `curl -s http://…/run|bash` into the VGA console via `virsh send-key`.
7. Waits for the VM to power off (installer calls `poweroff` on completion).
8. Restarts the VM — OVMF finds the systemd-boot EFI entry written during install and boots the installed system.
