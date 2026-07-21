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
  __layout__) printf '%s\n' single os-mirror os-mirror-raidz1 data-pools "Custom…" ;;
  filesystem) _ctl_built_root_filesystems ;;
  options.bootloader | post_install.security.firewall) menu_enum_options "$1" ;;
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

# _ctl_normalise_default <state> <path> → <state> with the override at <path>
# dropped when it renders identically to the seeded baseline default. The whole
# "strict delta" contract: an apply that lands the operator back on the shown
# default leaves NO override, so the map stays a true delta and ● (override-only)
# never lights for an unchanged value. Rendered compare (menu_render_value) so it
# judges "same as the default" the way the value displays — surviving the
# scalar/array shape gaps (keymap "us" vs ["us"], gpu "auto"). Pure.
_ctl_normalise_default() {
  local state="$1" path="$2"
  cfgstate_is_overridden "$state" "$path" || { printf '%s' "$state"; return 0; }
  local ov dv
  ov="$(menu_render_value "$state" "$path")"
  dv="$(menu_render_value "$(_ctl_baseline)" "$path")"
  if [[ "$ov" == "$dv" ]]; then
    cfgstate_unset "$state" "$path"
  else
    printf '%s' "$state"
  fi
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
  options.kernel | environment.desktop | environment.gpu \
    | options.mirror_countries) menu_enum_options "$1" ;;
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
  rootdisk)  b='Enter pick   Esc back' ;;
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
  rootdisk)    printf 'root disk> ' ;;
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
# tank<N>, default single-disk stripe ×1), forcing multi mode + a default OS pool.
# A 1-disk stripe is the friendliest default: it is the smallest installable pool
# (so adding several tanks never balloons the disk requirement), matches the
# data-pools preset, and the user cycles up to mirror/raidz for redundancy. Shared
# by the data-pools editor's "+ Add" and by picking "data-pools" in the layout.
_ctl_add_data_pool() {
  jq '
    (.data_pools // []) as $dp
    | .data_pools = ($dp + [{name:("tank" + (($dp | length) | tostring)),
                             topology:"stripe", disk_count:1}])
    | .mode = "multi"
    | (if .os_pool then . else
        .os_pool = {pool_name:"rpool", topology:"none", disk_count:1} end)
    ' <<<"$1"
}

# _ctl_add_storage_group <state> → state with one more storage group appended,
# forcing multi mode + a default OS pool. Storage groups fold into the shared
# `dpool` (each a redundant data area at /<name>), so a new one defaults to
# mirror ×2; the user cycles to raidz1 ×3 to rebuild the os-mirror-raidz1 preset.
# The first group is auto-named "data" at /data (preset parity), then data1, …
# Shared by the data-pools editor's "+ Add storage group".
_ctl_add_storage_group() {
  jq '
    (.storage_groups // []) as $sg
    | ($sg | length) as $n
    | (if $n == 0 then "data" else "data" + ($n | tostring) end) as $nm
    | .storage_groups = ($sg + [{name:$nm, mount:("/" + $nm),
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

# ── Rich chrome version gate (ADR 0047) ──────────────────────────────────────
# The rich chrome (footer + breadcrumb + rounded borders, actions on keys) needs
# fzf ≥ 0.62; a lagging install ISO (ADR 0023) may ship an older fzf, where the
# menu degrades to today's action-rows layout. The mode is decided ONCE at guided
# launch (guided.sh caches it in GUIDED_RICH_CHROME) — never a network/pacman
# step, so offline Save/Export authoring is never gated.

# _ctl_fzf_rich_for_version <version-string> — rc 0 when the parsed "MAJOR.MINOR"
# is ≥ 0.62 (any major > 0 qualifies). Pure: the first token's first two dotted
# fields, base-10 to dodge a leading-zero octal read.
_ctl_fzf_rich_for_version() {
  local v="${1%% *}" major minor
  major="${v%%.*}"; v="${v#*.}"; minor="${v%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  (( 10#$major > 0 || 10#$minor >= 62 ))
}

# _ctl_detect_rich_chrome — "1" when the installed fzf supports rich chrome, else
# "0" (also 0 when fzf is absent — legacy is the safe floor). guided.sh calls this
# once at launch; the pure result drives the cached flag.
_ctl_detect_rich_chrome() {
  local ver; ver="$(fzf --version 2>/dev/null)"
  [[ -n "$ver" ]] && _ctl_fzf_rich_for_version "$ver" && echo 1 || echo 0
}

# _ctl_rich_chrome — rc 0 when the rich chrome is active (the cached flag). Unset
# defaults to legacy, so every non-interactive seam renders action rows.
_ctl_rich_chrome() { [[ "${GUIDED_RICH_CHROME:-0}" == "1" ]]; }

# _ctl_action_row <line...> — emit action rows (Back/Add/remove/create) ONLY in
# legacy chrome; in rich mode they live on keybindings (^A/^X/Esc) + the footer,
# so the lists hold only data.
_ctl_action_row() { _ctl_rich_chrome || printf '%s\n' "$@"; }

# _ctl_bound_disks <state> — every by-id path already bound to ANY group (os +
# storage + data pools, plus the single-disk root), one per line, so a disk
# lives in exactly one place ("disappears everywhere" — ADR 0047).
_ctl_bound_disks() {
  jq -r '[ (.os_pool.devices // [])[],
           ((.storage_groups // [])[].devices // [])[],
           ((.data_pools // [])[].devices // [])[],
           (.root_disk // empty) ] | .[]' <<<"$1"
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

# _ctl_disk_label <by-id-path> — the disk row label; delegates to the shared
# picker_disk_label ("/dev/sda <size> <model> · <tail>", tail parseable back out).
_ctl_disk_label() { picker_disk_label "$1"; }

# _ctl_pool_toggle_disk <group> <by-id-path> — flip the disk's membership in the
# group's devices[], then re-derive disk_count as the number bound.
_ctl_pool_toggle_disk() {
  jq -c --arg d "$2" '
    (.devices // []) as $cur
    | (if any($cur[]; . == $d) then ($cur - [$d])
       else ($cur + [$d]) end) as $new
    | .devices = $new | .disk_count = ($new | length)' <<<"$1"
}

# _ctl_disks_row <group-json> <count-editable 0|1> — the pooledit "disks:" row.
# Device-mode shows the bound count and opens the sub-screen; count-mode shows
# the 1-8 cycle when editable (OS pool, data pool, storage group) or a plain
# count when not.
_ctl_disks_row() {
  local p="$1" editable="$2"
  if _ctl_device_mode; then
    printf 'disks: %s bound   (Enter to edit)\n' \
      "$(jq -r '(.devices // []) | length' <<<"$p")"
  elif [[ "$editable" == "1" ]]; then
    printf 'disks: %s   (Enter cycles 1-8)\n' \
      "$(jq -r '.disk_count // "?"' <<<"$p")"
  else
    printf 'disks: %s\n' "$(jq -r '.disk_count // "?"' <<<"$p")"
  fi
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
      # Single-disk root binds in-menu on-target: a device-mode single-disk
      # layout gets a root disk row (ADR 0047). Multi layouts bind per pool;
      # off-target (count-mode) the single disk is resolved post-menu as before.
      local _deff; _deff="$(_ctl_effective "$state" "$base")"
      if _ctl_device_mode \
        && [[ "$(jq -r '.mode // "single"' <<<"$_deff")" != "multi" ]]; then
        local _rd; _rd="$(jq -r '.root_disk // ""' <<<"$_deff")"
        printf 'root disk: %s   (Enter to pick)\n' \
          "$([[ -n "$_rd" ]] && _ctl_disk_label "$_rd" || echo "(none)")"
      fi
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
        && _ctl_action_row "Add persist directory ▸ extend the curated defaults"
    fi
    _ctl_action_row "← Back" ;;
  values)
    local vf; vf="$(nav_get "$nav" field)"
    if [[ "$vf" == "sysctl" ]]; then
      _ctl_sysctl_lines "$state" "$base"
      _ctl_action_row "+ Add sysctl (key=value)"
    elif [[ "$vf" == "users" ]]; then
      _ctl_user_marked "$state" "$base"
      _ctl_action_row "+ Create user (name)"
    elif [[ "$(_ctl_field_kind "$vf")" == "biglist" ]]; then
      _ctl_biglist_options "$vf"
    elif [[ "$(_ctl_field_kind "$vf")" == "toggle" ]]; then
      _ctl_marked_options "$vf" "$state" "$base"
    else
      _ctl_enum_options "$vf"
    fi
    _ctl_action_row "← Back" ;;
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
    _ctl_action_row "← Back" ;;
  datapools)
    # Unified layout editor (ADR 0047): OS pool + storage groups + data pools,
    # each row opening its per-kind editor. Distinct prefixes keep the enter
    # dispatch unambiguous: "OS pool:" (singleton), "<name> (storage):", and the
    # bare "<name>:" data-pool rows.
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    jq -e '.os_pool' <<<"$_eff" >/dev/null 2>&1 \
      && jq -r '"OS pool: \(.os_pool.topology // "?") ×\(.os_pool.disk_count // "?")"' \
        <<<"$_eff"
    jq -r '(.storage_groups // [])[]
             | "\(.name) (storage): \(.topology) ×\(.disk_count)"' <<<"$_eff"
    jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
      <<<"$_eff"
    # The "+ Add …" rows stay visible in BOTH chromes: building the layout is this
    # screen's primary action, and a footer-only ^A hint proved undiscoverable
    # (users saw tank0 and no way to add more). The parentheticals spell out the
    # distinction so the choice is obvious at author time: a data pool is an
    # independent zpool (own filesystem + own key); a storage group folds into the
    # shared `dpool` (zfs, disk-wide key). Offering both lets Custom reconstruct
    # every preset (incl. os-mirror-raidz1). ← Back is legacy-only (Esc in rich).
    printf '%s\n' \
      "+ Add data pool  (standalone pool · any filesystem · own key)" \
      "+ Add storage group  (shared dpool · zfs · disk-wide key)"
    _ctl_action_row "← Back" ;;
  pooledit)
    local i kind p _eff _rootfs
    i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
    _eff="$(_ctl_effective "$state" "$base")"
    p="$(_ctl_pool_get "$_eff" "$kind" "$i")"
    # A group with no explicit filesystem inherits the root's (ADR 0043), so the
    # displayed value matches what the topology/disks cycles use.
    _rootfs="$(jq -r '.filesystem // "zfs"' <<<"$_eff")"
    printf 'name: %s\n' "$(jq -r '.name // .pool_name // "?"' <<<"$p")"
    case "$kind" in
    os)
      # OS pool: topology + disks only. Root filesystem/encryption live at their
      # top-level rows (ADR 0047), never duplicated here.
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      _ctl_action_row "← Back" ;;
    storage)
      # Storage group: a redundant data area folded into the shared `dpool`. Its
      # topology + disk count are editable (so Custom can rebuild os-mirror-raidz1);
      # the mount is display-only (defaults to /<name>). It inherits the root
      # filesystem — no per-group fs/encryption rows (that is the data-pool path).
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      printf 'mount: %s\n' "$(jq -r '.mount // ("/" + (.name // "data"))' <<<"$p")"
      # Storage groups share dpool's encryption (the disk-wide setting) — shown
      # read-only, since they have no independent key (that is the data-pool path).
      printf 'encryption: %s   (disk-wide, shared)\n' \
        "$([[ "$(jq -r '.options.encryption // false' <<<"$_eff")" == "true" ]] \
           && echo on || echo off)"
      _ctl_action_row "✗ remove this group" "← Back" ;;
    *)
      printf 'filesystem: %s   (Enter cycles)\n' \
        "$(jq -r --arg r "$_rootfs" '.filesystem // $r' <<<"$p")"
      printf 'topology: %s   (Enter cycles)\n' \
        "$(jq -r '.topology // "?"' <<<"$p")"
      _ctl_disks_row "$p" 1
      printf 'encryption: %s   (Enter toggles)\n' \
        "$(jq -r '.encryption // false' <<<"$p")"
      # mount defaults to /<name> (blank keeps the default); editable free-text.
      printf 'mount: %s   (Enter to edit)\n' \
        "$(jq -r '.mount // ("/" + (.name // "pool"))' <<<"$p")"
      _ctl_action_row "✗ remove this pool" "← Back" ;;
    esac ;;
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
    _ctl_action_row "← Back" ;;
  rootdisk)
    # Single-select radio: the current root_disk marked (*) first (it is bound, so
    # the Free Set excludes it — add it back), then every free candidate ( ).
    # Picking one replaces the prior choice.
    local _rd d
    _rd="$(jq -r '.root_disk // ""' <<<"$(_ctl_effective "$state" "$base")")"
    [[ -n "$_rd" ]] && printf '(*) %s\n' "$(_ctl_disk_label "$_rd")"
    while IFS= read -r d; do
      [[ -n "$d" ]] && printf '( ) %s\n' "$(_ctl_disk_label "$d")"
    done < <(_ctl_free_disks "$state")
    _ctl_action_row "← Back" ;;
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
  rootdisk)  _ctl_enter_rootdisk "$line" ;;
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
  "root disk:"*)
    _ctl_write_nav "$(nav_to_rootdisk "$cat")"; echo render; return ;;
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
    _ctl_write_state "$(_ctl_normalise_default "$(_ctl_toggle_multi \
      "$(_ctl_state)" "$(_ctl_baseline)" "$path" "${line:4}")" "$path")"
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
    # NOT normalised: users keeps an explicit empty list ([] ≠ unset — no users is
    # a real choice distinct from "fall back to the seeded default"), so it owns
    # its own membership semantics rather than the strict-delta normalise.
    _ctl_write_state "$(_ctl_toggle_users "$(_ctl_state)" "$(_ctl_baseline)" \
      "${line:4}")"
    echo refresh; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "biglist" ]]; then
    # a big filterable list → set the picked value as a scalar, then back
    _ctl_write_state "$(_ctl_normalise_default \
      "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")" "$path")"
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
    if [[ "$line" == "Custom…" ]]; then
      # blank-canvas seed → straight into the unified editor (ADR 0047).
      _ctl_write_state \
        "$(edit_apply_skeleton "$(_ctl_state)" "$(skeleton_custom_seed)")"
      _ctl_write_nav "$(nav_to_datapools "$(nav_get "$nav" category)")"
      echo render; return
    fi
    if sk="$(skeleton_preset "$line" 2>/dev/null)"; then
      _ctl_write_state "$(edit_apply_skeleton "$(_ctl_state)" "$sk")"
    fi
    # A multi preset drops into the unified editor to bind disks / tweak pools;
    # single applies and backs out to the category (ADR 0047).
    if [[ "$(jq -r '.mode // "single"' <<<"$(_ctl_state)")" == "multi" ]]; then
      _ctl_write_nav "$(nav_to_datapools "$(nav_get "$nav" category)")"
    else
      _ctl_write_nav "$(nav_back "$nav")"
    fi
    echo render; return
  fi
  if new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$line")"; then
    _ctl_write_state "$(_ctl_normalise_default "$new" "$path")"
  fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# _ctl_enter_text <query> — commit the typed query into the field, then back.
# Empty query (Esc-less cancel via Enter) just returns without a change.
_ctl_enter_text() {
  local query="$1" nav path cat
  nav="$(_ctl_nav)"; path="$(nav_get "$nav" field)"
  cat="$(nav_get "$nav" category)"
  # Pool mount is scoped to a data pool by the nav's index (ADR 0047): a typed
  # value commits to .data_pools[index].mount; a blank input keeps the /<name>
  # default (no key written). Either way return to that pool's editor.
  if [[ "$path" == "__poolmount__" ]]; then
    local idx; idx="$(nav_get "$nav" index)"
    [[ -n "$query" ]] && _ctl_write_state "$(jq --argjson i "$idx" --arg m "$query" \
      '.data_pools[$i].mount = $m' <<<"$(_ctl_state)")"
    _ctl_write_nav "$(nav_to_pooledit "$cat" "$idx" data)"; echo render; return
  fi
  [[ -n "$query" ]] \
    && _ctl_write_state "$(_ctl_normalise_default \
         "$(_ctl_apply_text "$(_ctl_state)" "$path" "$query")" "$path")"
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
  "+ Add storage"*)
    _ctl_write_state "$(_ctl_add_storage_group "$(_ctl_state)")"
    echo refresh; return ;;
  "+ Add"*)
    _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"
    echo refresh; return ;;
  "OS pool:"*)
    # the singleton OS pool editor (topology + disks, ADR 0047).
    _ctl_write_nav "$(nav_to_pooledit "$cat" 0 os)"; echo render; return ;;
  *" (storage):"*)
    # a preset storage group (binding-only): parse its name, resolve its index.
    name="${line%% (storage):*}"
    idx="$(jq -r --arg n "$name" \
      '[(.storage_groups // [])[] | .name] | (index($n) // -1)' <<<"$(_ctl_state)")"
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      _ctl_write_nav "$(nav_to_pooledit "$cat" "$idx" storage)"
      echo render; return
    fi
    echo refresh; return ;;
  esac
  name="${line%%:*}"
  idx="$(jq -r --arg n "$name" \
    '[(.data_pools // [])[] | .name] | (index($n) // -1)' <<<"$(_ctl_state)")"
  if [[ "$idx" =~ ^[0-9]+$ ]]; then
    _ctl_write_nav "$(nav_to_pooledit "$cat" "$idx" data)"; echo render; return
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
    # Storage groups inherit dpool's disk-wide encryption — no per-group toggle.
    [[ "$kind" == "storage" ]] && { echo refresh; return; }
    p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
    _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
      "$(jq -c '.encryption = ((.encryption // false) | not)' <<<"$p")")"
    echo refresh; return ;;
  "mount:"*)
    # Only a data pool's mount is editable; a storage group's is preset-fixed
    # (display-only row, so Enter on it is a no-op).
    [[ "$kind" == "data" ]] || { echo refresh; return; }
    _ctl_write_nav "$(nav_to_poolmount "$cat" "$i")"; echo render; return ;;
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

