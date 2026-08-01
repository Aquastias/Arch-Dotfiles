#!/usr/bin/env bash
# =============================================================================
# lib/packages/resolver.sh — Package Resolver
# =============================================================================
# Answers "what actually lands on this machine?" for an Effective Config.
#
# Eighteen distinct paths put a package on the system. Five are authored; the
# rest are DERIVED from a setting the operator already made. No amount of
# slot-collapsing removes the derivation — GPU drivers should be computed, not
# hand-listed — so the answer is not fewer paths but a way to QUERY the result.
#
# Every input is declarative, so the resolver needs no pacman query and no
# network: it is testable headless and deterministic for a given config.
#
# Output is a TSV stream, one package per line:
#     <source>\t<layer>\t<package>
# where <source> names the mechanism (base, kernel, gpu, kde-apps, …) and
# <layer> is `authored` or `derived`. Excluded packages are reported
# separately by pkgres_excluded.
#
# Consumed by the CLI inspector (tools/explain-packages.sh), the menu's
# read-only derived section, and the real-profile regression tests — so those
# three can never drift.
#
# Public API:
#   pkgres_resolve  <effective-json>  → TSV of source, layer, package
#   pkgres_excluded <effective-json>  → the excluded package names
#   pkgres_sources                    → every source name the resolver emits
# =============================================================================

