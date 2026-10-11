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

# The screens read guided_controller_list's navigation/state/base (dynamic
# scope).
# shellcheck disable=SC2154

# _controller_list_text — the `text` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_text() {
  local path current
  path="$(navigation_get "$navigation" field)"
  # the menu-displayed value (effective, else the field default) so a
  # defaulted
  # field shows e.g. "current: 2G" rather than "current: (unset)".
  current="$(_controller_field_display "$path" "$state" "$base")"
  printf 'current: %s\n' "${current:-(unset)}"
  printf '%s\n' "(type above, Enter saves · Esc cancels)"
}

# _controller_list_swap_edit — the `swapedit` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_swap_edit() {
  local effective; effective="$(_controller_effective "$state" "$base")"
  if [[ "$(_controller_swap_on "$effective")" == "false" ]]; then
    printf 'enabled: off\n'
  else
    printf 'enabled: on\n'
    printf 'size: %s\n' \
      "$(jq -r '.options.swap_size // "auto"' <<<"$effective")"
    if [[ "$(_controller_zswap_on "$effective")" == "false" ]]; then
      printf 'zswap: off\n'
    else
      printf 'zswap: on\n'
      printf 'compressor: %s   (Enter cycles)\n' \
        "$(jq -r '.options.zswap.compressor // "zstd"' <<<"$effective")"
      printf 'max pool %%: %s   (Enter cycles)\n' \
        "$(jq -r '.options.zswap.max_pool_percent // 20' <<<"$effective")"
    fi
  fi
  _controller_action_row "← Back"
}

# _controller_list_manual_partitions — the `manualparts` screen's rows (reads
# the caller's nav/state/base).
_controller_list_manual_partitions() {
  # Manual Partitioning assignment table (ADR 0073): a validity line, the
  # cfdisk hand-off, then one row per partition (device → mountpoint · fs).
  local partitions_json problems
  partitions_json="$(config_state_get "$state" disk_config.partitions)"; \
    partitions_json="${partitions_json:-[]}"
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
# caller's navigation/state/base).
_controller_list_partition_edit() {
  # Per-partition editor: mountpoint / filesystem / format, each cycled by
  # Enter. Only supported values are offered (ADR 0073).
  local device mountpoint filesystem format
  device="$(navigation_get "$navigation" device)"
  mountpoint="$(_controller_manual_field "$state" "$device" mountpoint)"
  filesystem="$(_controller_manual_field "$state" "$device" fs)"
  format="$(_controller_manual_field "$state" "$device" format)"
  printf 'device: %s\n' "$device"
  printf 'mountpoint: %s   (Enter cycles)\n' \
    "${mountpoint:-(unassigned)}"
  printf 'filesystem: %s   (Enter cycles)\n' "${filesystem:-(none)}"
  printf 'format: %s   (Enter toggles)\n' \
    "$([[ "$format" == "true" ]] && echo on || echo off)"
  _controller_action_row "← Back"
}

# _controller_list_encryption — the `encryption` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_encryption() {
  # The Encryption Editor (ADR 0059), collapsing like the swap editor above:
  # only the enablement row when off (a passphrase configures nothing then),
  # the passphrase row too when on. The passphrase row shows its source tag,
  # never the value.
  local effective; effective="$(_controller_effective "$state" "$base")"
  if [[ "$(config_state_get "$effective" options.encryption)" == "true" ]]; then
    printf 'enabled: on\n'
    printf 'password: %s\n' "$(_controller_secret_tag enc)"
  else
    printf 'enabled: off\n'
  fi
  _controller_action_row "← Back"
}