# _ctl_line_to_disk <line> — the full by-id path a picked disk row resolves to:
# strip the 4-char mark ("[x] "/"[ ] "/"(*) "/"( ) "), take the by-id tail (the
# segment after the last " · "), and resolve it. Empty when it doesn't resolve.
_ctl_line_to_disk() {
  local tail="${1:4}"; tail="${tail##* · }"
  _ctl_pooldisks_resolve "$tail"
}

# _ctl_enter_pooldisks <line> — the disk sub-screen: Enter toggles one disk's
# binding (STAY, refresh re-marks in place); ← Back returns to the pool editor.
_ctl_enter_pooldisks() {
  local line="$1" nav cat i kind path p
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  i="$(nav_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_to_pooledit "$cat" "$i" "$kind")"
    echo render; return
  fi
  path="$(_ctl_line_to_disk "$line")"
  [[ -n "$path" ]] || { echo refresh; return; }
  p="$(_ctl_pool_get "$(_ctl_state)" "$kind" "$i")"
  _ctl_write_state "$(_ctl_pool_set "$(_ctl_state)" "$kind" "$i" \
    "$(_ctl_pool_toggle_disk "$p" "$path")")"
  echo refresh
}

# _ctl_enter_rootdisk <line> — the single-disk-root picker: Enter sets root_disk
# to the picked disk (single-select — replaces any prior) and returns to the
# category, since one pick is the whole job; ← Back → category.
_ctl_enter_rootdisk() {
  local line="$1" nav cat path
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_to_category "$cat")"; echo render; return
  fi
  path="$(_ctl_line_to_disk "$line")"
  [[ -n "$path" ]] || { echo refresh; return; }
  _ctl_write_state "$(cfgstate_set "$(_ctl_state)" root_disk "\"$path\"")"
  _ctl_write_nav "$(nav_to_category "$cat")"
  echo render
}

