#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-list-editors.sh — list rendering: editor screens
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042): the
# _controller_list_<screen> rows guided_controller_list dispatches to for the
# text, swap, partition, encryption, pool, disk, user and secret editors.
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# _controller_list_text — the `text` screen's rows (reads the
# caller's nav/state/base).
_controller_list_text() {
  local path cur
  path="$(navigation_get "$nav" field)"
  # the menu-displayed value (effective, else the field default) so a
  # defaulted
  # field shows e.g. "current: 2G" rather than "current: (unset)".
  cur="$(_controller_field_display "$path" "$state" "$base")"
  printf 'current: %s\n' "${cur:-(unset)}"
  printf '%s\n' "(type above, Enter saves · Esc cancels)"
}

# _controller_list_swap_edit — the `swapedit` screen's rows (reads the
# caller's nav/state/base).
_controller_list_swap_edit() {
  local _eff; _eff="$(_controller_effective "$state" "$base")"
  if [[ "$(_controller_swap_on "$_eff")" == "false" ]]; then
    printf 'enabled: off\n'
  else
    printf 'enabled: on\n'
    printf 'size: %s\n' "$(jq -r '.options.swap_size // "auto"' <<<"$_eff")"
    if [[ "$(_controller_zswap_on "$_eff")" == "false" ]]; then
      printf 'zswap: off\n'
    else
      printf 'zswap: on\n'
      printf 'compressor: %s   (Enter cycles)\n' \
        "$(jq -r '.options.zswap.compressor // "zstd"' <<<"$_eff")"
      printf 'max pool %%: %s   (Enter cycles)\n' \
        "$(jq -r '.options.zswap.max_pool_percent // 20' <<<"$_eff")"
    fi
  fi
  _controller_action_row "← Back"
}

# _controller_list_manual_partitions — the `manualparts` screen's rows (reads the
# caller's nav/state/base).
_controller_list_manual_partitions() {
  # Manual Partitioning assignment table (ADR 0073): a validity line, the
  # cfdisk hand-off, then one row per partition (device → mountpoint · fs).
  local partitions_json problems
  partitions_json="$(config_state_get "$state" disk_config.partitions)"; partitions_json="${partitions_json:-[]}"
  if problems="$(layout_manual_partition_problems "$partitions_json")"; then
    printf '✓ layout is valid — ready to Proceed\n'
  else
    printf '⚠ not installable: %s\n' \
      "$(awk 'NR == 1 { sub(/^• /, ""); print; exit }' <<<"$problems")"
  fi
  _controller_action_row "⟳ Run cfdisk (edit the partition table)"
  jq -c '.[]' <<< "$partitions_json" | while IFS= read -r partition; do
    manual_partition_row_label "$partition"; printf '\n'
  done
  _controller_action_row "← Back"
}

# _controller_list_partition_edit — the `partedit` screen's rows (reads the
# caller's nav/state/base).
_controller_list_partition_edit() {
  # Per-partition editor: mountpoint / filesystem / format, each cycled by
  # Enter. Only supported values are offered (ADR 0073).
  local _dev _mp _fs _fmt
  _dev="$(navigation_get "$nav" device)"
  _mp="$(_controller_manual_field "$state" "$_dev" mountpoint)"
  _fs="$(_controller_manual_field "$state" "$_dev" fs)"
  _fmt="$(_controller_manual_field "$state" "$_dev" format)"
  printf 'device: %s\n' "$_dev"
  printf 'mountpoint: %s   (Enter cycles)\n' \
    "${_mp:-(unassigned)}"
  printf 'filesystem: %s   (Enter cycles)\n' "${_fs:-(none)}"
  printf 'format: %s   (Enter toggles)\n' \
    "$([[ "$_fmt" == "true" ]] && echo on || echo off)"
  _controller_action_row "← Back"
}

# _controller_list_encryption — the `encryption` screen's rows (reads the
# caller's nav/state/base).
_controller_list_encryption() {
  # The Encryption Editor (ADR 0059), collapsing like the swap editor above:
  # only the enablement row when off (a passphrase configures nothing then),
  # the passphrase row too when on. The passphrase row shows its source tag,
  # never the value.
  local _eff; _eff="$(_controller_effective "$state" "$base")"
  if [[ "$(config_state_get "$_eff" options.encryption)" == "true" ]]; then
    printf 'enabled: on\n'
    printf 'password: %s\n' "$(_controller_secret_tag enc)"
  else
    printf 'enabled: off\n'
  fi
  _controller_action_row "← Back"
}

