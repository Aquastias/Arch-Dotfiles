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
  "Packages|packages.extra|extra packages|[]"
  "Packages|system_programs|system programs|[]"
  "Security|post_install.security.firewall|firewall|firewalld"
  "Security|post_install.security.antivirus|antivirus|true"
  "Security|post_install.security.rootkit|rootkit|true"
  "Security|post_install.security.apparmor|apparmor|true"
  "Backup|post_install.backup.zfs_auto_snapshot|zfs snapshots|true"
  "Backup|post_install.backup.borg|borg|true"
  "Users|users|users|"
)

# menu_enum_options <field> — the canonical option set for an enumerable field,
# one per line. The single source of truth shared by the interactive controller
# (_ctl_enum_options / _ctl_toggle_options) and the replay editors
# (_guided_edit_*), so the two guided front-ends can never drift on what a field
# offers. Free-text / unknown fields emit nothing. Multi-word entries stay whole
# (one per line) — callers mapfile into an array before passing them on.
menu_enum_options() {
  case "$1" in
  options.kernel)                 printf '%s\n' lts default hardened zen ;;
  options.bootloader)             printf '%s\n' systemd-boot grub ;;
  environment.desktop)            printf '%s\n' kde hyprland ;;
  environment.gpu)                printf '%s\n' auto amd nvidia intel ;;
  post_install.security.firewall) printf '%s\n' firewalld ufw none ;;
  options.mirror_countries)
    printf '%s\n' Germany Switzerland Sweden France Romania Austria \
      Netherlands "United Kingdom" "United States" Japan Australia ;;
  esac
}

# Configuration Categories — the eight top-level drill-in groups, in canonical
# order, each with a one-line summary. The category NAME matches a row's
# `section`, so a category aggregates its rows; the summary is display-only.
_MENU_CATEGORIES=(
  "Host|hostname, locale, timezone, keymap"
  "Disks|layout, data pools, filesystem, encryption, swap"
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

# menu_render_value <config> <path> — the one-line rendering of <path>'s value in
# <config> (empty when unset). The single source of truth for how a field's value
# displays: multi-select arrays (kernel / desktop / gpu) render comma-joined,
# primary/first token first; a map (sysctl) renders comma-joined key=value pairs;
# scalars stringify. Shared by menu_rows (display) and the guided controller's
# apply-time normalise (so "matches the default" is judged the way it displays).
menu_render_value() {
  # shellcheck disable=SC2016 # $p/$v are jq vars, must not expand in the shell
  jq -r --arg p "$2" '
    getpath($p | split(".")) as $v
    | if   $v == null         then empty
      elif ($v | type) == "array"  then ($v | join(", "))
      elif ($v | type) == "object" then
        ([$v | to_entries[] | "\(.key)=\(.value)"] | join(", "))
      else ($v | tostring) end' <<<"$1"
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
    value="$(menu_render_value "$merged" "$path")"
    [[ -n "$value" ]] || value="$default"
    # ● is override-only: the apply-time normalise drops any override equal to the
    # baseline default, so the override map is a true delta and its presence is
    # exactly "the operator changed this away from the default".
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