# guided_ctl_back — Esc: back one screen, or abort the whole menu at the top.
guided_ctl_back() {
  local nav; nav="$(_ctl_nav)"
  if [[ "$(nav_screen "$nav")" == "top" ]]; then echo abort; return; fi
  _ctl_write_nav "$(nav_back "$nav")"; echo render
}

# ── ^A / ^X context actions (ADR 0047 rich chrome) ───────────────────────────
# _ctl_datapools_line_ref <line> — the "<kind> <index>" of the pool a highlighted
# datapools list row addresses, or empty for a non-pool row (OS pool / + Add / ←
# Back). Shared by ^X-on-list removal. Pure: reads state to resolve name→index.
_ctl_datapools_line_ref() {
  local line="$1" name idx state; state="$(_ctl_state)"
  case "$line" in
  "OS pool:"* | "+ Add"* | "← Back") return 0 ;;
  *" (storage):"*)
    name="${line%% (storage):*}"
    idx="$(jq -r --arg n "$name" \
      '[(.storage_groups // [])[] | .name] | (index($n) // -1)' <<<"$state")"
    [[ "$idx" =~ ^[0-9]+$ ]] && printf 'storage %s' "$idx" ;;
  *)
    name="${line%%:*}"
    idx="$(jq -r --arg n "$name" \
      '[(.data_pools // [])[] | .name] | (index($n) // -1)' <<<"$state")"
    [[ "$idx" =~ ^[0-9]+$ ]] && printf 'data %s' "$idx" ;;
  esac
}

