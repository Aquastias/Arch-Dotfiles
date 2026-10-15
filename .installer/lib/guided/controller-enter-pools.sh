#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-pools.sh — enter dispatch: swap, pools, disks, actions
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

_controller_enter_swap_edit() {
  local line="$1" navigation cat; navigation="$(_controller_navigation)"; \
    cat="$(navigation_get "$navigation" category)"
  case "$line" in
  "← Back")
    _controller_write_navigation \
      "$(navigation_back "$navigation")"; echo render; return ;;
  "enabled:"*)
    # flip options.swap; has("swap") keeps an explicit false from being read as
    # the default true (jq `//` false-swallow gotcha).
    _controller_write_state "$(jq '
      (if (.options // {} | has("swap")) then .options.swap else true end) as $c
      | .options.swap = ($c | not)' <<<"$(_controller_state)")"
    echo refresh; return ;;
  "size:"*)
    _controller_write_navigation \
      "$(navigation_to_text "$cat" options.swap_size "swap size")"
    echo render; return ;;
  "zswap:"*)
    _controller_write_state "$(jq '
      (if (.options.zswap // {} | has("enabled")) then .options.zswap.enabled
       else true end) as $c
      | .options.zswap.enabled = ($c | not)' <<<"$(_controller_state)")"
    echo refresh; return ;;
  "compressor:"*)
    _controller_write_state "$(jq --arg default "$(install_config_default \
        zswap_compressor)" '
      (.options.zswap.compressor // $default) as $c
      | .options.zswap.compressor =
          ({"zstd":"lz4","lz4":"lzo","lzo":"zstd"}[$c] // $default)' \
      <<<"$(_controller_state)")"
    echo refresh; return ;;
  "max pool %:"*)
    _controller_write_state "$(jq --argjson default "$(install_config_default \
        zswap_max_pool_percent)" '
      (.options.zswap.max_pool_percent // $default) as $p
      | .options.zswap.max_pool_percent =
          ({"5":10,"10":20,"20":40,"40":60,"60":5}[($p | tostring)]
           // $default)' \
      <<<"$(_controller_state)")"
    echo refresh; return ;;
  esac
  echo refresh
}

# _controller_enter_data_pools <line> — the data-pools list editor: add a
# tank<N> pool (auto-named, default mirror ×2; forces multi + a default OS
# pool), or open a pool by name. STAYS on the list after an add (refresh).
_controller_enter_data_pools() {
  local line="$1" navigation cat name index
  navigation="$(_controller_navigation)"; \
    cat="$(navigation_get "$navigation" category)"
  case "$line" in
  "← Back") _controller_write_navigation \
    "$(navigation_back "$navigation")"; echo render; return ;;
  "+ Add storage"*)
    _controller_write_state \
      "$(_controller_add_storage_group "$(_controller_state)")"
    echo refresh; return ;;
  "+ Add"*)
    _controller_write_state \
      "$(_controller_add_data_pool "$(_controller_state)")"
    echo refresh; return ;;
  "OS pool:"*)
    # the singleton OS pool editor (topology + disks, ADR 0047).
    _controller_write_navigation \
      "$(navigation_to_pool_edit "$cat" 0 os)"; echo render; return ;;
  *" (storage):"*)
    # a preset storage group (binding-only): parse its name, resolve its index.
    name="${line%% (storage):*}"
    index="$(jq -r --arg n "$name" \
      '[(.storage_groups // [])[] | .name] | (index($n) // -1)' \
      <<<"$(_controller_state)")"
    if [[ "$index" =~ ^[0-9]+$ ]]; then
      _controller_write_navigation \
        "$(navigation_to_pool_edit "$cat" "$index" storage)"
      echo render; return
    fi
    echo refresh; return ;;
  esac
  name="${line%%:*}"
  index="$(jq -r --arg n "$name" \
    '[(.data_pools // [])[] | .name] | (index($n) // -1)' \
    <<<"$(_controller_state)")"
  if [[ "$index" =~ ^[0-9]+$ ]]; then
    _controller_write_navigation \
      "$(navigation_to_pool_edit "$cat" "$index" data)"; echo render; return
  fi
  echo refresh
}

