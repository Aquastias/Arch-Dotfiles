# Persistent VMs

Profile-driven, persistent, reusable libvirt VMs with the installer
already run. Use these for manual testing, desktop smoke-testing, or
dev work — they survive across reboots.

> One entry point, `vm.sh`, drives every flavour from a **VM Profile**
> (a JSONC data file). For **unattended integration tests** (disposable),
> add `--testing`; see [`tests/vm/`](../tests/vm/).

---

## Quick start

**Prerequisites:** `virt-install`, `virsh`, `cloud-localds`, `python3`,
`nc`, `jq`, `libvirtd` running, user in `libvirt` group.

```bash
# KDE Plasma (single disk, 60 GiB)
bash vm/vm.sh --profile desktop/kde

# Hyprland (single disk, 40 GiB)
bash vm/vm.sh --profile desktop/hyprland

# KDE + Hyprland side-by-side (single disk, 80 GiB)
bash vm/vm.sh --profile desktop/kde-hyprland

# Headless mirror with SOPS + impermanence + ZFS encryption
# (2 × 40 GiB). Type `test` at the Age-key passphrase prompt
# when the Secrets Module asks during install.
bash vm/vm.sh --profile headless/secure
```

`vm.sh` validates the profile, resolves the latest archzfs-compatible
Arch ISO → creates the VM → boots the live ISO → types the install
command into the console → waits for the installer to finish and power
off → restarts into the installed system.

Once it finishes, open virt-manager and connect to the VM.
Default credentials: `aquastias / 12345` (or `root / 12345`).

`--print-config` is a dry run: it validates the profile and prints the
resolved `install.jsonc` to stdout without touching libvirt.

---

## VM flavors (profiles under `vm/profiles/`)

| Profile | VM name | Disk | RAM | Desktop |
|---|---|---|---|---|
| `desktop/kde` | `arch-kde` | 1 × 60 GiB | 8 GiB | KDE Plasma 6 + SDDM |
| `desktop/hyprland` | `arch-hyprland` | 1 × 40 GiB | 6 GiB | Hyprland + greetd |
| `desktop/kde-hyprland` | `arch-kde-hyprland` | 1 × 80 GiB | 8 GiB | KDE + Hyprland |
| `headless/secure` | `arch-secure` | 2 × 40 GiB (mirror) | 6 GiB | none (headless) |

Each profile names its install config via one source: a `host_profile`
reference (resolved through the picker's Install Template merge — one
source of truth), an inline `install` block, or `"install": "repo"`.

---

## Options

```bash
bash vm/vm.sh --profile desktop/kde --recreate   # destroy existing VM first
bash vm/vm.sh --profile desktop/kde --print-config  # dry run, no libvirt
bash vm/vm.sh --help
```

`--recreate` destroys the libvirt domain and its own data disks before
creating a fresh one (the shared install ISO + seed cdroms are kept).

---

## Environment overrides

Profile hardware/timeouts are defaults; matching env vars still win:

```bash
ISO_URL_OVERRIDE=https://… bash vm/vm.sh --profile desktop/kde  # pin an ISO
VM_RAM_MB=16384            bash vm/vm.sh --profile desktop/kde   # more RAM
BOOT_TIMEOUT_SEC=600       bash vm/vm.sh --profile desktop/kde   # slow hardware
INSTALL_TIMEOUT_SEC=7200   bash vm/vm.sh --profile desktop/kde   # longer install
```

---

## How it works

1. Validates the profile and resolves its install config to a full
   `install.jsonc`.
2. Resolves the newest archzfs-compatible Arch ISO (cached in
   `vm/.vm-cache/`).
3. Builds a minimal cloud-init seed CDROM (NoCloud datasource only; no
   cloud-init config runs).
4. Creates the libvirt domain with UEFI + OVMF and boots it.
5. Polls `virsh domifaddr` until the VM gets a DHCP IP, then waits for
   SSH port 22.
6. Starts a temporary HTTP server on the libvirt gateway
   (`192.168.122.1:9876`) serving the installer script (and any staged
   `fixtures`, e.g. the secure profile's Age key).
7. Types `curl -s http://…/run|bash` into the console via `virsh send-key`.
8. Waits for poweroff, then restarts — OVMF finds the systemd-boot EFI
   entry written during install and boots the installed system.

All harness code lives under `vm/lib/` (`core.sh`, `flow-persistent.sh`,
`flow-test.sh`); the entry point never depends on a `tests/` path.