# The add/create/remove affordances that legacy chrome puts in the list ride on
# keybindings in rich mode. guided_ctl_action <add|add-storage|remove> [<line>]
# runs the current screen's context action and returns a directive (like the
# enter handlers), so ^A/^S/^X work identically to the legacy action rows. <line>
# is the highlighted row (used by ^X on the datapools list). A screen with no
# matching action returns `noop`.
guided_ctl_action() {
  local kind="$1" line="${2:-}" nav screen cat; nav="$(_ctl_nav)"
  screen="$(nav_screen "$nav")"; cat="$(nav_get "$nav" category)"
  case "$kind" in
  add)
    case "$screen" in
    datapools)
      _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"; echo refresh ;;
    values)
      case "$(nav_get "$nav" field)" in
      sysctl) _ctl_write_nav "$(nav_to_text "$cat" sysctl sysctl)"; echo render ;;
      users)  _ctl_write_nav "$(nav_to_text "$cat" __newuser__ "new user")"
              echo render ;;
      *)      echo noop ;;
      esac ;;
    category)
      # Add persist — only offered under Disks with impermanence on (else noop).
      if [[ "$cat" == "Disks" && "$(cfgstate_get \
        "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
        options.impermanence.enabled)" == "true" ]]; then
        _ctl_write_nav "$(nav_to_text "$cat" __persist__ "persist dir")"
        echo render
      else echo noop; fi ;;
    *) echo noop ;;
    esac ;;
  add-storage)
    # ^S — add a storage group (only meaningful on the datapools editor).
    case "$screen" in
    datapools)
      _ctl_write_state "$(_ctl_add_storage_group "$(_ctl_state)")"; echo refresh ;;
    *) echo noop ;;
    esac ;;
  remove)
    case "$screen" in
    pooledit)
      # Data pools and storage groups are removable; the OS pool is structural.
      local i k; i="$(nav_get "$nav" index)"; k="$(_ctl_pool_kind "$nav")"
      [[ "$k" == "data" || "$k" == "storage" ]] || { echo noop; return; }
      _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$k" "$i")"
      _ctl_write_nav "$(nav_to_datapools "$cat")"; echo render ;;
    datapools)
      # ^X on a highlighted pool row removes it in place (stay on the list). A
      # non-pool row (OS pool / + Add / ← Back) resolves to nothing → noop.
      local ref k i; ref="$(_ctl_datapools_line_ref "$line")"
      [[ -n "$ref" ]] || { echo noop; return; }
      k="${ref%% *}"; i="${ref##* }"
      _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$k" "$i")"; echo refresh ;;
    *) echo noop ;;
    esac ;;
  *) echo noop ;;
  esac
}

