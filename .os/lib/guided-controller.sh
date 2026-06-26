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
# Screens (nav.sh): top, category, values (enum picks, multi-select toggles, the
# sysctl + users list editors, the Disk-layout preset picker), text (free-text
# typed INTO fzf's own query line). EVERYTHING commits in place now — enum picks,
# toggles, layout presets, sysctl pairs, user toggle + create, Add-persist, and
# every free-text field — so the menu never leaves fzf. (The `edit-oneshot`
# directive remains only as an unused fallback seam.) ^Z/^Y/^R drive
# undo/redo/reset over a snapshot history.
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
# shellcheck source=lib/config/history.sh
[[ "$(type -t hist_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/history.sh"

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
  system.hostname) echo text ;;
  system.keymap) echo toggle ;;   # multi: select several keymaps (element 0 = default)
  system.locale | system.timezone) echo biglist ;;
  options.swap_size | options.esp_size | options.age_key_url) echo text ;;
  packages.extra) echo text ;;
  sysctl) echo list ;;   # a list of key=value pairs + an Add action
  options.kernel | environment.desktop | environment.gpu) echo toggle ;;
  options.mirror_countries | system_programs) echo toggle ;;
  users) echo users ;;   # toggle existing users + in-fzf create
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

# _ctl_biglist_options <path> → the big, filterable option set for a system
# identity field, from the live system (localectl/timedatectl) with a filesystem
# fallback (the install host is the Arch live ISO; the fallback also covers a dev
# box where the systemd commands return nothing).
_ctl_biglist_options() {
  local out
  case "$1" in
  system.keymap)
    out="$(localectl list-keymaps 2>/dev/null)"
    [[ -n "$out" ]] || out="$(find /usr/share/kbd/keymaps -name '*.map.gz' \
      -printf '%f\n' 2>/dev/null | sed 's/\.map\.gz$//' | sort -u)" ;;
  system.timezone)
    out="$(timedatectl list-timezones 2>/dev/null)"
    [[ -n "$out" ]] || out="$(find /usr/share/zoneinfo -type f -printf '%P\n' \
      2>/dev/null | grep -E '^[A-Z][A-Za-z_]+/' | sort)" ;;
  system.locale)
    out="$(awk '{print $1}' /usr/share/i18n/SUPPORTED 2>/dev/null | sort -u)"
    [[ -n "$out" ]] || out="$(localectl list-locales 2>/dev/null)" ;;
  esac
  [[ -n "$out" ]] && printf '%s\n' "$out"
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
  __persist__)    edit_append_persist "$state" "$val" ;;
  __newuser__)
    # create: add the typed name to the user list (dedup); a default profile is
    # materialized at Proceed/Save for any name without a committed profile.
    [[ -n "$val" ]] || { printf '%s' "$state"; return 1; }
    local _cur; _cur="$(jq -c '.users // []' \
      <<<"$(_ctl_effective "$state" "$(_ctl_baseline)")")"
    cfgstate_set "$state" users "$(jq -cn --argjson a "$_cur" --arg v "$val" \
      'if any($a[]; . == $v) then $a else ($a + [$v]) end')" ;;
  sysctl)
    [[ "$val" == *=* ]] || { printf '%s' "$state"; return 1; }
    edit_set_sysctl "$state" "${val%%=*}" "${val#*=}" ;;
  packages.extra) edit_append_packages "$state" "$val" ;;
  *) edit_set_scalar "$state" "$path" "$val" ;;
  esac
}

