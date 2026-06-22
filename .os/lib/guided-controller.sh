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
# Screens (nav.sh): top, category, values (enum pick), text (free-text typed
# INTO fzf's own query line — never leaves the window). Enter on a `values`/enum
# field and on `Disk layout` (native preset picker) commits in place; only the
# remaining MULTI fields (kernel/desktop/gpu/mirror_countries/system_programs/
# users) still emit `edit-oneshot` (slice 03 makes them a native toggle screen).
#
# Directives (one per guided_ctl_enter / guided_ctl_back call):
#   render             re-list + re-prompt + re-header the current screen
#   terminal <action>  exit with proceed|save|export     (launcher → result + accept)
#   edit-oneshot <path> one-shot helper hand-off          (launcher → execute + reload)
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
# shellcheck source=lib/config/skeleton.sh
[[ "$(type -t skeleton_preset)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/skeleton.sh"

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
# _ctl_field_kind <path> → text | enum | multi. text → native query-line editor;
# enum → native value picker; multi → one-shot (slice 03). Everything not
# text/multi is an enum (filesystem, bootloader, firewall, and every bool).
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

# _ctl_enum_options <path> → the value-picker lines for an enum field (or the
# synthetic __layout__ disk-layout preset list).
_ctl_enum_options() {
  case "$1" in
  __layout__) printf '%s\n' single os-mirror os-mirror-raidz1 data-pools ;;
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

# _ctl_apply_text <state> <path> <value> → new state for a free-text field.
# sysctl parses key=value; packages.extra appends; the rest are string scalars.
_ctl_apply_text() {
  local state="$1" path="$2" val="$3"
  case "$path" in
  sysctl)
    [[ "$val" == *=* ]] || { printf '%s' "$state"; return 1; }
    edit_set_sysctl "$state" "${val%%=*}" "${val#*=}" ;;
  packages.extra) edit_append_packages "$state" "$val" ;;
  *) edit_set_scalar "$state" "$path" "$val" ;;
  esac
}

# _ctl_field_for_label <category> <label> → the dotted path of the row whose
# label matches (reverse lookup through the pure Menu model).
_ctl_field_for_label() {
  menu_category_rows "$1" "$(_ctl_state)" "$(_ctl_baseline)" \
    | jq -r --arg l "$2" 'first(.[] | select(.label == $l) | .field) // empty'
}

# ── per-screen header + prompt (so every screen says how to go back) ─────────
_ctl_nav_header() {
  case "$(nav_screen "$1")" in
  top)      printf 'Enter open   Esc quit' ;;
  category) printf 'Enter edit   Esc back' ;;
  values)   printf 'Enter choose   Esc back' ;;
  text)     printf 'Type a value, Enter save   Esc back' ;;
  *)        printf 'Esc back' ;;
  esac
}
_ctl_nav_prompt() {
  case "$(nav_screen "$1")" in
  top)         printf 'guided> ' ;;
  category)    printf '%s> ' "$(nav_get "$1" category)" ;;
  values|text) printf '%s> ' "$(nav_get "$1" label)" ;;
  *)           printf 'guided> ' ;;
  esac
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
  text)
    local path cur
    path="$(nav_get "$nav" field)"
    cur="$(cfgstate_get "$(_ctl_effective "$state" "$base")" "$path")"
    printf 'current: %s\n' "${cur:-(unset)}"
    printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
  esac
}

# ── enter dispatch (one directive + a file mutation) ─────────────────────────
# guided_ctl_enter <line> [<query>] — <query> is fzf's typed text, used only on
# the text screen (the value being entered).
guided_ctl_enter() {
  local line="$1" query="${2:-}" screen; screen="$(nav_screen "$(_ctl_nav)")"
  case "$screen" in
  top)      _ctl_enter_top "$line" ;;
  category) _ctl_enter_category "$line" ;;
  values)   _ctl_enter_values "$line" ;;
  text)     _ctl_enter_text "$query" ;;
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
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "Disk layout"*)
    _ctl_write_nav "$(nav_to_values "$cat" __layout__ "Disk layout")"
    echo render; return ;;
  "Add persist"*)
    echo "edit-oneshot __persist__"; return ;;
  esac
  label="${line%%:*}"
  path="$(_ctl_field_for_label "$cat" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  case "$(_ctl_field_kind "$path")" in
  enum) _ctl_write_nav "$(nav_to_values "$cat" "$path" "$label")"; echo render ;;
  text) _ctl_write_nav "$(nav_to_text "$cat" "$path" "$label")"; echo render ;;
  *)    echo "edit-oneshot $path" ;;   # multi → one-shot (slice 03)
  esac
}

_ctl_enter_values() {
  local line="$1" nav path sk new
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  if [[ "$path" == "__layout__" ]]; then
    if sk="$(skeleton_preset "$line" 2>/dev/null)"; then
      _ctl_write_state "$(edit_apply_skeleton "$(_ctl_state)" "$sk")"
    fi
  elif new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$line")"; then
    _ctl_write_state "$new"
  fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# _ctl_enter_text <query> — commit the typed query into the field, then back.
# Empty query (Esc-less cancel via Enter) just returns without a change.
_ctl_enter_text() {
  local query="$1" nav path
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  [[ -n "$query" ]] \
    && _ctl_write_state "$(_ctl_apply_text "$(_ctl_state)" "$path" "$query")"
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
# path of the bind entry script. A `render` re-lists AND re-headers/re-prompts
# the (post-mutation) screen so the toolbar always reflects "how to go back";
# a terminal action writes the verb to $GUIDED_RESULT_FILE then accepts; an
# edit-oneshot hands the tty to the existing helper then re-lists.
_guided_directive_to_action() {
  local d="$1" entry="$2" nav
  case "$d" in
  render)
    nav="$(_ctl_nav)"
    printf 'reload(bash %q list)+change-header(%s)+change-prompt(%s)' \
      "$entry" "$(_ctl_nav_header "$nav")" "$(_ctl_nav_prompt "$nav")" ;;
  abort)            printf 'abort' ;;
  noop)             printf 'ignore' ;;
  "terminal "*)     printf 'execute-silent(printf %%s %q > %q)+accept' \
                      "${d#terminal }" "${GUIDED_RESULT_FILE:-/dev/null}" ;;
  "edit-oneshot "*) printf 'execute(bash %q oneshot %q)+reload(bash %q list)' \
                      "$entry" "${d#edit-oneshot }" "$entry" ;;
  *)                printf 'ignore' ;;
  esac
}
