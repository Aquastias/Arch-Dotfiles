#!/usr/bin/env bash
# =============================================================================
# lib/guided-controller.sh — Guided Installer persistent-fzf controller (ADR 0042)
# =============================================================================
# Invoked by the single persistent fzf's reload/transform binds as SUBPROCESSES.
# It reads the navigation + Config-State files (paths in GUIDED_NAV_FILE /
# GUIDED_STATE_FILE / GUIDED_BASELINE_FILE), mutates them, and either prints the
# current screen's item list (guided_ctl_list, for `reload`) or a single
# navigation DIRECTIVE the launcher maps to fzf actions (guided_ctl_enter /
# guided_ctl_back). No fzf is needed to drive it — state files in, files + a
# directive out — so the dispatch is unit-testable without a tty.
#
# Slice-01 scope (PRD): navigation and enum (single-select) fields are handled
# natively (reload, no flash). Free-text AND multi-select fields temporarily
# emit `edit-oneshot <path>` so the launcher runs the existing one-shot helper;
# slices 02 (query line) and 03 (toggle screen) convert those to native.
#
# Directives (one per guided_ctl_enter / guided_ctl_back call):
#   render             re-list the current screen        (launcher → reload)
#   terminal <action>  exit with proceed|save|export     (launcher → result + accept)
#   edit-oneshot <path> free-text / multi edit           (launcher → execute + reload)
#   abort              cancel the whole menu             (launcher → abort)
#   noop               do nothing
# =============================================================================

# shellcheck source=lib/config/state.sh
[[ "$(type -t cfgstate_get)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/state.sh"
# shellcheck source=lib/config/nav.sh
[[ "$(type -t nav_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/nav.sh"
# shellcheck source=lib/config/edits.sh
[[ "$(type -t edit_set_bool)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/edits.sh"
# shellcheck source=lib/config/menu.sh
[[ "$(type -t menu_categories)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/menu.sh"

# The rule separating the categories from the terminal-action rows on the top
# screen (kept in lockstep with lib/guided.sh's _GUIDED_DIVIDER).
_CTL_DIVIDER="──────────────────────────"

# ── state-file accessors ─────────────────────────────────────────────────────
_ctl_state()    { printf '%s' "$(<"$GUIDED_STATE_FILE")"; }
_ctl_nav()      { printf '%s' "$(<"$GUIDED_NAV_FILE")"; }
_ctl_baseline() {
  if [[ -n "${GUIDED_BASELINE_FILE:-}" && -f "${GUIDED_BASELINE_FILE}" ]]; then
    printf '%s' "$(<"$GUIDED_BASELINE_FILE")"
  else
    printf '%s' '{}'
  fi
}
_ctl_write_state() { printf '%s\n' "$1" >"$GUIDED_STATE_FILE"; }
_ctl_write_nav()   { printf '%s\n' "$1" >"$GUIDED_NAV_FILE"; }

# _ctl_effective <state> <baseline> — the merged view (override wins).
_ctl_effective() { jq -n --argjson b "$2" --argjson o "$1" '$b * $o'; }

# ── field model ──────────────────────────────────────────────────────────────
# _ctl_field_kind <path> → text | enum | multi. text + multi route to one-shot
# in slice 01; enum is the native value picker. Everything not text/multi is an
# enum (filesystem, bootloader, firewall, and every bool).
_ctl_field_kind() {
  case "$1" in
  system.hostname | system.locale | system.timezone | system.keymap) echo text ;;
  options.swap_size | options.esp_size | options.age_key_url) echo text ;;
  sysctl | packages.extra) echo text ;;
  options.kernel | environment.desktop | environment.gpu) echo multi ;;
  options.mirror_countries | system_programs | users) echo multi ;;
  *) echo enum ;;
  esac
}

# _ctl_enum_options <path> → the value-picker lines for an enum field.
_ctl_enum_options() {
  case "$1" in
  filesystem) printf '%s\n' zfs 'btrfs (reserved)' 'ext4 (reserved)' \
    'xfs (reserved)' ;;
  options.bootloader) printf '%s\n' systemd-boot grub ;;
  post_install.security.firewall) printf '%s\n' firewalld ufw none ;;
  *) printf '%s\n' true false ;;
  esac
}

# _ctl_apply_enum <state> <path> <value> → new state. Reserved filesystems are a
# no-op (rc 1, unchanged). Bools route to edit_set_bool; the rest are scalars.
_ctl_apply_enum() {
  local state="$1" path="$2" val="$3"
  case "$path" in
  filesystem)
    [[ "$val" == "zfs" ]] || { printf '%s' "$state"; return 1; }
    edit_set_scalar "$state" filesystem zfs ;;
  options.bootloader | post_install.security.firewall)
    edit_set_scalar "$state" "$path" "$val" ;;
  *) edit_set_bool "$state" "$path" "$val" ;;
  esac
}

