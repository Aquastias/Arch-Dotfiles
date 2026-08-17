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
# <layer> is provenance: `derived` for a computed set, or — for the authored
# slots — `core` vs `host`, so the report answers "do I edit Host Core or this
# host profile?". Excluded packages and the sets that cannot be resolved
# without hardware are reported separately (pkgres_excluded, pkgres_unresolved).
#
# Consumed by the CLI inspector (tools/explain-packages.sh), the menu's
# read-only derived section, and the real-profile regression tests — so those
# three can never drift.
#
# Public API:
#   pkgres_resolve    <effective-json>  → TSV of source, layer, package
#   pkgres_excluded   <effective-json>  → the excluded package names
#   pkgres_unresolved <effective-json>  → sets left open until install time
#   pkgres_sources                      → every source name the resolver emits
# =============================================================================

# shellcheck source=../config/categorized-list.sh
declare -F categorized_list_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/categorized-list.sh"
# shellcheck source=./kernel.sh
declare -F kernel_pkg >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/kernel.sh"
# shellcheck source=../boot/bootloaders.sh
declare -F bootloader_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/bootloaders.sh"
# shellcheck source=../config/post-install.sh
declare -F post_install_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/post-install.sh"
# shellcheck source=../config/printing.sh
declare -F printing_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/printing.sh"
# shellcheck source=../config/fonts.sh
declare -F fonts_repo_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/fonts.sh"
# shellcheck source=../config/bluetooth.sh
declare -F bluetooth_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/bluetooth.sh"
# shellcheck source=../config/power.sh
declare -F power_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/power.sh"

# The source names in report order, each paired with the menu category that
# DRIVES it. One table, not two: the guided derived section needs the origin
# and the CLI needs the order, and a source added to only one of them would
# render with no origin and never be noticed.
_PKGRES_SOURCES=(
  "base|the installer"
  "kernel|Options"
  "bootloader|Options"
  "filesystem-tools|Disks"
  "zfs|Disks"
  "luks|Disks"
  "gpu|Environment"
  "audio|Environment"
  "display-manager|Environment"
  "login-shell|Users"
  "kde-shell|Environment"
  "kde-apps|Environment"
  "kde-aur|Environment"
  "security|Security"
  "backup|Backup"
  "printing|Printing service"
  "bluetooth|Bluetooth"
  "power|Power"
  "fonts|General"
  "sops|secrets on disk"
  "repo|Packages"
  "aur|Packages"
)
pkgres_sources() { printf '%s\n' "${_PKGRES_SOURCES[@]%%|*}"; }

# pkgres_source_origin <source> — the menu category that drives it, so the
# guided read-only section can say where to go to change it.
pkgres_source_origin() {
  local e
  for e in "${_PKGRES_SOURCES[@]}"; do
    [[ "${e%%|*}" == "$1" ]] && { printf '%s' "${e#*|}"; return 0; }
  done
  printf 'the installer'
}

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

