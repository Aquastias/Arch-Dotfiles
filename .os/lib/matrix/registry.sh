#!/usr/bin/env bash
# =============================================================================
# lib/matrix/registry.sh — Combination Matrix Axis Registry (ADR 0046)
# =============================================================================
# The stay-in-sync enforcer. Maps every menu field (lib/config/menu.sh's
# _MENU_FIELDS) to a matrix ROLE and a light/heavy WEIGHT, and asserts the
# registry covers _MENU_FIELDS *exactly* — a menu field with no entry, or an
# entry for a field the menu no longer offers, hard-fails. This turns "a new
# menu option should update the tests" into "you cannot run the generator until
# you classify the new option."
#
# Roles:
#   storage-cluster     exhaustively crossed in Tier 1 (storage semantics).
#   pairwise-affecting  install-affecting back-end axis → the 2-wise cover.
#   scalar-sweep        install-affecting scalar, swept one value at a time.
#   inert               no install-combination content (identity, cosmetics,
#                       lists validated elsewhere) — excluded from both tiers.
#
# Weight is the cell-cost hint the profile synthesizer bands into light/heavy
# install timeouts: heavy = an axis whose variation can pull a desktop, the
# nvidia driver, or an AUR build.
#
# Pure: no TTY, no disk writes. Requires _MENU_FIELDS in scope (menu.sh).
#
# Public API:
#   matrix_axis_paths            → the registered paths, one per line
#   matrix_axis_role   <path>    → the path's role (empty + rc1 if unregistered)
#   matrix_axis_weight <path>    → the path's weight (empty + rc1 if unregistered)
#   matrix_registry_assert       → 0 iff the registry covers _MENU_FIELDS exactly
# =============================================================================

# shellcheck source=../config/menu.sh
[[ ${_MENU_FIELDS+x} == x ]] \
  || source "${BASH_SOURCE[0]%/*}/../config/menu.sh"

# The registry: "path|role|weight", one per menu field. Keep in lockstep with
# _MENU_FIELDS — matrix_registry_assert fails the generator on any drift.
_MATRIX_AXIS_REGISTRY=(
  "system.hostname|inert|light"
  "system.locale|inert|light"
  "system.timezone|inert|light"
  "system.keymap|inert|light"
  "filesystem|storage-cluster|light"
  "options.encryption|storage-cluster|light"
  "options.impermanence.enabled|storage-cluster|light"
  "options.esp_size|scalar-sweep|light"
  "options.kernel|pairwise-affecting|light"
  "options.bootloader|pairwise-affecting|light"
  "options.ssh.enabled|pairwise-affecting|light"
  "options.age_key_url|inert|light"
  "sysctl|inert|light"
  "environment.desktop|pairwise-affecting|heavy"
  "environment.gpu|pairwise-affecting|heavy"
  "options.mirror_countries|inert|light"
  "options.multilib|pairwise-affecting|light"
  "packages.extra|inert|heavy"
  "system_programs|inert|heavy"
  "post_install.security.firewall|inert|light"
  "post_install.security.antivirus|inert|light"
  "post_install.security.rootkit|inert|light"
  "post_install.security.apparmor|inert|light"
  "post_install.backup.zfs_auto_snapshot|inert|light"
  "post_install.backup.borg|inert|light"
  "users|inert|heavy"
)

# matrix_axis_paths — the registered paths, one per line.
matrix_axis_paths() {
  local spec
  for spec in "${_MATRIX_AXIS_REGISTRY[@]}"; do printf '%s\n' "${spec%%|*}"; done
}

# _matrix_registry_field <path> <n> — field <n> (role=2, weight=3) for <path>.
_matrix_registry_field() {
  local path="$1" n="$2" spec p role weight
  for spec in "${_MATRIX_AXIS_REGISTRY[@]}"; do
    IFS='|' read -r p role weight <<<"$spec"
    if [[ "$p" == "$path" ]]; then
      case "$n" in 2) printf '%s\n' "$role" ;; 3) printf '%s\n' "$weight" ;; esac
      return 0
    fi
  done
  return 1
}

# matrix_axis_role <path> — the path's role (rc1 + empty if unregistered).
matrix_axis_role()   { _matrix_registry_field "$1" 2; }
# matrix_axis_weight <path> — the path's weight (rc1 + empty if unregistered).
matrix_axis_weight() { _matrix_registry_field "$1" 3; }

# _matrix_menu_paths — the _MENU_FIELDS paths (field 2 of each spec), one/line.
_matrix_menu_paths() {
  local spec path
  for spec in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r _ path _ <<<"$spec"   # section | path | label|default
    printf '%s\n' "$path"
  done
}

# matrix_registry_assert — 0 iff the registry classifies _MENU_FIELDS exactly.
# Names every offending path; fails on the first class of problem it finds.
matrix_registry_assert() {
  local menu reg missing stale rc=0
  menu="$(_matrix_menu_paths | sort -u)"
  reg="$(matrix_axis_paths | sort -u)"

  missing="$(comm -23 <(printf '%s\n' "$menu") <(printf '%s\n' "$reg"))"
  if [[ -n "$missing" ]]; then
    local p
    while IFS= read -r p; do
      [[ -n "$p" ]] && echo "matrix: unclassified axis $p" >&2
    done <<<"$missing"
    rc=1
  fi

  stale="$(comm -13 <(printf '%s\n' "$menu") <(printf '%s\n' "$reg"))"
  if [[ -n "$stale" ]]; then
    local q
    while IFS= read -r q; do
      [[ -n "$q" ]] && echo "matrix: stale registry entry $q" >&2
    done <<<"$stale"
    rc=1
  fi

  return "$rc"
}