# ── rich-chrome footer + breadcrumb (ADR 0047) ───────────────────────────────
# _ctl_breadcrumb <nav> — the location breadcrumb for the list border-label
# (`--list-label`): Guided ▸ Category ▸ … . Pure: reads the nav (+ the pool name
# from state for the pool screens).
_ctl_breadcrumb() {
  local nav="$1" cat pool; cat="$(nav_get "$nav" category)"
  case "$(nav_screen "$nav")" in
  top)         printf ' Guided ' ;;
  category)    printf ' Guided ▸ %s ' "$cat" ;;
  values|text) printf ' Guided ▸ %s ▸ %s ' "$cat" "$(nav_get "$nav" label)" ;;
  swapedit)    printf ' Guided ▸ %s ▸ swap ' "$cat" ;;
  datapools)   printf ' Guided ▸ %s ▸ layout ' "$cat" ;;
  rootdisk)    printf ' Guided ▸ %s ▸ root disk ' "$cat" ;;
  pooledit | pooldisks)
    pool="$(jq -r '.name // .pool_name // "pool"' <<<"$(_ctl_pool_get \
      "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
      "$(_ctl_pool_kind "$nav")" "$(nav_get "$nav" index)")")"
    printf ' Guided ▸ %s ▸ layout ▸ %s ' "$cat" "$pool" ;;
  *) printf ' Guided ' ;;
  esac
}