# pkgres_unresolved <effective-json> — the sets this config leaves open until
# install time, one note per line. They are NOT packages, so they never enter
# the resolved stream; reporting them separately is what keeps the stream
# honest instead of carrying placeholder names.
pkgres_unresolved() {
  local cfg="$1"
  _pkgres_jq "$cfg" '
    (.environment.gpu // "auto")
    | if type == "string" then [.] else . end | .[]' \
    | while IFS= read -r v; do
        case "$v" in
        auto)  printf 'gpu: "auto" — vendor detected from lspci at install\n' ;;
        intel) printf 'gpu: intel — intel-media-driver assumed;%s\n' \
                 " pre-Broadwell resolves to libva-intel-driver" ;;
        esac
      done
  printf 'microcode: the running CPU vendor package, detected at install\n'
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
    (.options.kernel // ["lts"])
    | if type == "string" then [.] else . end | .[]')

  # ── bootloader ────────────────────────────────────────────────────────────
  # Packages come from the Bootloader Manifest (ADR 0077); today systemd-boot
  # adds nothing and grub adds grub.
  local _bl _blp
  _bl="$(_pkgres_jq "$cfg" '.options.bootloader // "systemd-boot"')"
  while IFS= read -r _blp; do
    [[ -n "$_blp" ]] && _pkgres_emit bootloader derived "$_blp"
  done < <(bootloader_packages "$_bl")

  # ── filesystem userland ───────────────────────────────────────────────────
  # Per-filesystem tools for any group using them; ext4 rides e2fsprogs in base
  # and zfs has no mkfs. Independent of encryption.
  local fs_all
  fs_all="$(_pkgres_jq "$cfg" '
    [(.filesystem // "zfs"),
     ((.storage_groups // [])[] | .filesystem // empty),
     ((.data_pools    // [])[] | .filesystem // empty)] | unique | .[]')"
  grep -qx xfs   <<<"$fs_all" && _pkgres_emit filesystem-tools derived xfsprogs
  grep -qx btrfs <<<"$fs_all" \
    && _pkgres_emit filesystem-tools derived btrfs-progs
  grep -qx zfs   <<<"$fs_all" && _pkgres_emit zfs derived zfs-dkms zfs-utils

  # LUKS userland for any non-zfs encrypted group.
  if [[ "$(_pkgres_jq "$cfg" '.options.encryption // false')" == "true" ]] \
     && grep -qvx zfs <<<"$fs_all"; then
    _pkgres_emit luks derived cryptsetup
  fi

  # ── GPU drivers ───────────────────────────────────────────────────────────
  local vendor
  while IFS= read -r vendor; do
    [[ -n "$vendor" ]] || continue
    case "$vendor" in
    amd)    _pkgres_emit gpu derived vulkan-radeon xf86-video-amdgpu mesa ;;
    nvidia) _pkgres_emit gpu derived nvidia-open-dkms nvidia-utils \
              lib32-nvidia-utils libva-nvidia-driver egl-wayland ;;
    # Broadwell+ gets intel-media-driver, older gets libva-intel-driver; the
    # split needs the lspci device id, which a pure resolver cannot read. The
    # modern default is reported and the caveat surfaces via
    # pkgres_unresolved rather than being silently wrong on old hardware.
    intel)  _pkgres_emit gpu derived intel-media-driver ;;
    vm)     _pkgres_emit gpu derived mesa ;;
    # `auto` resolves from lspci on the live ISO. The resolver is pure and
    # makes no hardware call, so it emits NOTHING rather than a fake package
    # name that would pollute a --flat listing. pkgres_unresolved reports it.
    auto)   : ;;
    esac
  done < <(_pkgres_jq "$cfg" '
    (.environment.gpu // "auto")
    | if type == "string" then [.] else . end | .[]')

  # ── desktop-driven sets ───────────────────────────────────────────────────
  local desktops
  desktops="$(_pkgres_jq "$cfg" '
    (.environment.desktop // [])
    | if type == "string" then [.] else . end | .[]')"

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

  # ── display manager (ADR 0069) ────────────────────────────────────────────
  # The greeter is its own derived set keyed on the resolved display_manager,
  # not smuggled inside kde-shell. `auto` resolves the same way the installer
  # does: greetd if Hyprland is selected, else sddm; none when no desktop.
  local dm_raw dm
  dm_raw="$(_pkgres_jq "$cfg" '.environment.display_manager // "auto"')"
  if [[ -z "$desktops" ]]; then
    dm="none"
  elif [[ "$dm_raw" == "auto" ]]; then
    if grep -qx "hyprland" <<<"$desktops"; then dm="greetd"; else dm="sddm"; fi
  else
    dm="$dm_raw"
  fi
  case "$dm" in
    greetd) _pkgres_emit display-manager derived greetd greetd-tuigreet ;;
    sddm)   _pkgres_emit display-manager derived sddm ;;
  esac

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

  # ── Printing Service (ADR 0079) ───────────────────────────────────────────
  # cups is a toggle-derived System Program, not authored in Host Core: report
  # it as source=printing so `explain-packages` and the guided derived section
  # answer "why is cups here?" the way they answer the Security/Backup extras —
  # via printing_programs, the single source of truth the injector also shares.
  local pp
  while IFS= read -r pp; do
    [[ -n "$pp" ]] || continue
    _pkgres_emit printing derived "$pp"
  done < <(printing_programs "$cfg" 2>/dev/null)

  # ── Bluetooth Service (ADR 0080) ──────────────────────────────────────────
  # The `bluetooth` program is toggle-derived like cups, not authored in core:
  # report it as source=bluetooth so explain-packages answers "why is bluetooth
  # here?" via bluetooth_programs, the single source of truth the injector shares.
  local bp
  while IFS= read -r bp; do
    [[ -n "$bp" ]] || continue
    _pkgres_emit bluetooth derived "$bp"
  done < <(bluetooth_programs "$cfg" 2>/dev/null)

  # ── Power Profile (ADR 0080) ──────────────────────────────────────────────
  # The power daemon (power-profiles-daemon | tuned) is enum-derived, not
  # authored in core: report it as source=power via power_programs, the single
  # source of truth the injector shares, so explain-packages answers "why is
  # this daemon here?".
  local wp
  while IFS= read -r wp; do
    [[ -n "$wp" ]] || continue
    _pkgres_emit power derived "$wp"
  done < <(power_programs "$cfg" 2>/dev/null)

  # ── Font Catalog (ADR 0080) ───────────────────────────────────────────────
  # Fonts moved out of packages.repo into the curated options.fonts catalog, so
  # they no longer surface under the authored repo slot below. Report them as
  # source=fonts (derived) — repo fonts install via pacstrap, AUR fonts
  # (ttf-ms-fonts) via the paru pass — so explain-packages still answers "why is
  # this font here?". Absent options.fonts ⇒ the catalog defaults.
  local fp
  while IFS= read -r fp; do
    [[ -n "$fp" ]] || continue
    _pkgres_emit fonts derived "$fp"
  done < <(fonts_repo_packages "$cfg" 2>/dev/null)
  while IFS= read -r fp; do
    [[ -n "$fp" ]] || continue
    _pkgres_emit fonts derived "$fp"
  done < <(fonts_aur_packages "$cfg" 2>/dev/null)

  # ── secrets-activated sops (ADR 0025) ─────────────────────────────────────
  # Not declared anywhere: the Runner selects it when the host or one of its
  # users ships a secrets.json.
  if _pkgres_has_secrets "$cfg"; then
    _pkgres_emit sops derived sops age go
  fi

  # ── authored slots ────────────────────────────────────────────────────────
  # Layer provenance: an authored package Host Core also declares is tagged
  # `core`, otherwise `host` — so the report answers "do I edit Host Core or
  # this host profile?" rather than only "was this authored or derived?".
  local core_json=""
  if [[ -n "${OS_DIR:-}" && -f "${OS_DIR}/hosts/core/profile.jsonc" ]]; then
    core_json="$(jsonc_strip "${OS_DIR}/hosts/core/profile.jsonc" 2>/dev/null)"
  fi
  local slot json p layer
  for slot in repo aur; do
    json="$(_pkgres_jq "$cfg" ".packages.${slot} // {} | tojson")"
    [[ -n "$json" && "$json" != "null" ]] || continue
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      layer=authored
      if [[ -n "$core_json" ]]; then
        if jq -e --arg s "$slot" --arg p "$p" \
             '[(.packages[$s] // {}) | to_entries[].value[]] | index($p)' \
             <<<"$core_json" >/dev/null 2>&1; then
          layer=core
        else
          layer=host
        fi
      fi
      _pkgres_emit "$slot" "$layer" "$p"
    done < <(categorized_list_parse "$json" string \
      "packages.${slot}" 2>/dev/null)
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
  local _sh; _sh="$(jq -r '.shell // true' <<<"$json")"
  if [[ "$_sh" == "true" && "$de" == "kde" ]]; then
    # sddm the PACKAGE moved to the display-manager set (ADR 0069); sddm-kcm (a
    # KDE config app) stays with the KDE shell.
    _pkgres_emit kde-shell derived \
      plasma-meta plasma-workspace plasma-x11-session polkit-kde-agent \
      sddm-kcm print-manager papirus-icon-theme \
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
