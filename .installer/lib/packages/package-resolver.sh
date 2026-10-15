#!/usr/bin/env bash
# =============================================================================
# lib/packages/package-resolver.sh — Package Resolver
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
# host profile?". Excluded packages and the sets that cannot be resolved without
# hardware are reported separately (package_resolver_excluded,
# package_resolver_unresolved).
#
# Consumed by the CLI inspector (tools/explain-packages.sh), the menu's
# read-only derived section, and the real-profile regression tests — so those
# three can never drift.
#
# Public API:
#   package_resolver_resolve <effective-json>
#       → TSV of source, layer, package
#   package_resolver_excluded <effective-json>
#       → the excluded package names
#   package_resolver_unresolved <effective-json>
#       → sets left open until install time
#   package_resolver_sources
#       → every source name the resolver emits
#
# Used by: tools/explain-packages.sh, lib/guided/controller.sh.
# =============================================================================

# shellcheck source=../config/install-config.sh
declare -F install_config_use_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/install-config.sh"
# shellcheck source=../config/categorized-list.sh
declare -F categorized_list_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/categorized-list.sh"
# shellcheck source=./kernel.sh
declare -F kernel_package >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/kernel.sh"
# shellcheck source=../boot/bootloader.sh
declare -F bootloader_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../boot/bootloader.sh"
# shellcheck source=../config/post-install.sh
declare -F post_install_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/post-install.sh"
# shellcheck source=../config/printing.sh
declare -F printing_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/printing.sh"
# shellcheck source=../config/mirrors.sh
declare -F mirrors_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/mirrors.sh"
# shellcheck source=../config/fonts.sh
declare -F fonts_repo_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/fonts.sh"
# shellcheck source=../config/bluetooth.sh
declare -F bluetooth_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/bluetooth.sh"
# shellcheck source=../config/power.sh
declare -F power_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/power.sh"
# The pure package maps shared with the install path, so the query and the
# install can never disagree on these names (base, gpu, audio, fs userland).
# shellcheck source=./base.sh
declare -F base_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/base.sh"
# shellcheck source=./gpu.sh
declare -F gpu_vendor_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/gpu.sh"
# shellcheck source=./audio.sh
declare -F audio_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/audio.sh"
# shellcheck source=./filesystem.sh
declare -F filesystem_userland_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/filesystem.sh"
# shellcheck source=./niri.sh
declare -F niri_core_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/niri.sh"
# shellcheck source=./noctalia.sh
declare -F noctalia_preset_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/noctalia.sh"
# shellcheck source=./package-resolver-desktop.sh
declare -F _package_resolver_desktop_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/package-resolver-desktop.sh"

# The source names in report order, each paired with the menu category that
# DRIVES it. One table, not two: the guided derived section needs the origin
# and the CLI needs the order, and a source added to only one of them would
# render with no origin and never be noticed.
_PACKAGE_RESOLVER_SOURCES=(
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
  "kde-apps-extra|Environment"
  "kde-plugins|Environment"
  "kde-aur|Environment"
  "niri-shell|Environment"
  "noctalia|Environment"
  "security|Security"
  "backup|Backup"
  "printing|Daemons"
  "bluetooth|Daemons"
  "power|Daemons"
  "mirrors|Mirrors & Repositories"
  "fonts|System"
  "sops|secrets on disk"
  "repo|Packages"
  "aur|Packages"
)
package_resolver_sources() {
  printf '%s\n' "${_PACKAGE_RESOLVER_SOURCES[@]%%|*}"
}

# package_resolver_source_origin <source> — the menu category that drives it, so
# the guided read-only section can say where to go to change it.
package_resolver_source_origin() {
  local entry
  for entry in "${_PACKAGE_RESOLVER_SOURCES[@]}"; do
    [[ "${entry%%|*}" == "$1" ]] && { printf '%s' "${entry#*|}"; return 0; }
  done
  printf 'the installer'
}

# _package_resolver_emit <source> <layer> <pkg...>
_package_resolver_emit() {
  local source_name="$1" layer="$2"; shift 2
  local package
  for package in "$@"; do
    [[ -n "$package" ]] \
      && printf '%s\t%s\t%s\n' "$source_name" "$layer" "$package"
  done
}

# _package_resolver_jq <config> <filter> — read a value out of the config.
_package_resolver_jq() { jq -r "$2" <<<"$1" 2>/dev/null; }

# package_resolver_excluded <effective-json> — the packages a layer dropped,
# reported separately so an operator can confirm an exclusion took effect. The
# Layer Resolver strips packages.exclude from a resolved config, so this reads
# the authored key when it survives (an un-resolved profile) and is empty
# otherwise.
package_resolver_excluded() {
  _package_resolver_jq "$1" '(.packages.exclude // [])[]' | sort -u
}

