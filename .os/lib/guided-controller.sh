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
# shellcheck source=lib/picker.sh
[[ "$(type -t picker_enum_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/picker.sh"
# shellcheck source=lib/config/history.sh
[[ "$(type -t hist_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/history.sh"

# The rule separating the categories from the terminal-action rows on the top
# screen.
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

# _ctl_built_root_filesystems — the root filesystems whose Root Layout Adapter is
# BUILT, one per line (issue 09). Kept in lockstep with lib/layout/dispatch.sh's
# root_adapter_source (the dispatch is the source of truth for what's built);
# the guided layer lists a value only when the operator can actually install it.
_ctl_built_root_filesystems() { printf '%s\n' zfs btrfs ext4 xfs; }

# _ctl_topologies_for_fs <fs> → the ordered topology cycle for a group of that
# filesystem (issue 09), matching the validation contract in
# lib/config/validation.sh::_validation_topology_for_fs. zfs keeps
# mirror/raidz/stripe; btrfs offers native raid; ext4/xfs are single-disk only.
# The order is the cycle order — the zfs list ends in `stripe` so the historical
# stripe→mirror wrap is preserved.
_ctl_topologies_for_fs() {
  case "$1" in
  btrfs)      printf '%s\n' single raid0 raid1 raid10 ;;
  ext4 | xfs) printf '%s\n' single ;;
  *)          printf '%s\n' mirror raidz1 raidz2 stripe ;;
  esac
}

# _ctl_cycle_next <current> <item...> → the item after <current> (wrapping); the
# first item when <current> is absent. The shared cycle primitive behind the pool
# editor's topology and filesystem rows.
_ctl_cycle_next() {
  local cur="$1"; shift; local -a list=("$@"); local i
  for i in "${!list[@]}"; do
    [[ "${list[$i]}" == "$cur" ]] \
      && { printf '%s\n' "${list[$(( (i + 1) % ${#list[@]} ))]}"; return 0; }
  done
  printf '%s\n' "${list[0]}"
}

# _ctl_cycle_topology <fs> <current> → the next topology in <fs>'s cycle after
# <current>, wrapping; the first entry when <current> is not in the set (e.g.
# after the group's filesystem changed and left a stale topology).
_ctl_cycle_topology() {
  # shellcheck disable=SC2046 # deliberately word-split the topology list to args
  _ctl_cycle_next "$2" $(_ctl_topologies_for_fs "$1")
}

# _ctl_pool_normalise_fs <state> <index> <fs> → state with data_pools[index]'s
# filesystem set to <fs> and the group made consistent for it (issue 09, ADR
# 0043): ext4/xfs are single-disk (topology single, disk_count 1); otherwise a
# topology no longer valid for <fs> resets to that fs's first (a still-valid one
# is kept). Keeps the editor from authoring a group validation would reject.
_ctl_pool_normalise_fs() {
  local state="$1" i="$2" fs="$3" valid first
  valid="$(_ctl_topologies_for_fs "$fs" | tr '\n' ' ')"
  first="$(_ctl_topologies_for_fs "$fs" | head -1)"
  jq --argjson i "$i" --arg fs "$fs" --arg valid "$valid" --arg first "$first" '
    ($valid | split(" ") | map(select(length > 0))) as $v
    | (.data_pools[$i].topology) as $topo
    | .data_pools[$i].filesystem = $fs
    | if ($fs == "ext4" or $fs == "xfs")
      then .data_pools[$i].topology = "single" | .data_pools[$i].disk_count = 1
           | (if (.data_pools[$i] | has("devices"))
              then .data_pools[$i].devices |= .[0:1] else . end)
      elif ($v | index($topo)) == null
      then .data_pools[$i].topology = $first
      else . end
  ' <<<"$state"
}

# _ctl_enum_options <path> → the value-picker lines for an enum field (or the
# synthetic __layout__ disk-layout preset list).
_ctl_enum_options() {
  case "$1" in
  __layout__) printf '%s\n' single os-mirror os-mirror-raidz1 data-pools ;;
  filesystem) _ctl_built_root_filesystems ;;
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
    # Commit only a BUILT root filesystem (issue 09); an unbuilt/unknown value is
    # a no-op (rc 1, unchanged) so the picker can never author an uninstallable fs.
    _ctl_built_root_filesystems | grep -qxF "$val" \
      || { printf '%s' "$state"; return 1; }
    edit_set_scalar "$state" filesystem "$val" ;;
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
  swapedit)  b='Enter edit/toggle   Esc back' ;;
  datapools) b='Enter open/add   Esc back' ;;
  pooledit)  b='Enter cycle/remove   Esc back' ;;
  pooldisks) b='Enter bind/unbind ✓   Esc back' ;;
  *)        b='Esc back' ;;
  esac
  printf '%s   ·   ^Z undo  ^Y redo  ^R reset' "$b"
}
_ctl_nav_prompt() {
  case "$(nav_screen "$1")" in
  top)         printf 'guided> ' ;;
  category)    printf '%s> ' "$(nav_get "$1" category)" ;;
  values|text) printf '%s> ' "$(nav_get "$1" label)" ;;
  swapedit)    printf 'swap> ' ;;
  datapools)   printf 'data pools> ' ;;
  pooledit)    printf 'pool> ' ;;
  pooldisks)   printf 'disks> ' ;;
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