# _ctl_program_names — resolvable System Program names (programs/<cat>/<name>),
# one per line; the toggle option set for system_programs.
_ctl_program_names() {
  local d
  for d in "${OS_DIR:-.}"/programs/*/*; do
    [[ -d "$d" ]] && basename "$d"
  done
}

# _ctl_toggle_options <field> → the raw option lines for a toggle (multi) field.
_ctl_toggle_options() {
  case "$1" in
  options.kernel)      printf '%s\n' lts default hardened zen ;;
  environment.desktop) printf '%s\n' kde hyprland ;;
  environment.gpu)     printf '%s\n' auto amd nvidia intel ;;
  options.mirror_countries)
    printf '%s\n' Germany Switzerland Sweden France Romania Austria \
      Netherlands "United Kingdom" "United States" Japan Australia ;;
  system_programs)     _ctl_program_names ;;
  system.keymap)       _ctl_biglist_options system.keymap ;;
  esac
}

# _ctl_field_has_preview <field> → rc 0 if this values screen shows a side panel
# (the layout graph, or the selection panel for the big keymap/locale/timezone).
_ctl_field_has_preview() {
  case "$1" in
  __layout__ | system.keymap | system.locale | system.timezone) return 0 ;;
  *) return 1 ;;
  esac
}

# _ctl_marked_options <field> <state> <base> — each option prefixed [x]/[ ] by
# whether it is currently selected (gpu's scalar "auto" counts as an array).
_ctl_marked_options() {
  local field="$1" state="$2" base="$3" sel opt
  sel="$(jq -c --arg p "$field" \
    'getpath($p | split(".")) // [] | if type == "array" then . else [.] end' \
    <<<"$(_ctl_effective "$state" "$base")")"
  while IFS= read -r opt; do
    # jq -n (null input) so it does NOT consume the loop's stdin (the option list)
    if jq -ne --argjson s "$sel" --arg o "$opt" 'any($s[]; . == $o)' \
        >/dev/null 2>&1; then
      printf '[x] %s\n' "$opt"
    else
      printf '[ ] %s\n' "$opt"
    fi
  done < <(_ctl_toggle_options "$field")
}

# _ctl_toggle_multi <state> <base> <field> <value> → flip <value>'s membership in
# the field's array (computed against the EFFECTIVE value so a seeded baseline is
# honoured), written back as an override; an empty result unsets the override.
# gpu is mutually-exclusive with "auto" and normalizes to scalar "auto" / a
# vendor array / unset.
_ctl_toggle_multi() {
  local state="$1" base="$2" field="$3" val="$4" eff cur new
  eff="$(_ctl_effective "$state" "$base")"
  if [[ "$field" == "environment.gpu" ]]; then
    cur="$(jq -c '.environment.gpu // [] | if type == "array" then . else [.] end' \
      <<<"$eff")"
    new="$(jq -cn --argjson a "$cur" --arg v "$val" '
      if $v == "auto"
        then (if any($a[]; . == "auto") then [] else ["auto"] end)
        else (($a - ["auto"]) as $c
              | if any($c[]; . == $v) then ($c - [$v]) else ($c + [$v]) end)
      end')"
    case "$new" in
    '["auto"]') cfgstate_set   "$state" environment.gpu '"auto"' ;;
    '[]')       cfgstate_unset "$state" environment.gpu ;;
    *)          cfgstate_set   "$state" environment.gpu "$new" ;;
    esac
    return
  fi
  cur="$(jq -c --arg p "$field" \
    'getpath($p | split(".")) // [] | if type == "array" then . else [.] end' \
    <<<"$eff")"
  new="$(jq -cn --argjson a "$cur" --arg v "$val" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  if [[ "$new" == '[]' ]]; then
    cfgstate_unset "$state" "$field"
  else
    cfgstate_set "$state" "$field" "$new"
  fi
}

# _ctl_sysctl_lines <state> <base> → the current sysctl pairs ("key=value"), one
# per line, from the effective view (so the seeded vm.swappiness=10 shows up).
_ctl_sysctl_lines() {
  jq -r '(.sysctl // {}) | to_entries[] | "\(.key)=\(.value)"' \
    <<<"$(_ctl_effective "$1" "$2")"
}

# _ctl_user_names → committed user names (users/<name>/profile.jsonc, minus core).
_ctl_user_names() {
  local d n
  for d in "${OS_DIR:-.}"/users/*/; do
    [[ -d "$d" ]] || continue
    n="$(basename "$d")"
    [[ "$n" == "core" ]] && continue
    [[ -f "${d}profile.jsonc" ]] && printf '%s\n' "$n"
  done
}

