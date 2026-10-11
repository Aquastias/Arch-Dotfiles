#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-enter-pools.sh — enter dispatch: swap, pools, disks, actions
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

_ctl_enter_swapedit() {
  local line="$1" nav cat; nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(navigation_back "$nav")"; echo render; return ;;
  "enabled:"*)
    # flip options.swap; has("swap") keeps an explicit false from being read as
    # the default true (jq `//` false-swallow gotcha).
    _ctl_write_state "$(jq '
      (if (.options // {} | has("swap")) then .options.swap else true end) as $c
      | .options.swap = ($c | not)' <<<"$(_ctl_state)")"
    echo refresh; return ;;
  "size:"*)
    _ctl_write_nav "$(navigation_to_text "$cat" options.swap_size "swap size")"
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
  nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  case "$line" in
  "← Back") _ctl_write_nav "$(navigation_back "$nav")"; echo render; return ;;
  "+ Add storage"*)
    _ctl_write_state "$(_ctl_add_storage_group "$(_ctl_state)")"
    echo refresh; return ;;
  "+ Add"*)
    _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"
    echo refresh; return ;;
  "OS pool:"*)
    # the singleton OS pool editor (topology + disks, ADR 0047).
    _ctl_write_nav "$(navigation_to_pool_edit "$cat" 0 os)"; echo render; return ;;
  *" (storage):"*)
    # a preset storage group (binding-only): parse its name, resolve its index.
    name="${line%% (storage):*}"
    idx="$(jq -r --arg n "$name" \
      '[(.storage_groups // [])[] | .name] | (index($n) // -1)' \
      <<<"$(_ctl_state)")"
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      _ctl_write_nav "$(navigation_to_pool_edit "$cat" "$idx" storage)"
      echo render; return
    fi
    echo refresh; return ;;
  esac
  name="${line%%:*}"
  idx="$(jq -r --arg n "$name" \
    '[(.data_pools // [])[] | .name] | (index($n) // -1)' <<<"$(_ctl_state)")"
  if [[ "$idx" =~ ^[0-9]+$ ]]; then
    _ctl_write_nav "$(navigation_to_pool_edit "$cat" "$idx" data)"; echo render; return
  fi
  echo refresh
}

# _ctl_enter_pooledit <line> — edit data_pools[index]: cycle topology
# (stripe→mirror→raidz1→raidz2), cycle the disk count (1-8), or remove the pool.
_ctl_enter_pooledit() {
  local line="$1" nav cat i kind _rfs p
  nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  i="$(navigation_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
  # The root filesystem a group inherits when it declares none (ADR 0043).
  _rfs="$(jq -r '.filesystem // "zfs"' <<<"$(_ctl_state)")"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(navigation_to_data_pools "$cat")"; echo render; return ;;
  "✗ remove"*)
    _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$kind" "$i")"
    _ctl_write_nav "$(navigation_to_data_pools "$cat")"; echo render; return ;;
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
    # Cycle the group's filesystem through the built adapters, then normalise
    # the
    # group for its new filesystem (ext4/xfs → single-disk; a topology invalid
    # for
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
    _ctl_write_nav "$(navigation_to_pool_mount "$cat" "$i")"; echo render; return ;;
  "disks:"*)
    # Device-mode: the disks row opens the bind sub-screen instead of cycling.
    if _ctl_device_mode; then
      _ctl_write_nav "$(navigation_to_pool_disks "$cat" "$i" "$kind")"
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
  nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  i="$(navigation_get "$nav" index)"; kind="$(_ctl_pool_kind "$nav")"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(navigation_to_pool_edit "$cat" "$i" "$kind")"
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
  nav="$(_ctl_nav)"; cat="$(navigation_get "$nav" category)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(navigation_to_category "$cat")"; echo render; return
  fi
  path="$(_ctl_line_to_disk "$line")"
  [[ -n "$path" ]] || { echo refresh; return; }
  _ctl_write_state "$(config_state_set "$(_ctl_state)" root_disk "\"$path\"")"
  _ctl_write_nav "$(navigation_to_category "$cat")"
  echo render
}

# guided_ctl_back — Esc: back one screen, or abort the whole menu at the top.
guided_ctl_back() {
  local nav; nav="$(_ctl_nav)"
  if [[ "$(navigation_screen "$nav")" == "top" ]]; then echo abort; return; fi
  _ctl_write_nav "$(navigation_back "$nav")"; echo render
}

# ── ^A / ^X context actions (ADR 0047 rich chrome) ───────────────────────────
# _ctl_datapools_line_ref <line> — the "<kind> <index>" of the pool a
# highlighted
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
# enter handlers), so ^A/^S/^X work identically to the legacy action rows.
# <line>
# is the highlighted row (used by ^X on the datapools list). A screen with no
# matching action returns `noop`.
guided_ctl_action() {
  local kind="$1" line="${2:-}" nav screen cat; nav="$(_ctl_nav)"
  screen="$(navigation_screen "$nav")"; cat="$(navigation_get "$nav" category)"
  case "$kind" in
  add)
    case "$screen" in
    datapools)
      _ctl_write_state "$(_ctl_add_data_pool "$(_ctl_state)")"; echo refresh ;;
    values)
      case "$(navigation_get "$nav" field)" in
      sysctl)
        _ctl_write_nav "$(navigation_to_text "$cat" sysctl sysctl)"; echo render ;;
      users)  _ctl_write_nav "$(navigation_to_text "$cat" __newuser__ "new user")"
              echo render ;;
      *)      echo noop ;;
      esac ;;
    impermanence)
      # Add persist — the editor's ^A accelerator (ADR 0066). Only meaningful
      # with impermanence on (the add row only renders then; else noop).
      if [[ "$(config_state_get \
        "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
        options.impermanence.enabled)" == "true" ]]; then
        _ctl_write_nav "$(navigation_to_text "$cat" __persist__ "persist dir")"
        echo render
      else echo noop; fi ;;
    *) echo noop ;;
    esac ;;
  add-storage)
    # ^S — add a storage group (only meaningful on the datapools editor).
    case "$screen" in
    datapools)
      _ctl_write_state "$(_ctl_add_storage_group "$(_ctl_state)")"
      echo refresh ;;
    *) echo noop ;;
    esac ;;
  remove)
    case "$screen" in
    pooledit)
      # Data pools and storage groups are removable; the OS pool is structural.
      local i k; i="$(navigation_get "$nav" index)"; k="$(_ctl_pool_kind "$nav")"
      [[ "$k" == "data" || "$k" == "storage" ]] || { echo noop; return; }
      _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$k" "$i")"
      _ctl_write_nav "$(navigation_to_data_pools "$cat")"; echo render ;;
    datapools)
      # ^X on a highlighted pool row removes it in place (stay on the list). A
      # non-pool row (OS pool / + Add / ← Back) resolves to nothing → noop.
      local ref k i; ref="$(_ctl_datapools_line_ref "$line")"
      [[ -n "$ref" ]] || { echo noop; return; }
      k="${ref%% *}"; i="${ref##* }"
      _ctl_write_state "$(_ctl_pool_del "$(_ctl_state)" "$k" "$i")"
      echo refresh ;;
    *) echo noop ;;
    esac ;;
  *) echo noop ;;
  esac
}