# _ctl_swap_on <effective-json> → "true"/"false": is swap enabled (default true)?
# has("swap") so an explicit `swap:false` is not swallowed by jq's `//` (which
# treats false like null) — see [[dotfiles_jq_alternative_false]].
_ctl_swap_on() {
  jq -r '(.options // {}) as $o
    | if ($o | has("swap")) then $o.swap else true end' <<<"$1"
}

# _ctl_zswap_on <effective-json> → "true"/"false": is zswap enabled (default
# true)? has("enabled") so an explicit false is honoured, not read as default.
_ctl_zswap_on() {
  jq -r '(.options.zswap // {}) as $z
    | if ($z | has("enabled")) then $z.enabled else true end' <<<"$1"
}

# _ctl_swap_label <effective-json> → the one-line swap summary for the Disks swap
# row: "off" when swap is disabled, else the size (default "auto") plus a zswap
# suffix — "· zswap <compressor>" when zswap is on, "· no zswap" when off (so a
# deviation from the zswap-on default is visible). NOTE: a stored false must
# survive — jq's `//` treats false like null, so test membership with has().
_ctl_swap_label() {
  jq -r '
    (.options // {}) as $o
    | (if ($o | has("swap")) then $o.swap else true end) as $on
    | if $on == false then "off"
      else
        ($o.swap_size // "auto") as $sz
        | ($o.zswap // {}) as $z
        | (if ($z | has("enabled")) then $z.enabled else true end) as $zon
        | if $zon == false then "\($sz) · no zswap"
          else "\($sz) · zswap \($z.compressor // "zstd")" end
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

# ── pool-group reference (kind, index) ───────────────────────────────────────
# The pool editor addresses any group through one uniform reference so a later
# slice can bind/edit the OS pool and storage groups, not just data_pools. kind
# is os (singleton) | storage | data; index selects within the array kinds. Pure
# resolvers: state + kind + index in, group JSON / new state out.

# _ctl_pool_kind <nav> — the group kind carried by a pooledit nav, defaulting to
# data (so a nav authored before this reference existed still resolves).
_ctl_pool_kind() {
  local k; k="$(nav_get "$1" kind)"; printf '%s' "${k:-data}"
}

# _ctl_pool_get <state> <kind> <index> — the group object at (kind, index), or
# {} when absent.
_ctl_pool_get() {
  case "$2" in
  os)      jq -c '.os_pool // {}' <<<"$1" ;;
  storage) jq -c --argjson i "$3" '.storage_groups[$i] // {}' <<<"$1" ;;
  *)       jq -c --argjson i "$3" '.data_pools[$i] // {}' <<<"$1" ;;
  esac
}

# _ctl_pool_set <state> <kind> <index> <group> — state with the group at
# (kind, index) replaced by <group>.
_ctl_pool_set() {
  case "$2" in
  os)      jq -c --argjson g "$4" '.os_pool = $g' <<<"$1" ;;
  storage) jq -c --argjson i "$3" --argjson g "$4" \
             '.storage_groups[$i] = $g' <<<"$1" ;;
  *)       jq -c --argjson i "$3" --argjson g "$4" \
             '.data_pools[$i] = $g' <<<"$1" ;;
  esac
}