# _ctl_user_marked <state> <base> — the user toggle list: every committed user
# UNION the currently-selected names (so a just-created name shows), each marked
# [x]/[ ] by membership in the effective .users.
_ctl_user_marked() {
  local sel opt; sel="$(jq -c '.users // []' <<<"$(_ctl_effective "$1" "$2")")"
  { _ctl_user_names; jq -r '.[]' <<<"$sel"; } | awk '!seen[$0]++' \
  | while IFS= read -r opt; do
      if jq -ne --argjson s "$sel" --arg o "$opt" 'any($s[]; . == $o)' \
          >/dev/null 2>&1; then
        printf '[x] %s\n' "$opt"
      else
        printf '[ ] %s\n' "$opt"
      fi
    done
}

# _ctl_toggle_users <state> <base> <name> — flip <name> in the effective .users,
# written as the FULL override array (replacing the seeded baseline) — and never
# unset, so toggling the last user off truly yields an empty user list.
_ctl_toggle_users() {
  local state="$1" base="$2" name="$3" cur new
  cur="$(jq -c '.users // []' <<<"$(_ctl_effective "$state" "$base")")"
  new="$(jq -cn --argjson a "$cur" --arg v "$name" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  cfgstate_set "$state" users "$new"
}

# _ctl_field_for_label <category> <label> → the dotted path of the row whose
# label matches (reverse lookup through the pure Menu model).
_ctl_field_for_label() {
  menu_category_rows "$1" "$(_ctl_state)" "$(_ctl_baseline)" \
    | jq -r --arg l "$2" 'first(.[] | select(.label == $l) | .field) // empty'
}

# _ctl_field_display <path> <state> <base> → the field's menu-displayed value
# (effective value, else its menu default), so the text screen's "current:" hint
# reflects a defaulted field (e.g. 2G) instead of "(unset)".
_ctl_field_display() {
  menu_rows "$2" "$3" \
    | jq -r --arg p "$1" 'first(.[] | select(.field == $p) | .value) // ""'
}

# ── per-screen header + prompt (so every screen says how to go back) ─────────
_ctl_nav_header() {
  local b
  case "$(nav_screen "$1")" in
  top)      b='Enter open   Esc quit' ;;
  category) b='Enter edit   Esc back' ;;
  values)
    if [[ "$(_ctl_field_kind "$(nav_get "$1" field)")" == "toggle" ]]; then
      b='Enter toggle ✓   Esc done'
    else
      b='Enter choose   Esc back'
    fi ;;
  text)     b='Type a value, Enter save   Esc back' ;;
  datapools) b='Enter open/add   Esc back' ;;
  pooledit)  b='Enter cycle/remove   Esc back' ;;
  *)        b='Esc back' ;;
  esac
  printf '%s   ·   ^Z undo  ^Y redo  ^R reset' "$b"
}
_ctl_nav_prompt() {
  case "$(nav_screen "$1")" in
  top)         printf 'guided> ' ;;
  category)    printf '%s> ' "$(nav_get "$1" category)" ;;
  values|text) printf '%s> ' "$(nav_get "$1" label)" ;;
  datapools)   printf 'data pools> ' ;;
  pooledit)    printf 'pool> ' ;;
  *)           printf 'guided> ' ;;
  esac
}