# _ctl_footer_summary <nav> — the live one-line summary for the footer. On a pool
# screen it describes THAT pool ("tank0 · mirror · 2 bound"); elsewhere it is the
# whole-layout label. Pure: reads state.
_ctl_footer_summary() {
  local nav="$1" eff
  eff="$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
  case "$(nav_screen "$nav")" in
  pooledit | pooldisks)
    jq -r --arg k "$(_ctl_pool_kind "$nav")" \
      '. as $g | "\($g.name // $g.pool_name // "pool") · \($g.topology // "?") · "
       + (if ($g.devices // null) != null
          then "\($g.devices | length) bound"
          else "\($g.disk_count // "?") disks" end)' \
      <<<"$(_ctl_pool_get "$eff" "$(_ctl_pool_kind "$nav")" \
            "$(nav_get "$nav" index)")" ;;
  *) _ctl_layout_label "$eff" ;;
  esac
}

# _ctl_footer <nav> — the rich-chrome footer: this screen's context actions and
# a live summary, separated by a bar. Pure: reads the nav + state.
_ctl_footer() {
  local nav="$1" acts
  case "$(nav_screen "$nav")" in
  datapools) acts='^A data pool · ^S storage group · ^X remove · Esc back' ;;
  pooledit)
    case "$(_ctl_pool_kind "$nav")" in
    data)    acts='^X remove pool · Esc back' ;;
    storage) acts='^X remove group · Esc back' ;;
    *)       acts='Esc back' ;;
    esac ;;
  pooldisks) acts='Enter bind/unbind · Esc back' ;;
  rootdisk)  acts='Enter pick · Esc back' ;;
  values)
    case "$(nav_get "$nav" field)" in
    sysctl | users) acts='^A add · Esc back' ;;
    *)              acts='Enter choose · Esc back' ;;
    esac ;;
  category)  acts='Enter edit · Esc back' ;;
  *)         acts='Esc back' ;;
  esac
  printf '%s   │   %s' "$acts" "$(_ctl_footer_summary "$nav")"
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