# shellcheck source=../config/categorized-list.sh
[[ "$(type -t categorized_list_parse)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/categorized-list.sh"
# shellcheck source=./kernel.sh
[[ "$(type -t kernel_pkg)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/kernel.sh"
# shellcheck source=../config/post-install.sh
[[ "$(type -t post_install_programs)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/post-install.sh"

# The source names, in report order. Kept as data so the CLI and the menu's
# derived section can group without re-deriving the list.
_PKGRES_SOURCES=(
  base kernel bootloader filesystem-tools zfs luks
  gpu audio login-shell
  kde-shell kde-apps kde-aur
  security backup sops
  repo aur
)
pkgres_sources() { printf '%s\n' "${_PKGRES_SOURCES[@]}"; }

# _pkgres_emit <source> <layer> <pkg...>
_pkgres_emit() {
  local src="$1" layer="$2"; shift 2
  local p
  for p in "$@"; do
    [[ -n "$p" ]] && printf '%s\t%s\t%s\n' "$src" "$layer" "$p"
  done
}

# _pkgres_jq <config> <filter> — read a value out of the config.
_pkgres_jq() { jq -r "$2" <<<"$1" 2>/dev/null; }

# pkgres_excluded <effective-json> — the packages a layer dropped, reported
# separately so an operator can confirm an exclusion took effect. The Layer
# Resolver strips packages.exclude from a resolved config, so this reads the
# authored key when it survives (an un-resolved profile) and is empty
# otherwise.
pkgres_excluded() {
  _pkgres_jq "$1" '(.packages.exclude // [])[]' | sort -u
}

# pkgres_resolve <effective-json> — every package that will be installed,
# each tagged with its source and layer. Deterministic: the emit order is
# fixed and each source sorts its own set.
pkgres_resolve() {
  local cfg="$1"

  # ── authored: the Base Package List ───────────────────────────────────────
  # Mirrors lib/packages/list.sh's hardcoded set. Listed here rather than
  # calling collect_packages because that function resolves the environment
  # and reads globals; the resolver must stay pure.
  _pkgres_emit base derived \
    base base-devel linux-firmware networkmanager openssh cronie \
    efibootmgr dosfstools vim git sudo rsync jq pacman-contrib stow \
    man-db man-pages texinfo

  # ── kernel(s) + headers ───────────────────────────────────────────────────
  local tok
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    _pkgres_emit kernel derived \
      "$(kernel_pkg "$tok")" "$(kernel_headers_pkg "$tok")"
  done < <(_pkgres_jq "$cfg" '
    (.options.kernel // ["lts"]) | if type == "string" then [.] else . end | .[]')

  # ── bootloader ────────────────────────────────────────────────────────────
  # systemd-boot ships with systemd (already in base); only grub adds a package.
  [[ "$(_pkgres_jq "$cfg" '.options.bootloader // "systemd-boot"')" == "grub" ]] \
    && _pkgres_emit bootloader derived grub

  # ── filesystem userland ───────────────────────────────────────────────────
  # Per-filesystem tools for any group using them; ext4 rides e2fsprogs in base
  # and zfs has no mkfs. Independent of encryption.
  local fs_all
  fs_all="$(_pkgres_jq "$cfg" '
    [(.filesystem // "zfs"),
     ((.storage_groups // [])[] | .filesystem // empty),
     ((.data_pools    // [])[] | .filesystem // empty)] | unique | .[]')"
  grep -qx xfs   <<<"$fs_all" && _pkgres_emit filesystem-tools derived xfsprogs
  grep -qx btrfs <<<"$fs_all" && _pkgres_emit filesystem-tools derived btrfs-progs
  grep -qx zfs   <<<"$fs_all" && _pkgres_emit zfs derived zfs-dkms zfs-utils

  # LUKS userland for any non-zfs encrypted group.
  if [[ "$(_pkgres_jq "$cfg" '.options.encryption // false')" == "true" ]] \
     && grep -qvx zfs <<<"$fs_all"; then
    _pkgres_emit luks derived cryptsetup
  fi

  # ── GPU drivers ───────────────────────────────────────────────────────────
  # `auto` cannot be resolved without hardware, so it reports as such rather
  # than lying — the resolver makes no lspci call.
  local vendor
  while IFS= read -r vendor; do
    [[ -n "$vendor" ]] || continue
    case "$vendor" in
    amd)    _pkgres_emit gpu derived vulkan-radeon xf86-video-amdgpu mesa ;;
    nvidia) _pkgres_emit gpu derived nvidia-open-dkms nvidia-utils \
              lib32-nvidia-utils libva-nvidia-driver egl-wayland ;;
    intel)  _pkgres_emit gpu derived intel-media-driver ;;
    vm)     _pkgres_emit gpu derived mesa ;;
    auto)   _pkgres_emit gpu derived "(auto — resolved from lspci at install)" ;;
    esac
  done < <(_pkgres_jq "$cfg" '
    (.environment.gpu // "auto") | if type == "string" then [.] else . end | .[]')

  # ── desktop-driven sets ───────────────────────────────────────────────────
  local desktops
  desktops="$(_pkgres_jq "$cfg" '
    (.environment.desktop // []) | if type == "string" then [.] else . end | .[]')"

  # Audio is auto-derived: PipeWire whenever any desktop is selected.
  if [[ -n "$desktops" ]]; then
    _pkgres_emit audio derived \
      pipewire pipewire-pulse pipewire-alsa wireplumber \
      gst-plugin-pipewire pipewire-jack libpulse
  fi

  local de
  while IFS= read -r de; do
    [[ -n "$de" ]] || continue
    _pkgres_de_packages "$de"
  done <<<"$desktops"

  # ── login shells ──────────────────────────────────────────────────────────
  # The chroot installs a user's login shell package when the binary is
  # missing, so the shell is derived from the setting, never declared.
  local sh
  while IFS= read -r sh; do
    [[ -n "$sh" ]] || continue
    _pkgres_emit login-shell derived "${sh##*/}"
  done < <(_pkgres_user_shells "$cfg")

  # ── Security & Backup Extras (ADR 0041) ───────────────────────────────────
  # Paru-based User Programs routed through the Primary User's pass.
  local pi prog
  pi="$(_pkgres_jq "$cfg" '.post_install // {} | tojson')"
  if [[ -n "$pi" && "$pi" != "null" ]]; then
    while IFS= read -r prog; do
      [[ -n "$prog" ]] || continue
      case "$prog" in
      zfs-auto-snapshot | borg) _pkgres_emit backup derived "$prog" ;;
      *)                        _pkgres_emit security derived "$prog" ;;
      esac
    done < <(post_install_programs "$pi" 2>/dev/null)
  fi

  # ── secrets-activated sops (ADR 0025) ─────────────────────────────────────
  # Not declared anywhere: the Runner selects it when the host or one of its
  # users ships a secrets.json.
  if _pkgres_has_secrets "$cfg"; then
    _pkgres_emit sops derived sops age go
  fi

  # ── authored slots ────────────────────────────────────────────────────────
  local slot json p
  for slot in repo aur; do
    json="$(_pkgres_jq "$cfg" ".packages.${slot} // {} | tojson")"
    [[ -n "$json" && "$json" != "null" ]] || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] && _pkgres_emit "$slot" authored "$p"
    done < <(categorized_list_parse "$json" string "packages.${slot}" 2>/dev/null)
  done
}

# _pkgres_de_packages <de> — the Desktop Environment Adapter's own sets, read
# from its install-<de>.jsonc so the adapter stays the owner (ADR 0021).
_pkgres_de_packages() {
  local de="$1"
  local f="${OS_DIR:-}/extras/desktop/${de}/install-${de}.jsonc"
  [[ -f "$f" ]] || return 0
  local json; json="$(jsonc_strip "$f" 2>/dev/null)" || return 0

  # The shell section is a fixed pacman list inside the adapter script, not
  # data — mirrored here so the report is complete.
  if [[ "$(jq -r '.shell // true' <<<"$json")" == "true" && "$de" == "kde" ]]; then
    _pkgres_emit kde-shell derived \
      plasma-meta plasma-workspace plasma-x11-session polkit-kde-agent \
      sddm sddm-kcm print-manager papirus-icon-theme \
      qt5-wayland qt6-wayland xdg-utils
  fi

  local p
  if [[ "$(jq -r '.apps // true' <<<"$json")" == "true" ]]; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && _pkgres_emit kde-apps derived "$p"
    done < <(categorized_list_parse \
      "$(jq -c '.apps_list // {}' <<<"$json")" bool apps_list 2>/dev/null)
  fi

  while IFS= read -r p; do
    [[ -n "$p" ]] && _pkgres_emit kde-aur derived "$p"
  done < <(categorized_list_parse \
    "$(jq -c '.aur // {}' <<<"$json")" bool aur 2>/dev/null)
}

# _pkgres_user_shells <config> — the login shell package of every declared
# user, resolved through User Core so an undeclared shell still reports.
_pkgres_user_shells() {
  local cfg="$1" u shell core_shell=""
  if [[ -n "${OS_DIR:-}" && -f "${OS_DIR}/users/core/profile.jsonc" ]]; then
    core_shell="$(jsonc_strip "${OS_DIR}/users/core/profile.jsonc" 2>/dev/null \
      | jq -r '.shell // empty' 2>/dev/null)"
  fi
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    shell=""
    if [[ -n "${OS_DIR:-}" && -f "${OS_DIR}/users/${u}/profile.jsonc" ]]; then
      shell="$(jsonc_strip "${OS_DIR}/users/${u}/profile.jsonc" 2>/dev/null \
        | jq -r '.shell // empty' 2>/dev/null)"
    fi
    printf '%s\n' "${shell:-${core_shell:-/bin/bash}}"
  done < <(_pkgres_jq "$cfg" '(.users // [])[]') | sort -u
}

# _pkgres_has_secrets <config> — rc 0 when the host or any declared user ships
# a secrets.json, the same condition that activates the sops Program.
_pkgres_has_secrets() {
  local cfg="$1" host u
  host="$(_pkgres_jq "$cfg" '.system.hostname // empty')"
  [[ -n "${OS_DIR:-}" ]] || return 1
  [[ -n "$host" && -f "${OS_DIR}/hosts/${host}/secrets.json" ]] && return 0
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    [[ -f "${OS_DIR}/users/${u}/secrets.json" ]] && return 0
  done < <(_pkgres_jq "$cfg" '(.users // [])[]')
  return 1
}