# _controller_enter_pool_edit <line> — edit data_pools[index]: cycle topology
# (stripe→mirror→raidz1→raidz2), cycle the disk count (1-8), or remove the pool.
_controller_enter_pool_edit() {
  local line="$1" navigation category index kind root_filesystem
  navigation="$(_controller_navigation)"
  category="$(navigation_get "$navigation" category)"
  index="$(navigation_get "$navigation" index)"
  kind="$(_controller_pool_kind "$navigation")"
  # The root filesystem a group inherits when it declares none (ADR 0043).
  root_filesystem="$(install_config_use_json "$(_controller_state)"
    install_config_filesystem)"
  case "$line" in
  "← Back")
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
    echo render ;;
  "✗ remove"*)
    _controller_write_state "$(_controller_pool_delete "$(_controller_state)" \
      "$kind" "$index")"
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
    echo render ;;
  "topology:"*)
    _controller_cycle_pool_topology "$kind" "$index" "$root_filesystem" ;;
  "filesystem:"*) _controller_cycle_pool_filesystem "$kind" "$index" ;;
  "encryption:"*) _controller_toggle_pool_encryption "$kind" "$index" ;;
  "mount:"*)
    # Only a data pool's mount is editable; a storage group's is preset-fixed
    # (display-only row, so Enter on it is a no-op).
    [[ "$kind" == "data" ]] || { echo refresh; return; }
    _controller_write_navigation \
      "$(navigation_to_pool_mount "$category" "$index")"
    echo render ;;
  "disks:"*)
    _controller_cycle_pool_disks "$kind" "$index" "$category" \
      "$root_filesystem" ;;
  *) echo refresh ;;
  esac
}

# _controller_cycle_pool_topology <kind> <index> <root-filesystem> — the cycle
# follows the group's own filesystem (pool value, else the root filesystem,
# else zfs) so btrfs groups get raid0/1/10 and ext4/xfs stay pinned to single
# (issue 09, ADR 0043).
_controller_cycle_pool_topology() {
  local kind="$1" index="$2" root_filesystem="$3" pool filesystem current next
  pool="$(_controller_pool_get "$(_controller_state)" "$kind" "$index")"
  filesystem="$(jq -r --arg r "$root_filesystem" '.filesystem // $r' \
    <<<"$pool")"
  current="$(jq -r '.topology // ""' <<<"$pool")"
  next="$(_controller_cycle_topology "$filesystem" "$current")"
  _controller_write_state "$(_controller_pool_set "$(_controller_state)" \
    "$kind" "$index" "$(jq -c --arg t "$next" '.topology = $t' <<<"$pool")")"
  echo refresh
}

# _controller_cycle_pool_filesystem <kind> <index> — cycle the group's
# filesystem through the built adapters, then normalise the group for its new
# filesystem (ext4/xfs → single-disk; a topology invalid for the new
# filesystem resets to that filesystem's first) via
# _controller_pool_normalise_filesystem. Only data pools expose a filesystem
# row, so this stays index-scoped to data.
_controller_cycle_pool_filesystem() {
  local kind="$1" index="$2" pool current next
  pool="$(_controller_pool_get "$(_controller_state)" "$kind" "$index")"
  current="$(jq -r '.filesystem // "zfs"' <<<"$pool")"  # raw-config-ok: a pool
  # shellcheck disable=SC2046 # word-split the built-fs list into cycle args
  next="$(_controller_cycle_next "$current" \
    $(_controller_built_root_filesystems))"
  _controller_write_state "$(_controller_pool_normalise_filesystem \
    "$(_controller_state)" "$index" "$next")"
  echo refresh
}

# _controller_toggle_pool_encryption <kind> <index> — storage groups inherit
# dpool's disk-wide encryption — no per-group toggle.
_controller_toggle_pool_encryption() {
  local kind="$1" index="$2" pool
  [[ "$kind" == "storage" ]] && { echo refresh; return; }
  pool="$(_controller_pool_get "$(_controller_state)" "$kind" "$index")"
  _controller_write_state "$(_controller_pool_set "$(_controller_state)" \
    "$kind" "$index" \
    "$(jq -c '.encryption = ((.encryption // false) | not)' <<<"$pool")")"
  echo refresh
}