# _controller_list_impermanence — the `impermanence` screen's rows (reads the
# caller's nav/state/base).
_controller_list_impermanence() {
  # The Impermanence Editor (ADR 0066), collapsing like swap/encryption: only
  # the enablement row when off; when on, the persist directories (each a
  # removable row), a read-only curated-defaults count, and the Add action.
  local _eff _impen; _eff="$(_controller_effective "$state" "$base")"
  _impen="$(config_state_get "$_eff" options.impermanence.enabled)"
  if [[ "$_impen" != "true" ]]; then
    printf 'enabled: off\n'
  else
    printf 'enabled: on\n'
    local _pd
    while IFS= read -r _pd; do
      [[ -n "$_pd" ]] && printf '%s\n' "$_pd"
    done < <(jq -r '(.persist.directories // [])[]' <<<"$_eff")
    printf 'curated defaults: %s paths always persisted (read-only)\n' \
      "$(_controller_curated_persist_count)"
    _controller_action_row "Add persist directory ▸ extend the curated defaults"
  fi
  _controller_action_row "← Back"
}

# _controller_list_data_pools — the `datapools` screen's rows (reads the
# caller's nav/state/base).
_controller_list_data_pools() {
  # Unified layout editor (ADR 0047): OS pool + storage groups + data pools,
  # each row opening its per-kind editor. Distinct prefixes keep the enter
  # dispatch unambiguous: "OS pool:" (singleton), "<name> (storage):", and the
  # bare "<name>:" data-pool rows.
  local _eff; _eff="$(_controller_effective "$state" "$base")"
  jq -e '.os_pool' <<<"$_eff" >/dev/null 2>&1 \
    && jq -r '"OS pool: \(.os_pool.topology // "?") "
              + "×\(.os_pool.disk_count // "?")"' \
      <<<"$_eff"
  jq -r '(.storage_groups // [])[]
           | "\(.name) (storage): \(.topology) ×\(.disk_count)"' <<<"$_eff"
  jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
    <<<"$_eff"
  # The "+ Add …" rows stay visible in BOTH chromes: building the layout is
  # this
  # screen's primary action, and a footer-only ^A hint proved undiscoverable
  # (users saw tank0 and no way to add more). The parentheticals spell out the
  # distinction so the choice is obvious at author time: a data pool is an
  # independent zpool (own filesystem + own key); a storage group folds into
  # the
  # shared `dpool` (zfs, disk-wide key). Offering both lets Custom reconstruct
  # every preset (incl. os-mirror-raidz1). ← Back is legacy-only (Esc in
  # rich).
  printf '%s\n' \
    "+ Add data pool  (standalone pool · any filesystem · own key)" \
    "+ Add storage group  (shared dpool · zfs · disk-wide key)"
  _controller_action_row "← Back"
}

# _controller_list_pool_edit — the `pooledit` screen's rows (reads the
# caller's nav/state/base).
_controller_list_pool_edit() {
  local index kind pool effective root_filesystem
  index="$(navigation_get "$nav" index)"; kind="$(_controller_pool_kind "$nav")"
  effective="$(_controller_effective "$state" "$base")"
  pool="$(_controller_pool_get "$effective" "$kind" "$index")"
  # A group with no explicit filesystem inherits the root's (ADR 0043), so the
  # displayed value matches what the topology/disks cycles use.
  root_filesystem="$(jq -r '.filesystem // "zfs"' <<<"$effective")"
  printf 'name: %s\n' "$(jq -r '.name // .pool_name // "?"' <<<"$pool")"
  case "$kind" in
  os)
    # OS pool: topology + disks only. Root filesystem/encryption live at their
    # top-level rows (ADR 0047), never duplicated here.
    printf 'topology: %s   (Enter cycles)\n' \
      "$(jq -r '.topology // "?"' <<<"$pool")"
    _controller_disks_row "$pool" 1
    _controller_action_row "← Back" ;;
  storage)
    _controller_list_storage_group_rows ;;
  *)
    printf 'filesystem: %s   (Enter cycles)\n' \
      "$(jq -r --arg r "$root_filesystem" '.filesystem // $r' <<<"$pool")"
    printf 'topology: %s   (Enter cycles)\n' \
      "$(jq -r '.topology // "?"' <<<"$pool")"
    _controller_disks_row "$pool" 1
    printf 'encryption: %s   (Enter toggles)\n' \
      "$(jq -r '.encryption // false' <<<"$pool")"
    # mount defaults to /<name> (blank keeps the default); editable free-text.
    printf 'mount: %s   (Enter to edit)\n' \
      "$(jq -r '.mount // ("/" + (.name // "pool"))' <<<"$pool")"
    _controller_action_row "✗ remove this pool" "← Back" ;;
  esac
}