# _ctl_pool_del <state> <kind> <index> — state with the group at (kind, index)
# removed. The OS pool is structural, not removable — a del on os is a no-op.
_ctl_pool_del() {
  case "$2" in
  os)      jq -c '.' <<<"$1" ;;
  storage) jq -c --argjson i "$3" 'del(.storage_groups[$i])' <<<"$1" ;;
  *)       jq -c --argjson i "$3" 'del(.data_pools[$i])' <<<"$1" ;;
  esac
}

# ── In-Menu Disk Binding: device-mode, Free Set, bind toggle (ADR 0047) ──────
# On a machine with real disks the pool editor binds actual /dev/disk/by-id/*
# devices (device-mode); off-target it keeps the abstract disk_count cycle
# (count-mode). The mode is decided once at guided launch (guided.sh caches it
# in GUIDED_DEVICE_MODE) and read here; GUIDED_LIVE_SET carries the live-medium
# disks to exclude, so the controller never probes hardware itself.

# _ctl_live_set — the newline-separated live-medium whole-disk set to exclude
# from enumeration (empty when unset — no exclusion).
_ctl_live_set() { printf '%s' "${GUIDED_LIVE_SET-}"; }

# _ctl_detect_device_mode — "1" when any install disk is enumerable, else "0".
# guided.sh calls this once at launch; the pure result drives the cached flag.
_ctl_detect_device_mode() {
  [[ -n "$(picker_enum_disks "$(_ctl_live_set)")" ]] && echo 1 || echo 0
}

# _ctl_device_mode — rc 0 when In-Menu Disk Binding is active (the cached flag).
_ctl_device_mode() { [[ "${GUIDED_DEVICE_MODE:-0}" == "1" ]]; }