# _controller_list_impermanence — the `impermanence` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_impermanence() {
  # The Impermanence Editor (ADR 0066), collapsing like swap/encryption: only
  # the enablement row when off; when on, the persist directories (each a
  # removable row), a read-only curated-defaults count, and the Add action.
  local effective impermanence; \
    effective="$(_controller_effective "$state" "$base")"
  impermanence="$(config_state_get "$effective" options.impermanence.enabled)"
  if [[ "$impermanence" != "true" ]]; then
    printf 'enabled: off\n'
  else
    printf 'enabled: on\n'
    local persist_directory
    while IFS= read -r persist_directory; do
      [[ -n "$persist_directory" ]] && printf '%s\n' "$persist_directory"
    done < <(jq -r '(.persist.directories // [])[]' <<<"$effective")
    printf 'curated defaults: %s paths always persisted (read-only)\n' \
      "$(_controller_curated_persist_count)"
    _controller_action_row "Add persist directory ▸ extend the curated defaults"
  fi
  _controller_action_row "← Back"
}

# _controller_list_data_pools — the `datapools` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_data_pools() {
  # Unified layout editor (ADR 0047): OS pool + storage groups + data pools,
  # each row opening its per-kind editor. Distinct prefixes keep the enter
  # dispatch unambiguous: "OS pool:" (singleton), "<name> (storage):", and the
  # bare "<name>:" data-pool rows.
  local effective; effective="$(_controller_effective "$state" "$base")"
  jq -e '.os_pool' <<<"$effective" >/dev/null 2>&1 \
    && jq -r '"OS pool: \(.os_pool.topology // "?") "
              + "×\(.os_pool.disk_count // "?")"' \
      <<<"$effective"
  jq -r '(.storage_groups // [])[]
           | "\(.name) (storage): \(.topology) ×\(.disk_count)"' <<<"$effective"
  jq -r '(.data_pools // [])[] | "\(.name): \(.topology) ×\(.disk_count)"' \
    <<<"$effective"
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
# caller's navigation/state/base).
_controller_list_pool_edit() {
  local index kind pool effective root_filesystem
  index="$(navigation_get "$navigation" index)"; \
    kind="$(_controller_pool_kind "$navigation")"
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
# caller's navigation/state/base).
_controller_list_pool_disks() {
  local index kind pool effective disk
  index="$(navigation_get "$navigation" index)"; \
    kind="$(_controller_pool_kind "$navigation")"
  effective="$(_controller_effective "$state" "$base")"
  pool="$(_controller_pool_get "$effective" "$kind" "$index")"
  # Bound disks first (marked), then the still-free ones (unmarked) — an
  # Enter-toggle multi-select; an exhausted Free Set simply shows no [ ] rows.
  while IFS= read -r disk; do
    [[ -n "$disk" ]] && printf '[x] %s\n' "$(_controller_disk_label "$disk")"
  done < <(jq -r '(.devices // [])[]' <<<"$pool")
  while IFS= read -r disk; do
    [[ -n "$disk" ]] && printf '[ ] %s\n' "$(_controller_disk_label "$disk")"
  done < <(_controller_free_disks "$state")
  _controller_action_row "← Back"
}

# _controller_list_root_disk — the `rootdisk` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_root_disk() {
  # Single-select radio: the current root_disk marked (*) first (it is bound,
  # so
  # the Free Set excludes it — add it back), then every free candidate ( ).
  # Picking one replaces the prior choice.
  local root_disk disk
  root_disk="$(jq -r '.root_disk // ""' \
    <<<"$(_controller_effective "$state" "$base")")"
  [[ -n "$root_disk" ]] \
    && printf '(*) %s\n' "$(_controller_disk_label "$root_disk")"
  while IFS= read -r disk; do
    [[ -n "$disk" ]] && printf '( ) %s\n' "$(_controller_disk_label "$disk")"
  done < <(_controller_free_disks "$state")
  _controller_action_row "← Back"
}