# _controller_list_storage_group_rows — a storage group's rows (reads the
# caller's pool/effective).
_controller_list_storage_group_rows() {
  # Storage group: a redundant data area folded into the shared `dpool`. Its
  # topology + disk count are editable (so Custom can rebuild
  # os-mirror-raidz1);
  # the mount is display-only (defaults to /<name>). It inherits the root
  # filesystem — no per-group fs/encryption rows (that is the data-pool
  # path).
  printf 'topology: %s   (Enter cycles)\n' \
    "$(jq -r '.topology // "?"' <<<"$pool")"
  _controller_disks_row "$pool" 1
  printf 'mount: %s\n' \
    "$(jq -r '.mount // ("/" + (.name // "data"))' <<<"$pool")"
  # Storage groups share dpool's encryption (the disk-wide setting) — shown
  # read-only, since they have no independent key (that is the data-pool
  # path).
  printf 'encryption: %s   (disk-wide, shared)\n' \
    "$([[ "$(jq -r '.options.encryption // false' <<<"$effective")" \
       == "true" ]] \
       && echo on || echo off)"
  _controller_action_row "✗ remove this group" "← Back"
}

# _controller_list_pool_disks — the `pooldisks` screen's rows (reads the
# caller's nav/state/base).
_controller_list_pool_disks() {
  local i kind p _eff d
  i="$(navigation_get "$nav" index)"; kind="$(_controller_pool_kind "$nav")"
  _eff="$(_controller_effective "$state" "$base")"
  p="$(_controller_pool_get "$_eff" "$kind" "$i")"
  # Bound disks first (marked), then the still-free ones (unmarked) — an
  # Enter-toggle multi-select; an exhausted Free Set simply shows no [ ] rows.
  while IFS= read -r d; do
    [[ -n "$d" ]] && printf '[x] %s\n' "$(_controller_disk_label "$d")"
  done < <(jq -r '(.devices // [])[]' <<<"$p")
  while IFS= read -r d; do
    [[ -n "$d" ]] && printf '[ ] %s\n' "$(_controller_disk_label "$d")"
  done < <(_controller_free_disks "$state")
  _controller_action_row "← Back"
}

# _controller_list_root_disk — the `rootdisk` screen's rows (reads the
# caller's nav/state/base).
_controller_list_root_disk() {
  # Single-select radio: the current root_disk marked (*) first (it is bound,
  # so
  # the Free Set excludes it — add it back), then every free candidate ( ).
  # Picking one replaces the prior choice.
  local _rd d
  _rd="$(jq -r '.root_disk // ""' <<<"$(_controller_effective "$state" "$base")")"
  [[ -n "$_rd" ]] && printf '(*) %s\n' "$(_controller_disk_label "$_rd")"
  while IFS= read -r d; do
    [[ -n "$d" ]] && printf '( ) %s\n' "$(_controller_disk_label "$d")"
  done < <(_controller_free_disks "$state")
  _controller_action_row "← Back"
}

# _controller_list_root_editor — the `rooteditor` screen's rows (reads the
# caller's nav/state/base).
_controller_list_root_editor() {
  # Root Editor (ADR 0063): root's two settings behind one editor, symmetric
  # with the per-user editor. Password uses the same masked capture + no-SOPS
  # root role; shell cycles /bin/bash → /bin/zsh → /bin/fish. Storage is
  # unchanged (options.root_shell + the root manifest role); only the surface
  # differs.
  printf 'password: %s\n' "$(_controller_secret_tag root)"
  printf 'shell: %s   (Enter cycles)\n' "$(_controller_root_shell)"
  _controller_action_row "← Back"
}