# _ctl_layout_label <effective-json> → a one-line description of the current disk
# layout, so the Disks "Disk layout" row reflects the chosen preset instead of a
# static "choose preset". single → "single"; multi → "os <topo> ×<n>" plus any
# storage / data pool counts.
_ctl_layout_label() {
  jq -r '
    if (.mode // "single") != "multi" then "single disk"
    else
      "OS: \(.os_pool.disk_count // "?") disks (\(.os_pool.topology // "?"))"
      + ((.storage_groups // [])
         | map(" + \(.name): \(.disk_count) disks (\(.topology))") | join(""))
      + ((.data_pools // [])
         | map(" + \(.name): \(.disk_count) disks (\(.topology))") | join(""))
    end' <<<"$1"
}

# _ctl_layout_graph <skeleton-json> → an ASCII tree of the layout for the preview
# pane (a pool per line + its topology / disk count).
_ctl_layout_graph() {
  jq -r '
    def pool(name; role; topo; n):
      "  ▸ \(name)  (\(role))\n      └─ "
      + (if topo == null or topo == "none" then "\(n) disk(s)"
         else "\(topo) · \(n) disk(s)" end);
    if (.mode // "single") != "multi" then
      "Single-disk ZFS\n\n" + pool("rpool"; "OS root"; null; 1)
    else
      "Multi-disk ZFS\n\n"
      + pool(.os_pool.pool_name // "rpool"; "OS root";
             .os_pool.topology; .os_pool.disk_count)
      + ((.storage_groups // [])
         | map("\n" + pool(.name; "storage → \(.mount)"; .topology; .disk_count))
         | join(""))
      + ((.data_pools // [])
         | map("\n" + pool(.name; "data pool"; .topology; .disk_count))
         | join(""))
    end' <<<"$1"
}

# _ctl_add_data_pool <state> → state with one more data pool appended (auto-named
# tank<N>, default mirror ×2), forcing multi mode + a default OS pool. Shared by
# the data-pools editor's "+ Add" and by picking "data-pools" in the layout.
_ctl_add_data_pool() {
  jq '
    (.data_pools // []) as $dp
    | .data_pools = ($dp + [{name:("tank" + (($dp | length) | tostring)),
                             topology:"mirror", disk_count:2}])
    | .mode = "multi"
    | (if .os_pool then . else
        .os_pool = {pool_name:"rpool", topology:"none", disk_count:1} end)
    ' <<<"$1"
}

# guided_ctl_preview <line> — the fzf preview body: the layout graph for the
# highlighted preset, but ONLY on the Disk-layout screen (empty elsewhere, so the
# preview is a no-op on every other screen).
guided_ctl_preview() {
  local line="$1" nav field
  nav="$(_ctl_nav)"
  [[ "$(nav_screen "$nav")" == "values" ]] || return 0
  field="$(nav_get "$nav" field)"
  case "$field" in
  __layout__)
    local sk; sk="$(skeleton_preset "$line" 2>/dev/null)" || return 0
    _ctl_layout_graph "$sk" ;;
  system.keymap)
    # multi: the selected keymap array (+ the highlighted candidate, mark stripped)
    local sel; sel="$(jq -r \
      '.system.keymap // [] | if type == "array" then . else [.] end | .[]' \
      <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")"
    printf 'Selected keymaps:\n'
    if [[ -n "$sel" ]]; then sed 's/^/  /' <<<"$sel"; else printf '  (none)\n'; fi
    printf '\nHighlighted:\n  %s\n' "${line:4}" ;;
  system.locale | system.timezone)
    local cur; cur="$(_ctl_field_display "$field" "$(_ctl_state)" "$(_ctl_baseline)")"
    printf 'Selected %s:\n  %s\n\nHighlighted:\n  %s\n' \
      "$(nav_get "$nav" label)" "${cur:-(none)}" "$line" ;;
  esac
}

# ── list rendering (for fzf reload) ──────────────────────────────────────────
# guided_ctl_list — the current screen's item list on stdout.
guided_ctl_list() {
  _ctl_autocommit   # snapshot any edit for undo/redo (single choke point)
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
    # Disks leads with the layout row (the headline storage choice), then fields.
    if [[ "$cat" == "Disks" ]]; then
      local _ov=""
      jq -e '.os_pool or .mode or .storage_groups or .data_pools' \
        <<<"$state" >/dev/null 2>&1 && _ov="  ●"
      printf 'layout: %s%s\n' \
        "$(_ctl_layout_label "$(_ctl_effective "$state" "$base")")" "$_ov"
    fi
    menu_category_rows "$cat" "$state" "$base" | jq -r \
      '.[] | "\(.label): \(.value // "")" + (if .overridden then "  ●" else "" end)'
    if [[ "$cat" == "Disks" ]]; then
      [[ "$(cfgstate_get "$(_ctl_effective "$state" "$base")" \
        options.impermanence.enabled)" == "true" ]] \
        && printf '%s\n' "Add persist directory ▸ extend the curated defaults"
    fi
    printf '%s\n' "← Back" ;;
  values)
    local vf; vf="$(nav_get "$nav" field)"
    if [[ "$vf" == "sysctl" ]]; then
      _ctl_sysctl_lines "$state" "$base"
      printf '%s\n' "+ Add sysctl (key=value)"
    elif [[ "$vf" == "users" ]]; then
      _ctl_user_marked "$state" "$base"
      printf '%s\n' "+ Create user (name)"
    elif [[ "$(_ctl_field_kind "$vf")" == "biglist" ]]; then
      _ctl_biglist_options "$vf"
    elif [[ "$(_ctl_field_kind "$vf")" == "toggle" ]]; then
      _ctl_marked_options "$vf" "$state" "$base"
    else
      _ctl_enum_options "$vf"
    fi
    printf '%s\n' "← Back" ;;
  text)
    local path cur
    path="$(nav_get "$nav" field)"
    # the menu-displayed value (effective, else the field default) so a defaulted
    # field shows e.g. "current: 2G" rather than "current: (unset)".
    cur="$(_ctl_field_display "$path" "$state" "$base")"
    printf 'current: %s\n' "${cur:-(unset)}"
    printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
  datapools)
    jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
      <<<"$(_ctl_effective "$state" "$base")"
    printf '%s\n' "+ Add data pool" "← Back" ;;
  pooledit)
    local i p
    i="$(nav_get "$nav" index)"
    p="$(jq -c --argjson i "$i" '.data_pools[$i] // {}' \
      <<<"$(_ctl_effective "$state" "$base")")"
    printf 'name: %s\n' "$(jq -r '.name // "?"' <<<"$p")"
    printf 'topology: %s   (Enter cycles)\n' "$(jq -r '.topology // "?"' <<<"$p")"
    printf 'disks: %s   (Enter cycles 1-8)\n' "$(jq -r '.disk_count // "?"' <<<"$p")"
    printf '%s\n' "✗ remove this pool" "← Back" ;;
  esac
}