# _ctl_nav_reconcile <nav> <state> → a nav still valid for <state>. A history op
# (reset/undo/redo) can delete the pool a pooledit/pooldisks nav addresses, which
# would then render "?" for the gone group (reset from inside a pool editor was
# the reported case). When the addressed pool is absent this backs the nav out to
# its category; any other nav is returned unchanged.
_ctl_nav_reconcile() {
  local nav="$1" state="$2" screen kind i exists
  screen="$(nav_screen "$nav")"
  case "$screen" in
  pooledit | pooldisks) ;;
  *) printf '%s' "$nav"; return ;;
  esac
  kind="$(_ctl_pool_kind "$nav")"; i="$(nav_get "$nav" index)"; i="${i:-0}"
  case "$kind" in
  os)      exists="$(jq -r 'if .os_pool then 1 else 0 end' <<<"$state")" ;;
  storage) exists="$(jq -r --argjson i "$i" \
             'if (.storage_groups[$i] // null) then 1 else 0 end' <<<"$state")" ;;
  *)       exists="$(jq -r --argjson i "$i" \
             'if (.data_pools[$i] // null) then 1 else 0 end' <<<"$state")" ;;
  esac
  if [[ "$exists" == "1" ]]; then printf '%s' "$nav"
  else nav_to_category "$(nav_get "$nav" category)"; fi
}