# _controller_list_user_edit — the `useredit` screen's rows (reads the
# caller's nav/state/base).
_controller_list_user_edit() {
  # Per-user User Editor (ADR 0051): a committed user shows an `enabled`
  # toggle
  # (in/out of the install), an ad-hoc user a `✗ remove user` row; both show
  # the
  # full profile — shell, sudo, groups, git identity, ssh keys, programs —
  # read
  # from the effective (committed `*` install-scoped override) view.
  local un ueff; un="$(navigation_get "$nav" user)"
  ueff="$(_controller_user_effective "$un")"
  if _controller_user_is_committed "$un"; then
    local _en; _en="$(jq -r --arg u "$un" \
      'if ((.users // []) | any(. == $u)) then "on" else "off" end' \
      <<<"$(_controller_effective "$state" "$base")")"
    printf 'enabled: %s   (Enter toggles)\n' "$_en"
  fi
  printf 'shell: %s   (Enter cycles)\n' "$(_controller_user_shell "$un")"
  printf 'sudo: %s   (Enter toggles)\n' \
    "$(jq -r 'if .sudo then "on" else "off" end' <<<"$ueff")"
  printf 'groups: %s   (Enter edits)\n' \
    "$(jq -r '(.groups // []) | join(", ")
              | if . == "" then "(none)" else . end' \
      <<<"$ueff")"
  printf 'git name: %s   (Enter edits)\n' \
    "$(jq -r '.git.name // "(unset)"' <<<"$ueff")"
  printf 'git email: %s   (Enter edits)\n' \
    "$(jq -r '.git.email // "(unset)"' <<<"$ueff")"
  printf 'ssh keys: %s   (Enter edits)\n' \
    "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$ueff")"
  printf 'programs: %s   (Enter edits)\n' \
    "$(jq -r '(.programs // []) | join(", ")
              | if . == "" then "(none)" else . end' \
      <<<"$ueff")"
  printf '%s\n' "⧉ Clone this user"
  _controller_user_is_committed "$un" || printf '%s\n' "✗ remove user"
  _controller_action_row "← Back"
}

# _controller_list_user_field — the `userfield` screen's rows (reads the
# caller's nav/state/base).
_controller_list_user_field() {
  # A user-scoped sub-editor (ADR 0051): multi (groups/programs) marks options
  # against the effective value; text (git.name/git.email) shows current +
  # hint;
  # list (ssh) shows the keys + an add action.
  local un field; un="$(navigation_get "$nav" user)"; field="$(navigation_get "$nav" field)"
  case "$(_controller_user_field_kind "$field")" in
  multi)
    local _sel _opt
    _sel="$(jq -c --arg f "$field" '.[$f] // []' \
      <<<"$(_controller_user_effective "$un")")"
    while IFS= read -r _opt; do
      if jq -ne --argjson s "$_sel" --arg o "$_opt" 'any($s[]; . == $o)' \
          >/dev/null 2>&1; then printf '[x] %s\n' "$_opt"
      else printf '[ ] %s\n' "$_opt"; fi
    done < <(_controller_user_field_options "$field")
    _controller_action_row "← Back" ;;
  text)
    local _cur
    if [[ "$field" == git.* ]]; then
      _cur="$(jq -r --arg k "${field#git.}" '.git[$k] // ""' \
        <<<"$(_controller_user_effective "$un")")"
      printf 'current: %s\n' "${_cur:-(unset)}"
    fi
    printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
  list)
    local _k
    while IFS= read -r _k; do [[ -n "$_k" ]] && printf '%s\n' "$_k"; done \
      < <(jq -r '(.ssh_authorized_keys // [])[]' \
        <<<"$(_controller_user_effective "$un")")
    _controller_action_row "+ Add SSH key" ;;
  esac
}

# _controller_list_secret — the `secret` screen's rows (reads the
# caller's nav/state/base).
_controller_list_secret() {
  # Inline masked password entry (ADR 0051): the operator types into the fzf
  # query line (masked to bullets by the change bind); this body is just the
  # hint for the current target + phase. The value is read from the buffer
  # file
  # on Enter, never shown here.
  local _tgt _ph _who
  _tgt="$(navigation_get "$nav" target)"; _ph="$(navigation_get "$nav" phase)"
  case "$_tgt" in
  user) _who="$(navigation_get "$nav" user)" ;;
  enc)  _who="encryption" ;;
  *)    _who="root" ;;
  esac
  if [[ "$_ph" == "confirm" ]]; then
    printf 'confirm %s password — type it again, Enter saves\n' "$_who"
  else
    printf 'set %s password — type it, Enter continues\n' "$_who"
  fi
  printf '%s\n' "(masked · backspace to fix · Esc cancels)"
}