# _ctl_bound_disks <state> — every by-id path already bound to ANY group (os +
# storage + data), one per line, so a disk lives in exactly one pool.
_ctl_bound_disks() {
  jq -r '[ (.os_pool.devices // [])[],
           ((.storage_groups // [])[].devices // [])[],
           ((.data_pools // [])[].devices // [])[] ] | .[]' <<<"$1"
}

# _ctl_free_disks <state> — the Free Set: enumerated candidates (live medium
# excluded) minus every already-bound disk, one per line.
_ctl_free_disks() {
  local bound; bound="$(_ctl_bound_disks "$1")"
  picker_enum_disks "$(_ctl_live_set)" | awk -v b="$bound" '
    BEGIN { n = split(b, a, "\n"); for (i = 1; i <= n; i++)
              if (a[i] != "") seen[a[i]] = 1 }
    !seen[$0]'
}

# _ctl_disk_label <by-id-path> — a compact one-line label: "<size> <model> ·
# <tail>" when lsblk can read the disk, else just the by-id tail (the stable key
# the toggle parses back — always the segment after the last " · ").
_ctl_disk_label() {
  local p="$1" tail dev sm
  tail="${p##*/}"
  if dev="$(readlink -f "$p" 2>/dev/null)" \
     && sm="$(lsblk -dno SIZE,MODEL "$dev" 2>/dev/null | head -1)" \
     && [[ -n "${sm//[[:space:]]/}" ]]; then
    printf '%s · %s' "$(echo "$sm" | tr -s ' ')" "$tail"
  else
    printf '%s' "$tail"
  fi
}

# _ctl_pool_toggle_disk <group> <by-id-path> — flip the disk's membership in the
# group's devices[], then re-derive disk_count as the number bound.
_ctl_pool_toggle_disk() {
  jq -c --arg d "$2" '
    (.devices // []) as $cur
    | (if any($cur[]; . == $d) then ($cur - [$d])
       else ($cur + [$d]) end) as $new
    | .devices = $new | .disk_count = ($new | length)' <<<"$1"
}

# guided_ctl_preview <line> — the fzf preview body: the layout graph for the
# highlighted preset, but ONLY on the Disk-layout screen (empty elsewhere, so the
# preview is a no-op on every other screen).
guided_ctl_preview() {
  local line="$1" nav field
  nav="$(_ctl_nav)"
  # The data-pools editor screens graph the LIVE state (not a preset line) so the
  # tree reflects pools/disks as you add and cycle them.
  case "$(nav_screen "$nav")" in
  datapools | pooledit)
    _ctl_layout_graph "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    return 0 ;;
  esac
  [[ "$(nav_screen "$nav")" == "values" ]] || return 0
  field="$(nav_get "$nav" field)"
  case "$field" in
  __layout__)
    # A destructive preset row previews THAT preset ("what you'd get"). The
    # data-pools row is additive (it opens the editor, keeping your pools) and
    # ← Back is no choice at all — both graph the LIVE state so edits stay visible.
    local sk
    if [[ "$line" == "data-pools" || "$line" == "← Back" ]]; then
      _ctl_layout_graph "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    elif sk="$(skeleton_preset "$line" 2>/dev/null)"; then
      _ctl_layout_graph "$sk"
    else
      _ctl_layout_graph "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    fi ;;
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
      local _sov=""
      jq -e '.options.swap != null or .options.swap_size != null' \
        <<<"$state" >/dev/null 2>&1 && _sov="  ●"
      printf 'swap: %s%s\n' \
        "$(_ctl_swap_label "$(_ctl_effective "$state" "$base")")" "$_sov"
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
  swapedit)
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    if [[ "$(_ctl_swap_on "$_eff")" == "false" ]]; then
      printf 'enabled: off\n'
    else
      printf 'enabled: on\n'
      printf 'size: %s\n' "$(jq -r '.options.swap_size // "auto"' <<<"$_eff")"
      if [[ "$(_ctl_zswap_on "$_eff")" == "false" ]]; then
        printf 'zswap: off\n'
      else
        printf 'zswap: on\n'
        printf 'compressor: %s   (Enter cycles)\n' \
          "$(jq -r '.options.zswap.compressor // "zstd"' <<<"$_eff")"
        printf 'max pool %%: %s   (Enter cycles)\n' \
          "$(jq -r '.options.zswap.max_pool_percent // 20' <<<"$_eff")"
      fi
    fi
    printf '%s\n' "← Back" ;;
  datapools)
    jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
      <<<"$(_ctl_effective "$state" "$base")"
    printf '%s\n' "+ Add data pool" "← Back" ;;
  pooledit)
    local i kind p _eff _rootfs
    i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
    _eff="$(_ctl_effective "$state" "$base")"
    p="$(_ctl_pool_get "$_eff" "$kind" "$i")"
    # A group with no explicit filesystem inherits the root's (ADR 0043), so the
    # displayed value matches what the topology/disks cycles use.
    _rootfs="$(jq -r '.filesystem // "zfs"' <<<"$_eff")"
    printf 'name: %s\n' "$(jq -r '.name // "?"' <<<"$p")"
    printf 'filesystem: %s   (Enter cycles)\n' \
      "$(jq -r --arg r "$_rootfs" '.filesystem // $r' <<<"$p")"
    printf 'topology: %s   (Enter cycles)\n' "$(jq -r '.topology // "?"' <<<"$p")"
    # Device-mode binds real disks (row shows the bound count, Enter opens the
    # sub-screen); count-mode keeps the abstract 1-8 cycle.
    if _ctl_device_mode; then
      printf 'disks: %s bound   (Enter to edit)\n' \
        "$(jq -r '(.devices // []) | length' <<<"$p")"
    else
      printf 'disks: %s   (Enter cycles 1-8)\n' \
        "$(jq -r '.disk_count // "?"' <<<"$p")"
    fi
    printf 'encryption: %s   (Enter toggles)\n' "$(jq -r '.encryption // false' <<<"$p")"
    printf '%s\n' "✗ remove this pool" "← Back" ;;
  pooldisks)
    local i kind p _eff d
    i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
    _eff="$(_ctl_effective "$state" "$base")"
    p="$(_ctl_pool_get "$_eff" "$kind" "$i")"
    # Bound disks first (marked), then the still-free ones (unmarked) — an
    # Enter-toggle multi-select; an exhausted Free Set simply shows no [ ] rows.
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '[x] %s\n' "$(_ctl_disk_label "$d")"
    done < <(jq -r '(.devices // [])[]' <<<"$p")
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '[ ] %s\n' "$(_ctl_disk_label "$d")"
    done < <(_ctl_free_disks "$state")
    printf '%s\n' "← Back" ;;
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
  swapedit)  _ctl_enter_swapedit "$line" ;;
  datapools) _ctl_enter_datapools "$line" ;;
  pooledit)  _ctl_enter_pooledit "$line" ;;
  pooldisks) _ctl_enter_pooldisks "$line" ;;
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
  "swap:"*)
    _ctl_write_nav "$(nav_to_swapedit "$cat")"; echo render; return ;;
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
  sysctl)            _ctl_write_nav "$(nav_to_values "$cat" sysctl sysctl)" ;;
  __newuser__)       _ctl_write_nav "$(nav_to_values "$cat" users users)" ;;
  options.swap_size) _ctl_write_nav "$(nav_to_swapedit "$cat")" ;;
  *)                 _ctl_write_nav "$(nav_back "$nav")" ;;
  esac
  echo render
}