# guided_ctl_key <ctrl-z|ctrl-y|ctrl-r> — the global toolbar keys. ^Z undoes /
# ^Y redoes over the snapshot stack; ^R resets every override back to the seeded
# launch state (itself undoable — ^Z brings it back, so no confirm is needed).
# Each restores the Config State from the stack and re-renders in place; the nav
# is reconciled so a pool editor left pointing at a now-deleted pool backs out to
# its category instead of rendering "?" everywhere.
guided_ctl_key() {
  local k="$1" hist state
  [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]] || { echo noop; return; }
  hist="$(<"$GUIDED_HIST_FILE")"
  case "$k" in
  ctrl-z) hist="$(hist_undo "$hist")" ;;
  ctrl-y) hist="$(hist_redo "$hist")" ;;
  ctrl-r) hist="$(hist_commit "$hist" '{}')" ;;
  *)      echo noop; return ;;
  esac
  printf '%s\n' "$hist" >"$GUIDED_HIST_FILE"
  state="$(hist_present "$hist")"
  _ctl_write_state "$state"
  _ctl_write_nav "$(_ctl_nav_reconcile "$(_ctl_nav)" "$state")"
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
    # Rich chrome (fzf ≥ 0.62): a live footer (context actions + summary) and a
    # breadcrumb on the list-label. Legacy fzf gets neither (actions stay in the
    # list, header carries the keys) — the features are identical either way.
    local chrome=''
    if _ctl_rich_chrome; then
      chrome="$(printf '+change-footer(%s)+change-list-label(%s)' \
        "$(_ctl_footer "$nav")" "$(_ctl_breadcrumb "$nav")")"
    fi
    printf 'clear-query+reload(bash %q list)+change-header(%s)+change-prompt(%s)%s%s' \
      "$entry" "$(_ctl_nav_header "$nav")" "$(_ctl_nav_prompt "$nav")" "$pv" \
      "$chrome" ;;
  refresh)
    # same screen, just re-mark the list: reload-sync avoids the flicker a plain
    # reload shows, and keeps the query + header (no clear-query/change-*).
    # refresh-preview re-renders the live layout graph after a pool/disk edit;
    # a no-op where the preview pane is hidden. Rich chrome ALSO re-emits the
    # footer so its live summary (e.g. "2 bound") tracks a bind/add without a full
    # render — change-footer leaves the typed query untouched.
    local rfoot=''
    _ctl_rich_chrome && rfoot="$(printf '+change-footer(%s)' \
      "$(_ctl_footer "$(_ctl_nav)")")"
    printf 'reload-sync(bash %q list)+refresh-preview%s' "$entry" "$rfoot" ;;
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