# package_resolver_unresolved <effective-json> — the sets this config leaves
# open until install time, one note per line. They are NOT packages, so they
# never enter the resolved stream; reporting them separately is what keeps the
# stream honest instead of carrying placeholder names.
package_resolver_unresolved() {
  local config="$1"
  (install_config_use_json "$config"; install_config_gpu) \
    | while IFS= read -r vendor; do
        case "$vendor" in
        auto)  printf 'gpu: "auto" — vendor detected from lspci at install\n' ;;
        intel) printf 'gpu: intel — intel-media-driver assumed;%s\n' \
                 " pre-Broadwell resolves to libva-intel-driver" ;;
        esac
      done
  printf 'microcode: the running CPU vendor package, detected at install\n'
}

# package_resolver_resolve <effective-json> — every package that will be
# installed, each tagged with its source and layer. Deterministic: the emit
# order is fixed and each source sorts its own set.
package_resolver_resolve() {
  local config="$1"

  # The Base Package List: the shared pure set (lib/packages/base.sh) that
  # package_list_collect also installs — one source of truth, so query and
  # install cannot drift. (Tagged `derived` because the resolver reports it as
  # computed, not operator-authored.)
  _package_resolver_emit_from base base_packages
  _package_resolver_kernels "$config"
  _package_resolver_bootloader "$config"

  local filesystems
  filesystems="$(_package_resolver_filesystems "$config")"
  _package_resolver_filesystem_sets "$config" "$filesystems"
  _package_resolver_gpu "$config"

  local desktops
  desktops="$(_package_resolver_jq "$config" '
    (.environment.desktop // [])
    | if type == "string" then [.] else . end | .[]')"
  _package_resolver_desktop_sets "$config" "$desktops"
  _package_resolver_display_manager "$config" "$desktops"
  _package_resolver_login_shells "$config"
  _package_resolver_post_install "$config" "$filesystems"

  _package_resolver_services "$config"

  # Font Catalog (ADR 0080): fonts moved out of packages.repo into the curated
  # options.fonts catalog, so they no longer surface under the authored repo
  # slot. Report them as source=fonts (derived) — repo fonts install via
  # pacstrap, AUR fonts (ttf-ms-fonts) via the paru pass. Absent options.fonts
  # ⇒ the catalog defaults.
  _package_resolver_emit_from fonts fonts_repo_packages "$config"
  _package_resolver_emit_from fonts fonts_aur_packages "$config"

  # secrets-activated sops (ADR 0025): not declared anywhere — the Runner
  # selects it when the host or one of its users ships a secrets.json.
  if _package_resolver_has_secrets "$config"; then
    _package_resolver_emit sops derived sops age go
  fi

  _package_resolver_authored_slots "$config"
}

# _package_resolver_services <config> — toggle-derived Host Programs, not
# authored in Host Core: each is reported under its own source via the
# single source of truth the injector shares, so explain-packages and the
# guided derived section answer "why is this here?". Printing → cups (ADR
# 0079); Mirrors & Repositories → reflector (ADR 0089); bluetooth (ADR
# 0080); the power daemon (power-profiles-daemon | tuned, ADR 0080).
_package_resolver_services() {
  _package_resolver_emit_from printing printing_programs "$1"
  _package_resolver_emit_from mirrors mirrors_programs "$1"
  _package_resolver_emit_from bluetooth bluetooth_programs "$1"
  _package_resolver_emit_from power power_programs "$1"
}

# _package_resolver_emit_from <source> <command> [argument…] — emit every
# line <command> prints (its stderr dropped) as a derived <source> package.
_package_resolver_emit_from() {
  local source_name="$1" package
  shift
  while IFS= read -r package; do
    _package_resolver_emit "$source_name" derived "$package"
  done < <("$@" 2>/dev/null)
}

# _package_resolver_kernels <config> — each Kernel Selection token's kernel +
# headers.
_package_resolver_kernels() {
  local token
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    _package_resolver_emit kernel derived \
      "$(kernel_package "$token")" "$(kernel_headers_package "$token")"
  done < <(install_config_use_json "$1"; install_config_get kernels)
}

# _package_resolver_bootloader <config> — packages from the Bootloader
# Manifest (ADR 0077); today systemd-boot adds nothing and grub adds grub.
_package_resolver_bootloader() {
  local bootloader package
  bootloader="$(install_config_use_json "$1"; install_config_bootloader)"
  while IFS= read -r package; do
    [[ -n "$package" ]] && _package_resolver_emit bootloader derived "$package"
  done < <(bootloader_packages "$bootloader")
  return 0
}

# _package_resolver_filesystems <config> — every filesystem a group uses, one
# per line. A manual layout is plain partitions (ADR 0073): no pools, so no
# ZFS even though `filesystem` still defaults to zfs.
_package_resolver_filesystems() {
  (
    install_config_use_json "$1"
    [[ "$(install_config_disk_kind)" == manual ]] && exit 0
    { install_config_filesystem
      _package_resolver_jq "$1" '(.storage_groups // [])[],
        (.data_pools // [])[] | .filesystem // empty'
    } | sort -u
  )
}

# _package_resolver_filesystem_sets <config> <filesystems> — per-filesystem
# tools for any group using them (names from the shared fs userland map,
# lib/packages/filesystem.sh); ext4 rides e2fsprogs in base and zfs has no
# mkfs. Independent of encryption. Then LUKS userland for any non-zfs
# encrypted group.
_package_resolver_filesystem_sets() {
  local config="$1" filesystems="$2"
  # shellcheck disable=SC2046
  grep -qx xfs   <<<"$filesystems" \
    && _package_resolver_emit filesystem-tools derived \
         $(filesystem_userland_packages xfs)
  # shellcheck disable=SC2046
  grep -qx btrfs <<<"$filesystems" \
    && _package_resolver_emit filesystem-tools derived \
         $(filesystem_userland_packages btrfs)
  # shellcheck disable=SC2046
  grep -qx zfs   <<<"$filesystems" \
    && _package_resolver_emit zfs derived $(filesystem_userland_packages zfs)

  # The install list's own per-group rule (ADR 0043) via the reader, bound
  # inside the $(…) subshell so the bind cannot leak
  local any_luks
  any_luks="$(install_config_use_json "$config"
    install_config_any_nonzfs_luks)"
  if [[ "$any_luks" == "true" ]]; then
    # shellcheck disable=SC2046
    _package_resolver_emit luks derived $(filesystem_luks_userland_packages)
  fi
  return 0
}

# _package_resolver_gpu <config> — GPU drivers from the shared pure GPU map
# (lib/packages/gpu.sh), the same map the install path uses. intel reports its
# modern default (intel-media-driver); the pre-Broadwell libva-intel-driver
# downgrade needs the lspci device id a pure resolver cannot read, so it
# surfaces via package_resolver_unresolved instead of being silently wrong.
# `auto` is no vendor, so the map returns nothing — emitting no fake name to
# pollute a --flat listing; package_resolver_unresolved reports it.
_package_resolver_gpu() {
  local vendor
  while IFS= read -r vendor; do
    [[ -n "$vendor" ]] || continue
    # shellcheck disable=SC2046
    _package_resolver_emit gpu derived $(gpu_vendor_packages "$vendor")
  done < <(install_config_use_json "$1"; install_config_gpu)
}

# _package_resolver_desktop_sets <config> <desktops> — audio, then each
# desktop's own sets. Audio is auto-derived: the shared PipeWire stack
# (lib/packages/audio.sh) whenever any desktop is selected — the same names
# the install path adds.
_package_resolver_desktop_sets() {
  local config="$1" desktops="$2" desktop
  if [[ -n "$desktops" ]]; then
    _package_resolver_emit_from audio audio_packages
  fi
  while IFS= read -r desktop; do
    [[ -n "$desktop" ]] || continue
    _package_resolver_desktop_packages "$desktop" "$config"
  done <<<"$desktops"
}

# _package_resolver_display_manager <config> <desktops> — the greeter, its
# own derived set keyed on the resolved display_manager (ADR 0069), not
# smuggled inside kde-shell. `auto` resolves the same DESKTOP-AWARE way the
# installer does (_environment_resolve_display_manager, ADR 0091): greetd for a
# KDE-free desktop set (hyprland/niri), sddm when kde is present; none when no
# desktop. Explicit greetd/sddm win.
_package_resolver_display_manager() {
  local config="$1" desktops="$2" display_manager
  display_manager="$(install_config_use_json "$config"
    install_config_display_manager)"
  if [[ -z "$desktops" ]]; then
    display_manager="none"
  elif [[ "$display_manager" == "auto" ]]; then
    display_manager="greetd"
    grep -qx kde <<<"$desktops" && display_manager="sddm"
  fi
  case "$display_manager" in
    greetd) _package_resolver_emit display-manager derived \
              greetd greetd-tuigreet ;;
    sddm)   _package_resolver_emit display-manager derived sddm ;;
  esac
}

