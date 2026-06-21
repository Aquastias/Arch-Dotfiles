#!/usr/bin/env bash
# =============================================================================
# lib/config/menu.sh — Guided Installer Menu model (ADR 0039)
# =============================================================================
# Turns a Config State into the menu rows the fzf shell renders. Each row
# carries its section (the Host / Users split), the field's dotted path, a
# label, the current value (override if set, else the default), and the `●`
# override flag. The rows ARE the contract — they drive both the shell and the
# tests, so "full parity" means "every covered field surfaces a row".
#
# Pure: JSON-in/JSON-out, no TTY.
#
# Public API:
#   menu_rows <override> [<baseline>]  → JSON array of rows [{section,field,
#                        label,value,overridden}]
#
# <override> is the operator's sparse override map; <baseline> (optional, the
# seeded defaults) supplies a row's displayed value when the operator hasn't
# overridden it. The row VALUE is baseline*override (override wins, jq `*`), but
# `overridden` reflects the OVERRIDE map only — so a seeded-but-untouched field
# shows its value with no ● until the operator edits it.
# =============================================================================

# shellcheck source=./state.sh
[[ "$(type -t cfgstate_get)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/state.sh"

# Field table — "section|path|label|default". The single source of truth for
# the covered fields; add a row here to surface a field in the menu.
_MENU_FIELDS=(
  "Host|system.hostname|hostname|"
  "Host|system.locale|locale|en_US.UTF-8"
  "Host|system.timezone|timezone|Europe/Bucharest"
  "Host|system.keymap|keymap|us"
  "Disks|filesystem|filesystem|zfs"
  "Disks|options.encryption|encryption|false"
  "Disks|options.impermanence.enabled|impermanence|false"
  "Disks|options.swap|swap|true"
  "Disks|options.swap_size|swap size|auto"
  "Disks|options.esp_size|esp size|2G"
  "Options|options.kernel|kernel|lts"
  "Options|options.bootloader|bootloader|systemd-boot"
  "Options|options.ssh.enabled|ssh|false"
  "Options|options.age_key_url|age key url|"
  "Options|sysctl|sysctl|"
  "Environment|environment.desktop|desktop|"
  "Environment|environment.gpu|gpu|auto"
  "Options|options.mirror_countries|mirror countries|Germany, Switzerland, Sweden, France, Romania"
  "Options|options.multilib|multilib|true"
  "Packages|packages.extra|extra packages|"
  "Packages|system_programs|system programs|"
  "Security|post_install.security|security extra|false"
  "Backup|post_install.backup|backup extra|false"
  "Users|users|users|"
)

# Configuration Categories — the eight top-level drill-in groups, in canonical
# order, each with a one-line summary. The category NAME matches a row's
# `section`, so a category aggregates its rows; the summary is display-only.
_MENU_CATEGORIES=(
  "Host|hostname, locale, timezone, keymap"
  "Disks|filesystem, encryption, swap, ESP"
  "Options|kernel, bootloader, ssh, mirrors, sysctl"
  "Environment|desktop, gpu"
  "Packages|extra packages, system programs"
  "Security|firewall, antivirus, rootkit, apparmor"
  "Backup|snapshots, encrypted backup"
  "Users|primary user, extra accounts"
)

# menu_categories <override> [<baseline>] — the top-level category rows (JSON
# array of {name, summary, overridden}), in canonical order. `overridden` is the
# fold of the category's field rows: true iff any descendant field is an
# override. No new state — it reads menu_rows's per-field ● flag.
menu_categories() {
  local rows; rows="$(menu_rows "$1" "${2:-{\}}")"
  local spec name summary overridden cats=()
  for spec in "${_MENU_CATEGORIES[@]}"; do
    IFS='|' read -r name summary <<<"$spec"
    if jq -e --arg s "$name" 'any(.[]; .section == $s and .overridden)' \
        <<<"$rows" >/dev/null; then
      overridden=true
    else
      overridden=false
    fi
    cats+=("$(jq -n --arg n "$name" --arg s "$summary" --argjson o "$overridden" \
      '{name:$n, summary:$s, overridden:$o}')")
  done
  printf '%s\n' "${cats[@]}" | jq -s '.'
}

# menu_rows <override> [<baseline>] — the menu rows on stdout (JSON array).
menu_rows() {
  local state="$1" baseline="${2:-{\}}"
  local spec section path label default value overridden
  local rows=()
  # The displayed value is baseline*override (override wins); ● is override-only.
  local merged; merged="$(jq -n --argjson b "$baseline" --argjson o "$state" \
    '$b * $o')"
  # Effective filesystem governs which Disks rows surface: Impermanence needs
  # native snapshots, so it is hidden for ext4 / xfs (ADR 0040).
  local fs; fs="$(cfgstate_get "$merged" filesystem)"
  [[ -n "$fs" ]] || fs="zfs"
  for spec in "${_MENU_FIELDS[@]}"; do
    IFS='|' read -r section path label default <<<"$spec"
    if [[ "$path" == "options.impermanence.enabled" \
          && ( "$fs" == "ext4" || "$fs" == "xfs" ) ]]; then
      continue
    fi
    # Multi-select fields (kernel / desktop / gpu) store a JSON array; render it
    # comma-joined so the row stays one scalar line, primary/first token first. A
    # map field (sysctl) renders as comma-joined key=value pairs.
    value="$(jq -r --arg p "$path" '
      getpath($p | split(".")) as $v
      | if   $v == null         then empty
        elif ($v | type) == "array"  then ($v | join(", "))
        elif ($v | type) == "object" then
          ([$v | to_entries[] | "\(.key)=\(.value)"] | join(", "))
        else ($v | tostring) end' <<<"$merged")"
    [[ -n "$value" ]] || value="$default"
    if cfgstate_is_overridden "$state" "$path"; then
      overridden=true
    else
      overridden=false
    fi
    rows+=("$(jq -n \
      --arg s "$section" --arg f "$path" --arg l "$label" \
      --arg v "$value" --argjson o "$overridden" \
      '{section:$s, field:$f, label:$l, value:$v, overridden:$o}')")
  done
  printf '%s\n' "${rows[@]}" | jq -s '.'
}

# menu_category_rows <category> <override> [<baseline>] — the field rows for one
# Configuration Category (the drill-in sub-menu), filtered from menu_rows by
# `section`. Same per-row shape as menu_rows.
menu_category_rows() {
  local category="$1"
  menu_rows "$2" "${3:-{\}}" | jq --arg c "$category" '[.[] | select(.section == $c)]'
}