# _ctl_field_for_label <category> <label> → the dotted path of the row whose
# label matches (reverse lookup through the pure Menu model).
_ctl_field_for_label() {
  menu_category_rows "$1" "$(_ctl_state)" "$(_ctl_baseline)" \
    | jq -r --arg l "$2" 'first(.[] | select(.label == $l) | .field) // empty'
}

# ── list rendering (for fzf reload) ──────────────────────────────────────────
# guided_ctl_list — the current screen's item list on stdout.
guided_ctl_list() {
  local nav state base screen
  nav="$(_ctl_nav)"; state="$(_ctl_state)"; base="$(_ctl_baseline)"
  screen="$(nav_screen "$nav")"
  case "$screen" in
  top)
    menu_categories "$state" "$base" | jq -r \
      '.[] | "\(.name) — \(.summary)" + (if .overridden then "  ●" else "" end)'
    printf '%s\n' "$_CTL_DIVIDER" \
      "Proceed ▸ review & install" \
      "Save profile ▸ write a device-less profile" \
      "Export config ▸ write a device-baked config" ;;
  category)
    local cat; cat="$(nav_get "$nav" category)"
    menu_category_rows "$cat" "$state" "$base" | jq -r \
      '.[] | "\(.label): \(.value // "")" + (if .overridden then "  ●" else "" end)'
    if [[ "$cat" == "Disks" ]]; then
      printf '%s\n' "Disk layout ▸ choose preset"
      [[ "$(cfgstate_get "$(_ctl_effective "$state" "$base")" \
        options.impermanence.enabled)" == "true" ]] \
        && printf '%s\n' "Add persist directory ▸ extend the curated defaults"
    fi
    printf '%s\n' "← Back" ;;
  values)
    _ctl_enum_options "$(nav_get "$nav" field)"
    printf '%s\n' "← Back" ;;
  esac
}

# ── enter dispatch (one directive + a file mutation) ─────────────────────────
guided_ctl_enter() {
  local line="$1" screen; screen="$(nav_screen "$(_ctl_nav)")"
  case "$screen" in
  top)      _ctl_enter_top "$line" ;;
  category) _ctl_enter_category "$line" ;;
  values)   _ctl_enter_values "$line" ;;
  *)        echo noop ;;
  esac
}

_ctl_enter_top() {
  local line="$1" cat
  case "$line" in
  "$_CTL_DIVIDER")  echo noop ;;
  "Proceed"*)       echo "terminal proceed" ;;
  "Save profile"*)  echo "terminal save" ;;
  "Export config"*) echo "terminal export" ;;
  *)
    cat="${line%% *}"
    case "$cat" in
    Host | Disks | Options | Environment | Packages | Security | Backup | Users)
      _ctl_write_nav "$(nav_to_category "$cat")"; echo render ;;
    *) echo noop ;;
    esac ;;
  esac
}

_ctl_enter_category() {
  local line="$1" nav cat label path
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back")        _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "Disk layout"*)  echo "edit-oneshot __layout__"; return ;;
  "Add persist"*)  echo "edit-oneshot __persist__"; return ;;
  esac
  label="${line%%:*}"
  path="$(_ctl_field_for_label "$cat" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  if [[ "$(_ctl_field_kind "$path")" == "enum" ]]; then
    _ctl_write_nav "$(nav_to_values "$cat" "$path" "$label")"; echo render
  else
    echo "edit-oneshot $path"   # text + multi → one-shot (slice 01)
  fi
}

_ctl_enter_values() {
  local line="$1" nav path new
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  if new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$line")"; then
    _ctl_write_state "$new"
  fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# guided_ctl_back — Esc: back one screen, or abort the whole menu at the top.
guided_ctl_back() {
  local nav; nav="$(_ctl_nav)"
  if [[ "$(nav_screen "$nav")" == "top" ]]; then echo abort; return; fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# _guided_directive_to_action <directive> <entry> — map a controller directive
# to the fzf action string a `transform` bind executes. <entry> is the absolute
# path of the bind entry script. Pure (string → string); a terminal action
# writes the chosen verb to $GUIDED_RESULT_FILE then accepts (fzf exits), an
# edit-oneshot hands the tty to the existing one-shot helper then re-lists, and
# render re-lists in place (no new fzf, no flash).
_guided_directive_to_action() {
  local d="$1" entry="$2"
  case "$d" in
  render)           printf 'reload(bash %q list)' "$entry" ;;
  abort)            printf 'abort' ;;
  noop)             printf 'ignore' ;;
  "terminal "*)     printf 'execute-silent(printf %%s %q > %q)+accept' \
                      "${d#terminal }" "${GUIDED_RESULT_FILE:-/dev/null}" ;;
  "edit-oneshot "*) printf 'execute(bash %q oneshot %q)+reload(bash %q list)' \
                      "$entry" "${d#edit-oneshot }" "$entry" ;;
  *)                printf 'ignore' ;;
  esac
}