# _package_resolver_login_shells <config> — the chroot installs a user's login
# shell package when the binary is missing, so the shell is derived from the
# setting, never declared.
_package_resolver_login_shells() {
  local shell
  while IFS= read -r shell; do
    [[ -n "$shell" ]] || continue
    _package_resolver_emit login-shell derived "${shell##*/}"
  done < <(_package_resolver_user_shells "$1")
}

# _package_resolver_post_install <config> <filesystems> — Security & Backup
# Extras (ADR 0041): paru-based User Programs routed through the Primary
# User's pass.
_package_resolver_post_install() {
  local config="$1" filesystems="$2" post_install_json program has_zfs=false
  post_install_json="$(_package_resolver_jq "$config" \
    '.post_install // {} | tojson')"
  [[ -n "$post_install_json" && "$post_install_json" != "null" ]] || return 0
  grep -qx zfs <<<"$filesystems" && has_zfs=true
  while IFS= read -r program; do
    [[ -n "$program" ]] || continue
    case "$program" in
    zfs-auto-snapshot | borg)
      _package_resolver_emit backup derived "$program" ;;
    *) _package_resolver_emit security derived "$program" ;;
    esac
  done < <(post_install_programs "$post_install_json" "$has_zfs" 2>/dev/null)
}

# _package_resolver_authored_slots <config> — packages.repo / packages.aur.
# Layer provenance: an authored package Host Core also declares is tagged
# `core`, otherwise `host` — so the report answers "do I edit Host Core or
# this host profile?" rather than only "was this authored or derived?".
_package_resolver_authored_slots() {
  local config="$1" core_json=""
  local core_profile="${INSTALLER_DIR:-}/hosts/core/profile.jsonc"
  if [[ -n "${INSTALLER_DIR:-}" && -f "$core_profile" ]]; then
    core_json="$(jsonc_strip "$core_profile" 2>/dev/null)"
  fi
  local slot json package
  for slot in repo aur; do
    json="$(_package_resolver_jq "$config" ".packages.${slot} // {} | tojson")"
    [[ -n "$json" && "$json" != "null" ]] || continue
    while IFS= read -r package; do
      [[ -n "$package" ]] || continue
      _package_resolver_emit "$slot" \
        "$(_package_resolver_authored_layer "$core_json" "$slot" "$package")" \
        "$package"
    done < <(categorized_list_parse "$json" string \
      "packages.${slot}" 2>/dev/null)
  done
}