# ── enter dispatch (one directive + a file mutation) ─────────────────────────
# guided_ctl_enter <line> [<query>] — <query> is fzf's typed text, used only on
# the text screen (the value being entered).
guided_ctl_enter() {
  local line="$1" query="${2:-}" screen; screen="$(nav_screen "$(_ctl_nav)")"
  case "$screen" in
  top)       _ctl_enter_top "$line" ;;
  category)  _ctl_enter_category "$line" ;;
  values)    _ctl_enter_values "$line" ;;
  text)      _ctl_enter_text "$query" ;;
  datapools) _ctl_enter_datapools "$line" ;;
  pooledit)  _ctl_enter_pooledit "$line" ;;
  *)         echo noop ;;
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
  "layout:"*)
    _ctl_write_nav "$(nav_to_values "$cat" __layout__ "layout")"
    echo render; return ;;
  "Add persist"*)
    _ctl_write_nav "$(nav_to_text "$cat" __persist__ "persist dir")"
    echo render; return ;;
  esac
  label="${line%%:*}"
  path="$(_ctl_field_for_label "$cat" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  case "$(_ctl_field_kind "$path")" in
  enum | toggle | list | users | biglist)
    _ctl_write_nav "$(nav_to_values "$cat" "$path" "$label")"; echo render ;;
  text)
    _ctl_write_nav "$(nav_to_text "$cat" "$path" "$label")"; echo render ;;
  *)
    echo "edit-oneshot $path" ;;   # fallback seam — no field reaches it now
  esac
}