# _ctl_enter_swapedit <line> — the swap sub-editor: toggle swap on/off, toggle
# zswap, cycle the zswap compressor (zstd→lz4→lzo) and max pool % (5→…→60), or
# open the free-text size editor. Toggles/cycles STAY on the screen (refresh);
# size opens the text screen (which returns here — see _ctl_enter_text).
_ctl_enter_swapedit() {
  local line="$1" nav cat; nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "enabled:"*)
    # flip options.swap; has("swap") keeps an explicit false from being read as
    # the default true (jq `//` false-swallow gotcha).
    _ctl_write_state "$(jq '
      (if (.options // {} | has("swap")) then .options.swap else true end) as $c
      | .options.swap = ($c | not)' <<<"$(_ctl_state)")"
    echo refresh; return ;;
  "size:"*)
    _ctl_write_nav "$(nav_to_text "$cat" options.swap_size "swap size")"
    echo render; return ;;
  "zswap:"*)
    _ctl_write_state "$(jq '
      (if (.options.zswap // {} | has("enabled")) then .options.zswap.enabled
       else true end) as $c
      | .options.zswap.enabled = ($c | not)' <<<"$(_ctl_state)")"
    echo refresh; return ;;
  "compressor:"*)
    _ctl_write_state "$(jq '
      (.options.zswap.compressor // "zstd") as $c
      | .options.zswap.compressor =
          ({"zstd":"lz4","lz4":"lzo","lzo":"zstd"}[$c] // "zstd")' \
      <<<"$(_ctl_state)")"
    echo refresh; return ;;
  "max pool %:"*)
    _ctl_write_state "$(jq '
      (.options.zswap.max_pool_percent // 20) as $p
      | .options.zswap.max_pool_percent =
          ({"5":10,"10":20,"20":40,"40":60,"60":5}[($p | tostring)] // 20)' \
      <<<"$(_ctl_state)")"
    echo refresh; return ;;
  esac
  echo refresh
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
  local line="$1" nav cat i kind _rfs p
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
  # The root filesystem a group inherits when it declares none (ADR 0043).
  _rfs="$(jq -r '.filesystem // "zfs"' <<<"$(_ctl_state)")"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_to_datapools "$cat")"; echo render; return ;;
  "✗ remove"*)
    _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$kind" "$i")"
    _ctl_write_nav "$(nav_to_datapools "$cat")"; echo render; return ;;
  "topology:"*)
    # The cycle follows the group's own filesystem (pool value, else the root
    # filesystem, else zfs) so btrfs groups get raid0/1/10 and ext4/xfs stay
    # pinned to single (issue 09, ADR 0043).
    local _fs _cur _next
    p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
    _fs="$(jq -r --arg r "$_rfs" '.filesystem // $r' <<<"$p")"
    _cur="$(jq -r '.topology // ""' <<<"$p")"
    _next="$(_ctl_cycle_topology "$_fs" "$_cur")"
    _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
      "$(jq -c --arg t "$_next" '.topology = $t' <<<"$p")")"
    echo refresh; return ;;
  "filesystem:"*)
    # Cycle the group's filesystem through the built adapters, then normalise the
    # group for its new filesystem (ext4/xfs → single-disk; a topology invalid for
    # the new fs resets to that fs's first) via _ctl_pool_normalise_fs. Only
    # data pools expose a filesystem row, so this stays index-scoped to data.
    local _cur _next
    _cur="$(jq -r '.filesystem // "zfs"' \
      <<<"$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")")"
    # shellcheck disable=SC2046 # word-split the built-fs list into cycle args
    _next="$(_ctl_cycle_next "$_cur" $(_ctl_built_root_filesystems))"
    _ctl_write_state "$(_ctl_pool_normalise_fs "$(_ctl_state)" "$i" "$_next")"
    echo refresh; return ;;
  "encryption:"*)
    p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
    _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
      "$(jq -c '.encryption = ((.encryption // false) | not)' <<<"$p")")"
    echo refresh; return ;;
  "disks:"*)
    # Device-mode: the disks row opens the bind sub-screen instead of cycling.
    if _ctl_device_mode; then
      _ctl_write_nav "$(nav_to_pooldisks "$cat" "$i" "$kind")"
      echo render; return
    fi
    # ext4/xfs are single-disk only (ADR 0043): their disk count is pinned at 1,
    # so the cycle is a no-op there; other filesystems cycle 1-8.
    p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
    _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
      "$(jq -c --arg r "$_rfs" '
        (.filesystem // $r) as $fs
        | if ($fs == "ext4" or $fs == "xfs") then .disk_count = 1
          else .disk_count |= (if . >= 8 then 1 else . + 1 end) end' <<<"$p")")"
    echo refresh; return ;;
  esac
  echo refresh
}