# _package_resolver_authored_layer <core-json> <slot> <package> — `core` when
# Host Core declares <package> in <slot>, `host` otherwise; `authored` when no
# Host Core is readable.
_package_resolver_authored_layer() {
  local core_json="$1" slot="$2" package="$3"
  [[ -n "$core_json" ]] || { printf 'authored'; return 0; }
  if jq -e --arg s "$slot" --arg p "$package" \
       '[(.packages[$s] // {}) | to_entries[].value[]] | index($p)' \
       <<<"$core_json" >/dev/null 2>&1; then
    printf 'core'
  else
    printf 'host'
  fi
}

# _package_resolver_user_shells <config> — the login shell package of every
# declared user, resolved through User Core so an undeclared shell still
# reports.
_package_resolver_user_shells() {
  local config="$1" user shell core_shell
  core_shell="$(_package_resolver_profile_shell users/core)"
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    shell="$(_package_resolver_profile_shell "users/${user}")"
    printf '%s\n' "${shell:-${core_shell:-/bin/bash}}"
  done < <(_package_resolver_jq "$config" '(.users // [])[]') | sort -u
}

# _package_resolver_profile_shell <users/name> — the `.shell` a user profile
# declares under INSTALLER_DIR; empty when unset or unreadable.
_package_resolver_profile_shell() {
  local profile="${INSTALLER_DIR:-}/$1/profile.jsonc"
  [[ -n "${INSTALLER_DIR:-}" && -f "$profile" ]] || return 0
  jsonc_strip "$profile" 2>/dev/null | jq -r '.shell // empty' 2>/dev/null
}

# _package_resolver_has_secrets <config> — rc 0 when the host or any declared
# user ships a secrets.json, the same condition that activates the sops Program.
_package_resolver_has_secrets() {
  local config="$1" host user
  host="$(_package_resolver_jq "$config" '.system.hostname // empty')"
  [[ -n "${INSTALLER_DIR:-}" ]] || return 1
  # VM hosts/users live under <kind>/vm/<name>/ (fallback mirrors
  # _profile_loader_load).
  if [[ -n "$host" ]]; then
    [[ -f "${INSTALLER_DIR}/hosts/${host}/secrets.json" \
       || -f "${INSTALLER_DIR}/hosts/vm/${host}/secrets.json" ]] && return 0
  fi
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    [[ -f "${INSTALLER_DIR}/users/${user}/secrets.json" \
       || -f "${INSTALLER_DIR}/users/vm/${user}/secrets.json" ]] && return 0
  done < <(_package_resolver_jq "$config" '(.users // [])[]')
  return 1
}
