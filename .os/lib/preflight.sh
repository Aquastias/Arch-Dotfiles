#!/usr/bin/env bash
# =============================================================================
# lib/preflight.sh — ensure the installer's host tools exist before any run
# =============================================================================
# The front-ends (guided TUI, --profile disk picker) and the Target Resolver run
# inside install.sh BEFORE 01-bootstrap-zfs.sh, and the numbered phases then
# shell out to the whole partition/format/pacstrap toolchain. This module checks
# every host tool the installer needs up front and pacman-installs any that are
# missing (mirrors lib/secrets.sh's on-demand age/sops install), so the operator
# never hits a bare "fzf: command not found" — or worse, a missing mkfs mid-wipe.
#
# Scope — what is and isn't guarded:
#   • Guarded: the "extra" packages a stripped/custom live medium might omit
#     (jq, fzf, gptfdisk, arch-install-scripts, btrfs-progs, cryptsetup, …).
#   • NOT guarded — the ISO's non-negotiable base (bash/coreutils/util-linux/
#     systemd/gawk/sed/grep/pacman): if any were absent, pacman/bash could not
#     have started this script, so a pacman guard is moot.
#   • NOT guarded — zfs/zpool/zgenhostid: 01-bootstrap-zfs.sh installs zfs-dkms
#     on demand (ADR 0023), and only for a ZFS layout.
#   • NOT guarded — age/sops: lib/secrets.sh installs them contextually, only
#     for encrypted-secrets profiles.
#
# Off a live medium (no pacman) a missing tool is a hard error listing exactly
# what to install — never a cryptic command-not-found. main()-free, so sourcing
# is inert. The pacman call is a seam (_preflight_pacman) so tests can assert the
# resolved package set without root or a network.
# =============================================================================

# The host toolchain the installer shells out to, beyond the ISO base. Entries
# are cmd[:pkg]; pkg defaults to cmd. One representative command per package is
# enough — pacman --needed dedups, and every tool a package ships arrives with
# it. Kept config-independent on purpose: verifying the full toolchain up front
# (even btrfs/luks/raid helpers on a ZFS-only run) is cheap on the official ISO,
# where every entry is already present, and fails fast on a minimal medium.
_PREFLIGHT_BASE_TOOLS=(
  jq                         # config parsing — every front-end + phase
  git                        # repo clone / profile assembly
  curl                       # connectivity checks, downloads
  sgdisk:gptfdisk            # GPT partitioning
  mkfs.fat:dosfstools        # ESP formatting
  partprobe:parted           # re-read the partition table after sgdisk
  pacstrap:arch-install-scripts  # + arch-chroot / genfstab
  mkinitcpio                 # initramfs generation
  efibootmgr                 # UEFI boot entries
  reflector                  # mirror ranking
  rsync                      # file staging / persist copies
  mkfs.btrfs:btrfs-progs     # btrfs layouts
  mkfs.ext4:e2fsprogs        # ext4 layouts
  cryptsetup                 # LUKS-encrypted layouts
  mdadm                      # mdraid layouts
  pvs:lvm2                   # LVM layouts
)

# preflight_installer_tools [--interactive]
# Emit the required cmd[:pkg] tokens, one per line. --interactive adds fzf, used
# by the disk picker / guided TUI — not needed for --print-config, a --guided
# replay, or a positional-config install.
preflight_installer_tools() {
  printf '%s\n' "${_PREFLIGHT_BASE_TOOLS[@]}"
  [[ "${1:-}" == --interactive ]] && printf '%s\n' fzf
  return 0
}

# Seam: the one privileged, network-touching side effect. Overridden in tests.
_preflight_pacman() {
  pacman -Sy --noconfirm --needed "$@" >&2
}

# preflight_ensure_host_tools <cmd[:pkg]>...
# Returns 0 once every command resolves; non-zero (with guidance on stderr) if a
# tool is missing and cannot be installed. The caller decides whether to exit.
preflight_ensure_host_tools() {
  local -a missing_cmds=() missing_pkgs=()
  local spec cmd pkg
  for spec in "$@"; do
    cmd="${spec%%:*}"
    pkg="${spec#*:}"
    [[ "$pkg" == "$spec" ]] && pkg="$cmd"
    command -v "$cmd" >/dev/null 2>&1 \
      || { missing_cmds+=("$cmd"); missing_pkgs+=("$pkg"); }
  done
  ((${#missing_pkgs[@]})) || return 0

  echo -e "${YELLOW:-}[preflight]${NC:-} missing host tool(s):" \
    "${missing_cmds[*]}" >&2

  # No pacman → not an Arch live medium (e.g. running on a dev box). Don't try
  # to install; tell the operator exactly which packages to provide and stop.
  if ! command -v pacman >/dev/null 2>&1; then
    echo -e "${RED:-}[preflight]${NC:-} no pacman — not an Arch live medium." >&2
    echo "  Install these packages and re-run: ${missing_pkgs[*]}" >&2
    return 1
  fi

  echo -e "${GREEN:-}[preflight]${NC:-} installing on live ISO:" \
    "${missing_pkgs[*]}" >&2
  if ! _preflight_pacman "${missing_pkgs[@]}"; then
    echo -e "${RED:-}[preflight]${NC:-} pacman failed for: ${missing_pkgs[*]}" >&2
    echo "  Check the network (01-bootstrap-zfs.sh has iwctl notes)," \
      "then re-run." >&2
    return 1
  fi

  # A stale mirror or a partial host can let pacman succeed yet leave a binary
  # absent — verify each originally-missing command resolves before we hand off.
  local -a still=()
  for cmd in "${missing_cmds[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || still+=("$cmd")
  done
  if ((${#still[@]})); then
    echo -e "${RED:-}[preflight]${NC:-} still missing after install:" \
      "${still[*]}" >&2
    return 1
  fi
  return 0
}