# _controller_list_root_editor — the `rooteditor` screen's rows (reads the
# caller's navigation/state/base).
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
# caller's navigation/state/base).
_controller_list_user_edit() {
  # Per-user User Editor (ADR 0051): a committed user shows an `enabled`
  # toggle
  # (in/out of the install), an ad-hoc user a `✗ remove user` row; both show
  # the
  # full profile — shell, sudo, groups, git identity, ssh keys, programs —
  # read
  # from the effective (committed `*` install-scoped override) view.
  local user user_effective; user="$(navigation_get "$navigation" user)"
  user_effective="$(_controller_user_effective "$user")"
  if _controller_user_is_committed "$user"; then
    local enabled; enabled="$(jq -r --arg u "$user" \
      'if ((.users // []) | any(. == $u)) then "on" else "off" end' \
      <<<"$(_controller_effective "$state" "$base")")"
    printf 'enabled: %s   (Enter toggles)\n' "$enabled"
  fi
  printf 'shell: %s   (Enter cycles)\n' "$(_controller_user_shell "$user")"
  printf 'sudo: %s   (Enter toggles)\n' \
    "$(jq -r 'if .sudo then "on" else "off" end' <<<"$user_effective")"
  printf 'groups: %s   (Enter edits)\n' \
    "$(jq -r '(.groups // []) | join(", ")
              | if . == "" then "(none)" else . end' \
      <<<"$user_effective")"
  printf 'git name: %s   (Enter edits)\n' \
    "$(jq -r '.git.name // "(unset)"' <<<"$user_effective")"
  printf 'git email: %s   (Enter edits)\n' \
    "$(jq -r '.git.email // "(unset)"' <<<"$user_effective")"
  printf 'ssh keys: %s   (Enter edits)\n' \
    "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$user_effective")"
  printf 'programs: %s   (Enter edits)\n' \
    "$(jq -r '(.programs // []) | join(", ")
              | if . == "" then "(none)" else . end' \
      <<<"$user_effective")"
  printf '%s\n' "⧉ Clone this user"
  _controller_user_is_committed "$user" || printf '%s\n' "✗ remove user"
  _controller_action_row "← Back"
}

# _controller_list_user_field — the `userfield` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_user_field() {
  # A user-scoped sub-editor (ADR 0051): multi (groups/programs) marks options
  # against the effective value; text (git.name/git.email) shows current +
  # hint;
  # list (ssh) shows the keys + an add action.
  local user field; user="$(navigation_get "$navigation" user)"; \
    field="$(navigation_get "$navigation" field)"
  case "$(_controller_user_field_kind "$field")" in
  multi)
    local selected option
    selected="$(jq -c --arg f "$field" '.[$f] // []' \
      <<<"$(_controller_user_effective "$user")")"
    while IFS= read -r option; do
      if jq -ne --argjson s "$selected" --arg o "$option" 'any($s[]; . == $o)' \
          >/dev/null 2>&1; then printf '[x] %s\n' "$option"
      else printf '[ ] %s\n' "$option"; fi
    done < <(_controller_user_field_options "$field")
    _controller_action_row "← Back" ;;
  text)
    local current
    if [[ "$field" == git.* ]]; then
      current="$(jq -r --arg k "${field#git.}" '.git[$k] // ""' \
        <<<"$(_controller_user_effective "$user")")"
      printf 'current: %s\n' "${current:-(unset)}"
    fi
    printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
  list)
    local key
    while IFS= read -r key; do [[ -n "$key" ]] && printf '%s\n' "$key"; done \
      < <(jq -r '(.ssh_authorized_keys // [])[]' \
        <<<"$(_controller_user_effective "$user")")
    _controller_action_row "+ Add SSH key" ;;
  esac
}

# _controller_list_secret — the `secret` screen's rows (reads the
# caller's navigation/state/base).
_controller_list_secret() {
  # Inline masked password entry (ADR 0051): the operator types into the fzf
  # query line (masked to bullets by the change bind); this body is just the
  # hint for the current target + phase. The value is read from the buffer
  # file
  # on Enter, never shown here.
  local target phase who
  target="$(navigation_get "$navigation" target)"; \
    phase="$(navigation_get "$navigation" phase)"
  case "$target" in
  user) who="$(navigation_get "$navigation" user)" ;;
  enc)  who="encryption" ;;
  *)    who="root" ;;
  esac
  if [[ "$phase" == "confirm" ]]; then
    printf 'confirm %s password — type it again, Enter saves\n' "$who"
  else
    printf 'set %s password — type it, Enter continues\n' "$who"
  fi
  printf '%s\n' "(masked · backspace to fix · Esc cancels)"
}