_ctl_enter_values() {
  local line="$1" nav path sk new
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "toggle" ]]; then
    # strip the "[x] "/"[ ] " mark, flip membership, and STAY on the screen so
    # the operator can toggle several. `refresh` (reload-sync, query/header kept)
    # re-marks the list in place without the flicker — and crucially without
    # clearing a filter the operator typed on a long list (e.g. mirror countries).
    _ctl_write_state "$(_ctl_toggle_multi "$(_ctl_state)" "$(_ctl_baseline)" \
      "$path" "${line:4}")"
    echo refresh; return
  fi
  if [[ "$path" == "sysctl" ]]; then
    if [[ "$line" == "+ Add"* ]]; then
      _ctl_write_nav "$(nav_to_text "$(nav_get "$nav" category)" sysctl sysctl)"
      echo render; return
    fi
    echo refresh; return   # an existing pair is display-only (re-list in place)
  fi
  if [[ "$path" == "users" ]]; then
    if [[ "$line" == "+ Create"* ]]; then
      _ctl_write_nav \
        "$(nav_to_text "$(nav_get "$nav" category)" __newuser__ "new user")"
      echo render; return
    fi
    _ctl_write_state "$(_ctl_toggle_users "$(_ctl_state)" "$(_ctl_baseline)" \
      "${line:4}")"
    echo refresh; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "biglist" ]]; then
    # a big filterable list → set the picked value as a scalar, then back
    _ctl_write_state "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")"
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  if [[ "$path" == "__layout__" ]]; then
    if [[ "$line" == "data-pools" ]]; then
      # "data-pools" is the door to the editor (the pools live under layout, not a
      # separate row): seed one pool if there are none yet, then open the editor.
      [[ "$(jq '(.data_pools // []) | length' <<<"$(_ctl_state)")" == "0" ]] \
        && _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"
      _ctl_write_nav "$(nav_to_datapools "$(nav_get "$nav" category)")"
      echo render; return
    fi
    if sk="$(skeleton_preset "$line" 2>/dev/null)"; then
      _ctl_write_state "$(edit_apply_skeleton "$(_ctl_state)" "$sk")"
    fi
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  if new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$line")"; then
    _ctl_write_state "$new"
  fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# _ctl_enter_text <query> — commit the typed query into the field, then back.
# Empty query (Esc-less cancel via Enter) just returns without a change.
_ctl_enter_text() {
  local query="$1" nav path cat
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  cat="$(nav_get "$nav" category)"
  [[ -n "$query" ]] \
    && _ctl_write_state "$(_ctl_apply_text "$(_ctl_state)" "$path" "$query")"
  # sysctl / create-user were reached from a list screen — return there so the
  # new entry shows and more can be added; every other text field backs out.
  case "$path" in
  sysctl)      _ctl_write_nav "$(nav_to_values "$cat" sysctl sysctl)" ;;
  __newuser__) _ctl_write_nav "$(nav_to_values "$cat" users users)" ;;
  *)           _ctl_write_nav "$(nav_back "$nav")" ;;
  esac
  echo render
}

# _ctl_enter_datapools <line> — the data-pools list editor: add a tank<N> pool
# (auto-named, default mirror ×2; forces multi + a default OS pool), or open a
# pool by name. STAYS on the list after an add (refresh).
_ctl_enter_datapools() {
  local line="$1" nav cat name idx
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back") _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "+ Add"*)
    _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"
    echo refresh; return ;;
  esac
  name="${line%%:*}"
  idx="$(jq -r --arg n "$name" \
    '[(.data_pools // [])[] | .name] | (index($n) // -1)' <<<"$(_ctl_state)")"
  if [[ "$idx" =~ ^[0-9]+$ ]]; then
    _ctl_write_nav "$(nav_to_pooledit "$cat" "$idx")"; echo render; return
  fi
  echo refresh
}

# _ctl_enter_pooledit <line> — edit data_pools[index]: cycle topology
# (stripe→mirror→raidz1→raidz2), cycle the disk count (1-8), or remove the pool.
_ctl_enter_pooledit() {
  local line="$1" nav cat i
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"; i="$(nav_get "$nav" index)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_to_datapools "$cat")"; echo render; return ;;
  "✗ remove"*)
    _ctl_write_state "$(jq --argjson i "$i" 'del(.data_pools[$i])' \
      <<<"$(_ctl_state)")"
    _ctl_write_nav "$(nav_to_datapools "$cat")"; echo render; return ;;
  "topology:"*)
    _ctl_write_state "$(jq --argjson i "$i" '
      .data_pools[$i].topology |=
        ({"stripe":"mirror","mirror":"raidz1","raidz1":"raidz2",
          "raidz2":"stripe"}[.] // "mirror")' <<<"$(_ctl_state)")"
    echo refresh; return ;;
  "disks:"*)
    _ctl_write_state "$(jq --argjson i "$i" \
      '.data_pools[$i].disk_count |= (if . >= 8 then 1 else . + 1 end)' \
      <<<"$(_ctl_state)")"
    echo refresh; return ;;
  esac
  echo refresh
}