# _ctl_pooldisks_resolve <tail> — the full by-id path whose basename matches the
# label tail (enumeration includes bound disks — they are still physically
# present — so this resolves both a bind and an unbind).
_ctl_pooldisks_resolve() {
  picker_enum_disks "$(_ctl_live_set)" | awk -v t="$1" '
    { n = $0; sub(/.*\//, "", n); if (n == t) { print; exit } }'
}

# _ctl_enter_pooldisks <line> — the disk sub-screen: Enter toggles one disk's
# binding (STAY, refresh re-marks in place); ← Back returns to the pool editor.
_ctl_enter_pooldisks() {
  local line="$1" nav cat i kind tail path p
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_to_pooledit "$cat" "$i" "$kind")"
    echo render; return
  fi
  # Strip the "[x] "/"[ ] " mark, take the by-id tail (the segment after the
  # last " · "), resolve it to a full path, and flip its binding.
  tail="${line:4}"; tail="${tail##* · }"
  path="$(_ctl_pooldisks_resolve "$tail")"
  [[ -n "$path" ]] || { echo refresh; return; }
  p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
  _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
    "$(_ctl_pool_toggle_disk "$p" "$path")")"
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
    case "$(nav_screen "$nav")" in
    values)
      _ctl_field_has_preview "$(nav_get "$nav" field)" && _showpv=1 ;;
    datapools | pooledit) _showpv=1 ;;   # the live layout graph
    esac
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
    # refresh-preview re-renders the live layout graph after a pool/disk edit;
    # a no-op where the preview pane is hidden.
    printf 'reload-sync(bash %q list)+refresh-preview' "$entry" ;;
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