# _controller_cycle_pool_disks <kind> <index> <category> <root-filesystem> —
# device-mode: the disks row opens the bind sub-screen instead of cycling.
# ext4/xfs are single-disk only (ADR 0043): their disk count is pinned at 1,
# so the cycle is a no-op there; other filesystems cycle 1-8.
_controller_cycle_pool_disks() {
  local kind="$1" index="$2" category="$3" root_filesystem="$4" pool
  if _controller_device_mode; then
    _controller_write_navigation \
      "$(navigation_to_pool_disks "$category" "$index" "$kind")"
    echo render; return
  fi
  pool="$(_controller_pool_get "$(_controller_state)" "$kind" "$index")"
  _controller_write_state "$(_controller_pool_set "$(_controller_state)" \
    "$kind" "$index" "$(jq -c --arg r "$root_filesystem" '
      (.filesystem // $r) as $fs
      | if ($fs == "ext4" or $fs == "xfs") then .disk_count = 1
        else .disk_count |= (if . >= 8 then 1 else . + 1 end) end' \
      <<<"$pool")")"
  echo refresh
}

# _controller_pool_disks_resolve <tail> — the full by-id path whose basename
# matches the label tail (enumeration includes bound disks — they are still
# physically present — so this resolves both a bind and an unbind).
_controller_pool_disks_resolve() {
  picker_enum_disks "$(_controller_live_set)" | awk -v t="$1" '
    { n = $0; sub(/.*\//, "", n); if (n == t) { print; exit } }'
}

# _controller_line_to_disk <line> — the full by-id path a picked disk row
# resolves to: strip the 4-char mark ("[x] "/"[ ] "/"(*) "/"( ) "), take the
# by-id tail (the segment after the last " · "), and resolve it. Empty when it
# doesn't resolve.
_controller_line_to_disk() {
  local tail="${1:4}"; tail="${tail##* · }"
  _controller_pool_disks_resolve "$tail"
}

# _controller_enter_pool_disks <line> — the disk sub-screen: Enter toggles one
# disk's binding (STAY, refresh re-marks in place); ← Back returns to the pool
# editor.
_controller_enter_pool_disks() {
  local line="$1" navigation cat i kind path pool
  navigation="$(_controller_navigation)"; \
    cat="$(navigation_get "$navigation" category)"
  i="$(navigation_get "$navigation" index)"; \
    kind="$(_controller_pool_kind "$navigation")"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation \
      "$(navigation_to_pool_edit "$cat" "$i" "$kind")"
    echo render; return
  fi
  path="$(_controller_line_to_disk "$line")"
  [[ -n "$path" ]] || { echo refresh; return; }
  pool="$(_controller_pool_get "$(_controller_state)" "$kind" "$i")"
  _controller_write_state "$(_controller_pool_set "$(_controller_state)" \
    "$kind" "$i" \
    "$(_controller_pool_toggle_disk "$pool" "$path")")"
  echo refresh
}

# _controller_enter_root_disk <line> — the single-disk-root picker: Enter sets
# root_disk to the picked disk (single-select — replaces any prior) and returns
# to the category, since one pick is the whole job; ← Back → category.
_controller_enter_root_disk() {
  local line="$1" navigation cat path
  navigation="$(_controller_navigation)"; \
    cat="$(navigation_get "$navigation" category)"
  if [[ "$line" == "← Back" ]]; then
    _controller_write_navigation \
      "$(navigation_to_category "$cat")"; echo render; return
  fi
  path="$(_controller_line_to_disk "$line")"
  [[ -n "$path" ]] || { echo refresh; return; }
  _controller_write_state \
    "$(config_state_set "$(_controller_state)" root_disk "\"$path\"")"
  _controller_write_navigation "$(navigation_to_category "$cat")"
  echo render
}

# guided_controller_back — Esc: back one screen, or abort the whole menu at the
# top.
guided_controller_back() {
  local navigation; navigation="$(_controller_navigation)"
  if [[ "$(navigation_screen "$navigation")" == \
    "top" ]]; then echo abort; return; fi
  _controller_write_navigation "$(navigation_back "$navigation")"; echo render
}

# ── ^A / ^X context actions (ADR 0047 rich chrome) ───────────────────────────
# _controller_data_pools_line_reference <line> — the "<kind> <index>" of the
# pool a highlighted datapools list row addresses, or empty for a non-pool row
# (OS pool / + Add / ← Back). Shared by ^X-on-list removal. Pure: reads state to
# resolve name→index.
_controller_data_pools_line_reference() {
  local line="$1" name index state; state="$(_controller_state)"
  case "$line" in
  "OS pool:"* | "+ Add"* | "← Back") return 0 ;;
  *" (storage):"*)
    name="${line%% (storage):*}"
    index="$(jq -r --arg n "$name" \
      '[(.storage_groups // [])[] | .name] | (index($n) // -1)' <<<"$state")"
    [[ "$index" =~ ^[0-9]+$ ]] && printf 'storage %s' "$index" ;;
  *)
    name="${line%%:*}"
    index="$(jq -r --arg n "$name" \
      '[(.data_pools // [])[] | .name] | (index($n) // -1)' <<<"$state")"
    [[ "$index" =~ ^[0-9]+$ ]] && printf 'data %s' "$index" ;;
  esac
}

