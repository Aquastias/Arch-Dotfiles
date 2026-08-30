#!/usr/bin/env bash
# =============================================================================
# lib/preflight.sh — ensure the installer's host tools exist before any run
# =============================================================================
# Front-ends and the Target Resolver run in install.sh BEFORE 01-bootstrap, and
# the numbered phases shell out to the whole partition/pacstrap toolchain. This
# checks every host tool up front and pacman-installs any missing, so the
# operator never hits "fzf: command not found" or a missing mkfs mid-wipe.
#
# Guarded: the "extra" packages a stripped medium might omit (jq, fzf, gptfdisk,
# arch-install-scripts, btrfs-progs, cryptsetup, …). NOT guarded: the ISO base
# (bash/coreutils/…, or the script couldn't run); zfs (01-bootstrap installs it,
# ADR 0023); age/sops (lib/secrets.sh installs contextually).
#
# Off a live medium (no pacman) a missing tool is a hard error listing what to
# install. The pacman call is a seam (_preflight_pacman) for tests.
# =============================================================================

# Self-contained on purpose: preflight runs in install.sh BEFORE common.sh is
# sourced (jq must exist before anything parses jsonc), so it cannot use
# common.sh's command_exists — define a local copy here.
command_exists() { command -v "$1" >/dev/null 2>&1; }

# The host toolchain beyond the ISO base. Entries are cmd[:pkg] (pkg defaults to
# cmd); one representative command per package (pacman --needed dedups).
# Config-independent on purpose: checking the full toolchain up front is cheap on
# the official ISO and fails fast on a minimal medium.
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

# preflight_installer_tools [--interactive] — emit the required cmd[:pkg] tokens,
# one per line. --interactive adds fzf (disk picker / guided TUI).
preflight_installer_tools() {
  printf '%s\n' "${_PREFLIGHT_BASE_TOOLS[@]}"
  [[ "${1:-}" == --interactive ]] && printf '%s\n' fzf
  return 0
}

# preflight_frontend_tools [--interactive] — the front-end-only tier for --debug:
# jq (+ fzf when interactive), and NONE of the install toolchain, so
# `install.sh --debug` can launch the menu on a daily-driver box.
preflight_frontend_tools() {
  printf '%s\n' jq
  [[ "${1:-}" == --interactive ]] && printf '%s\n' fzf
  return 0
}

# preflight_resolve_plan <debug:0|1> — pure --debug resolver (ADR 0063). Maps
# the flags to one line "<tier> <install>": --debug → "frontend no" (front-end
# tools only, install withheld), normal → "full yes". Pure (no root/network/
# exec), so the "never install under --debug" guarantee is unit-testable.
preflight_resolve_plan() {
  if [[ "${1:-0}" == "1" ]]; then
    printf 'frontend no\n'
  else
    printf 'full yes\n'
  fi
}

# Seam: the one privileged, network-touching side effect. Overridden in tests.
_preflight_pacman() {
  pacman -Sy --noconfirm --needed "$@" >&2
}

# preflight_ensure_host_tools <cmd[:pkg]>... — returns 0 once every command
# resolves; non-zero (guidance on stderr) if one is missing and uninstallable.
preflight_ensure_host_tools() {
  local -a missing_cmds=() missing_pkgs=()
  local spec cmd pkg
  for spec in "$@"; do
    cmd="${spec%%:*}"
    pkg="${spec#*:}"
    [[ "$pkg" == "$spec" ]] && pkg="$cmd"
    command_exists "$cmd" \
      || { missing_cmds+=("$cmd"); missing_pkgs+=("$pkg"); }
  done
  ((${#missing_pkgs[@]})) || return 0

  echo -e "${YELLOW:-}[preflight]${NC:-} missing host tool(s):" \
    "${missing_cmds[*]}" >&2

  # No pacman → not an Arch live medium (e.g. a dev box). Don't install; list
  # the packages to provide and stop.
  if ! command_exists pacman; then
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
    command_exists "$cmd" || still+=("$cmd")
  done
  if ((${#still[@]})); then
    echo -e "${RED:-}[preflight]${NC:-} still missing after install:" \
      "${still[*]}" >&2
    return 1
  fi
  return 0
}