# guided_ctl_back — Esc: back one screen, or abort the whole menu at the top.
guided_ctl_back() {
  local nav; nav="$(_ctl_nav)"
  if [[ "$(nav_screen "$nav")" == "top" ]]; then echo abort; return; fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# ── undo / redo / reset history (slice 03) ───────────────────────────────────
# Snapshots live in $GUIDED_HIST_FILE; _ctl_autocommit pushes one whenever the
# Config State changed since the last snapshot. It runs from guided_ctl_list —
# the single choke point every edit funnels through on its render — so toggles,
# value picks, text, and even one-shot edits are all captured as one undo step
# without sprinkling commits across the dispatch.
_ctl_autocommit() {
  [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]] || return 0
  local hist now prev
  hist="$(<"$GUIDED_HIST_FILE")"
  now="$(_ctl_state | jq -cS .)"
  prev="$(hist_present "$hist" | jq -cS .)"
  [[ "$now" == "$prev" ]] && return 0
  hist_commit "$hist" "$(_ctl_state)" >"$GUIDED_HIST_FILE"
}

# guided_ctl_key <ctrl-z|ctrl-y|ctrl-r> — the global toolbar keys. ^Z undoes /
# ^Y redoes over the snapshot stack; ^R resets every override back to the seeded
# launch state (itself undoable — ^Z brings it back, so no confirm is needed).
# Each restores the Config State from the stack and re-renders in place.
guided_ctl_key() {
  local k="$1" hist
  [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]] || { echo noop; return; }
  hist="$(<"$GUIDED_HIST_FILE")"
  case "$k" in
  ctrl-z) hist="$(hist_undo "$hist")" ;;
  ctrl-y) hist="$(hist_redo "$hist")" ;;
  ctrl-r) hist="$(hist_commit "$hist" '{}')" ;;
  *)      echo noop; return ;;
  esac
  printf '%s\n' "$hist" >"$GUIDED_HIST_FILE"
  _ctl_write_state "$(hist_present "$hist")"
  echo render
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
    # clear-query first: fzf keeps the filter text across reload, so a leftover
    # filter would hide the next screen's items (e.g. typing "disk" then opening
    # the preset picker would hide every preset). Each screen starts unfiltered.
    # The Disk-layout screen turns on a preview (the ASCII layout graph); every
    # other screen swaps the preview to a cheap no-op and hides the pane, so the
    # graph command only runs where it's shown.
    nav="$(_ctl_nav)"
    local pv _showpv=0
    if [[ "$(nav_screen "$nav")" == "values" ]]; then
      _ctl_field_has_preview "$(nav_get "$nav" field)" && _showpv=1
    fi
    if ((_showpv)); then
      pv="$(printf '+change-preview(bash %q preview {})+change-preview-window(right,45%%)' \
        "$entry")"
    else
      pv='+change-preview(echo)+change-preview-window(hidden)'
    fi
    printf 'clear-query+reload(bash %q list)+change-header(%s)+change-prompt(%s)%s' \
      "$entry" "$(_ctl_nav_header "$nav")" "$(_ctl_nav_prompt "$nav")" "$pv" ;;
  refresh)
    # same screen, just re-mark the list: reload-sync avoids the flicker a plain
    # reload shows, and keeps the query + header (no clear-query/change-*).
    printf 'reload-sync(bash %q list)' "$entry" ;;
  abort)            printf 'abort' ;;
  noop)             printf 'ignore' ;;
  "terminal "*)     printf 'execute-silent(printf %%s %q > %q)+accept' \
                      "${d#terminal }" "${GUIDED_RESULT_FILE:-/dev/null}" ;;
  "edit-oneshot "*) printf \
                      'execute(bash %q oneshot %q)+clear-query+reload(bash %q list)' \
                      "$entry" "${d#edit-oneshot }" "$entry" ;;
  *)                printf 'ignore' ;;
  esac
}