# The add/create/remove affordances that legacy chrome puts in the list ride on
# keybindings in rich mode. guided_controller_action <add|add-storage|remove>
# [<line>] runs the current screen's context action and returns a directive
# (like the enter handlers), so ^A/^S/^X work identically to the legacy action
# rows. <line> is the highlighted row (used by ^X on the datapools list). A
# screen with no matching action returns `noop`.
guided_controller_action() {
  local kind="$1" line="${2:-}" navigation screen category
  navigation="$(_controller_navigation)"
  screen="$(navigation_screen "$navigation")"
  category="$(navigation_get "$navigation" category)"
  case "$kind" in
  add) _controller_add_action "$screen" "$navigation" "$category" ;;
  add-storage)
    # ^S — add a storage group (only meaningful on the datapools editor).
    if [[ "$screen" == datapools ]]; then
      _controller_write_state \
        "$(_controller_add_storage_group "$(_controller_state)")"
      echo refresh
    else
      echo noop
    fi ;;
  remove)
    _controller_remove_action "$screen" "$navigation" "$category" "$line" ;;
  *) echo noop ;;
  esac
}

# _controller_add_action <screen> <navigation> <category> — ^A.
_controller_add_action() {
  local screen="$1" navigation="$2" category="$3"
  case "$screen" in
  datapools)
    _controller_write_state \
      "$(_controller_add_data_pool "$(_controller_state)")"
    echo refresh ;;
  values)
    case "$(navigation_get "$navigation" field)" in
    sysctl)
      _controller_write_navigation \
        "$(navigation_to_text "$category" sysctl sysctl)"
      echo render ;;
    users)
      _controller_write_navigation \
        "$(navigation_to_text "$category" __newuser__ "new user")"
      echo render ;;
    *) echo noop ;;
    esac ;;
  impermanence)
    # Add persist — the editor's ^A accelerator (ADR 0066). Only meaningful
    # with impermanence on (the add row only renders then; else noop).
    if [[ "$(config_state_get "$(_controller_effective "$(_controller_state)" \
          "$(_controller_baseline)")" options.impermanence.enabled)" \
          == "true" ]]; then
      _controller_write_navigation \
        "$(navigation_to_text "$category" __persist__ "persist dir")"
      echo render
    else echo noop; fi ;;
  *) echo noop ;;
  esac
}

# _controller_remove_action <screen> <navigation> <category> <line> — ^X.
_controller_remove_action() {
  local screen="$1" navigation="$2" category="$3" line="$4"
  local pool_kind index reference
  case "$screen" in
  pooledit)
    # Data pools and storage groups are removable; the OS pool is structural.
    index="$(navigation_get "$navigation" index)"
    pool_kind="$(_controller_pool_kind "$navigation")"
    [[ "$pool_kind" == "data" || "$pool_kind" == "storage" ]] \
      || { echo noop; return; }
    _controller_write_state "$(_controller_pool_delete "$(_controller_state)" \
      "$pool_kind" "$index")"
    _controller_write_navigation "$(navigation_to_data_pools "$category")"
    echo render ;;
  datapools)
    # ^X on a highlighted pool row removes it in place (stay on the list). A
    # non-pool row (OS pool / + Add / ← Back) resolves to nothing → noop.
    reference="$(_controller_data_pools_line_reference "$line")"
    [[ -n "$reference" ]] || { echo noop; return; }
    pool_kind="${reference%% *}"; index="${reference##* }"
    _controller_write_state "$(_controller_pool_delete "$(_controller_state)" \
      "$pool_kind" "$index")"
    echo refresh ;;
  *) echo noop ;;
  esac
}
