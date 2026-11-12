#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-chrome.sh — headers, prompts, layout labels, footer
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── per-screen header + prompt (so every screen says how to go back) ─────────
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

_controller_navigation_header() {
  local keys
  case "$(navigation_screen "$1")" in
  top)      keys='Enter open   Esc quit' ;;
  profiles) keys='Enter seed from profile   Esc back' ;;
  newhost)  keys='Enter confirm reset   Esc cancel' ;;
  rooteditor) keys='Enter edit/cycle   Esc back' ;;
  category) keys='Enter edit / cycle   Esc back' ;;
  values)
    if [[ "$(navigation_get "$1" field)" == "users" ]]; then
      keys='Enter toggle / set pw   Esc back'
    elif [[ "$(_controller_field_kind "$(navigation_get "$1" field)")" == \
      "toggle" ]]; then
      keys='Enter toggle ✓   Esc done'
    else
      keys='Enter choose   Esc back'
    fi ;;
  text)     keys='Type a value, Enter save   Esc back' ;;
  swapedit)  keys='Enter edit/toggle   Esc back' ;;
  manualparts) keys='Enter open / cfdisk   Esc back' ;;
  partedit)  keys='Enter cycle/toggle   Esc back' ;;
  encryption) keys='Enter edit/toggle   Esc back' ;;
  impermanence) keys='Enter edit/toggle/remove   Esc back' ;;
  datapools) keys='Enter open/add   Esc back' ;;
  pooledit)  keys='Enter cycle/remove   Esc back' ;;
  pooldisks) keys='Enter bind/unbind ✓   Esc back' ;;
  rootdisk)  keys='Enter pick   Esc back' ;;
  useredit)  keys='Enter edit/toggle   Esc back' ;;
  userfield)
    case "$(_controller_user_field_kind "$(navigation_get "$1" field)")" in
    multi) keys='Enter toggle ✓   Esc back' ;;
    text)  keys='Type a value, Enter save   Esc back' ;;
    list)  keys='Enter add   Esc back' ;;
    esac ;;
  secret)    keys='Type the password, Enter continues   Esc cancels' ;;
  pkgcat)    keys='Enter open / add   Esc back' ;;
  pkgs)      keys='Enter toggle ✓   Esc back' ;;
  pkgbrowse) keys='Type to filter · Enter add/remove ✓   Esc back' ;;
  pkgderived)    keys='Enter open (read-only)   Esc back' ;;
  pkgderivedsrc) keys='Read-only — change it in Environment/Security/Backup' ;;
  *)        keys='Esc back' ;;
  esac
  printf '%s   ·   ^Z undo  ^Y redo  ^R reset' "$keys"
}
_controller_navigation_prompt() {
  case "$(navigation_screen "$1")" in
  top)         printf 'guided> ' ;;
  profiles)    printf 'profiles> ' ;;
  newhost)     printf 'reset> ' ;;
  rooteditor)  printf 'root> ' ;;
  category)    printf '%s> ' "$(navigation_get "$1" category)" ;;
  values|text) printf '%s> ' "$(navigation_get "$1" label)" ;;
  swapedit)    printf 'swap> ' ;;
  manualparts) printf 'partitions> ' ;;
  partedit)    printf 'partition> ' ;;
  encryption)  printf 'encryption> ' ;;
  impermanence) printf 'impermanence> ' ;;
  datapools)   printf 'data pools> ' ;;
  pooledit)    printf 'pool> ' ;;
  pooldisks)   printf 'disks> ' ;;
  rootdisk)    printf 'root disk> ' ;;
  useredit)    printf '%s> ' "$(navigation_get "$1" user)" ;;
  userfield)   printf '%s> ' "$(navigation_get "$1" label)" ;;
  secret)      printf 'password> ' ;;
  pkgcat)        printf '%s> ' "$(navigation_get "$1" slot)" ;;
  pkgs)          printf '%s/%s> ' "$(navigation_get "$1" slot)" \
                   "$(navigation_get "$1" pkgcat)" ;;
  pkgbrowse)     printf '%s pkg> ' "$(navigation_get "$1" slot)" ;;
  pkgderived)    printf 'derived> ' ;;
  pkgderivedsrc) printf 'derived/%s> ' "$(navigation_get "$1" source)" ;;
  *)           printf 'guided> ' ;;
  esac
}

# _controller_esp_budget_warn <effective-json> → a one-line ⚠ when a PINNED
# esp_size is too small for the selected kernels on an ESP-mirroring loader (ADR
# 0078), so the conflict shows live on the Kernels / Disks screens, not only at
# Proceed. Nothing when esp_size is auto, the loader is grub, or the pin fits.
_controller_esp_budget_warn() {
  local effective="$1" size kernel_count filesystem bootloader
  size="$(install_config_from_json "$effective" esp_size)"
  [[ "$size" == auto ]] && return 0
  # get: count the tokens, no validation abort mid-render
  # get: count the tokens (one per line), no validation abort mid-render
  kernel_count="$(install_config_from_json "$effective" get kernels \
    | grep -c '')"
  filesystem="$(install_config_from_json "$effective" filesystem)"
  bootloader="$(install_config_from_json "$effective" bootloader)"
  esp_budget_fits_size "$size" "$kernel_count" "$filesystem" "$bootloader" \
    && return 0
  printf '⚠ ESP too small: %s %s kernel(s) need ≥ %s (esp size is %s)\n' \
    "$kernel_count" "$bootloader" \
    "$(esp_budget_auto_size "$kernel_count" "$filesystem" "$bootloader")" \
    "$size"
}

# _controller_layout_label <effective-json> → a one-line description of the
# current disk layout, so the Disks "Disk layout" row reflects the chosen preset
# instead of a static "choose preset". single → "single"; multi → "os <topo>
# ×<n>" plus any storage / data pool counts.
_controller_layout_label() {
  printf '%s\n' "$1" \
    | jq -r -f "${BASH_SOURCE[0]%/*}/controller-layout-label.jq"
}

# _controller_swap_on <effective-json> → "true"/"false": is swap enabled
# (default true)? config_state_get keeps an explicit `swap:false` (jq's `//`
# would read false as unset — see [[dotfiles_jq_alternative_false]]).
_controller_swap_on() {
  local swap
  swap="$(config_state_get "$1" options.swap)"
  printf '%s\n' "${swap:-true}"
}

# _controller_zswap_on <effective-json> → "true"/"false": is zswap enabled
# (default true)? An explicit false is honoured, not read as default.
_controller_zswap_on() {
  local zswap
  zswap="$(config_state_get "$1" options.zswap.enabled)"
  printf '%s\n' "${zswap:-true}"
}

# _controller_swap_label <effective-json> → the one-line swap summary for the
# Disks swap row: "off" when swap is disabled, else the size (default "auto")
# plus a zswap suffix — "· zswap <compressor>" when zswap is on, "· no zswap"
# when off (so a deviation from the zswap-on default is visible).
_controller_swap_label() {
  local size compressor
  if [[ "$(_controller_swap_on "$1")" == false ]]; then
    printf 'off\n'
    return 0
  fi
  size="$(config_state_get "$1" options.swap_size)"
  if [[ "$(_controller_zswap_on "$1")" == false ]]; then
    printf '%s · no zswap\n' "${size:-auto}"
  else
    compressor="$(config_state_get "$1" options.zswap.compressor)"
    printf '%s · zswap %s\n' "${size:-auto}" "${compressor:-zstd}"
  fi
}

# _controller_encryption_label <effective-json> <tag> → the one-line summary for
# the collapsed Disks Encryption row (ADR 0059): "off" when encryption is
# disabled, else "on · <tag>" where <tag> is the source tag (default <value> /
# custom / from age) computed by the caller. Pure: JSON + a string in, a string
# out — so the row text is testable without fzf or the secrets file, the way
# _controller_swap_ label is.
_controller_encryption_label() {
  local effective="$1" tag="$2"
  if [[ "$(config_state_get "$effective" options.encryption)" == "true" ]]; then
    printf 'on · %s' "$tag"
  else
    printf 'off'
  fi
}

# _controller_layout_graph <skeleton-json> → an ASCII tree of the layout for the
# preview
# pane (a pool per line + its topology / disk count).
_controller_layout_graph() {
  printf '%s\n' "$1" \
    | jq -r -f "${BASH_SOURCE[0]%/*}/controller-layout-graph.jq"
}

# _controller_add_data_pool <state> → state with one more data pool appended
# (auto-named tank<N>, default single-disk stripe ×1), forcing multi mode + a
# default OS pool. A 1-disk stripe is the friendliest default: it is the
# smallest installable pool (so adding several tanks never balloons the disk
# requirement), matches the data-pools preset, and the user cycles up to
# mirror/raidz for redundancy. Shared by the data-pools editor's "+ Add" and by
# picking "data-pools" in the layout.
_controller_add_data_pool() {
  local count pool state
  local new_pool='{name: $name, topology: "stripe", disk_count: 1}'
  local append='.data_pools = (.data_pools // []) + [$pool]'
  # How many data pools there are.
  count="$(printf '%s\n' "$1" | jq '(.data_pools // []) | length')"
  # The new pool: tank<count>, a 1-disk stripe.
  pool="$(jq -c -n --arg name "tank${count}" "$new_pool")"
  # The state with the pool appended.
  state="$(printf '%s\n' "$1" | jq --argjson pool "$pool" "$append")"
  _controller_force_multi "$state"
}

# _controller_add_storage_group <state> → state with one more storage group
# appended, forcing multi mode + a default OS pool. Storage groups fold into the
# shared `dpool` (each a redundant data area at /<name>), so a new one defaults
# to mirror ×2; the user cycles to raidz1 ×3 to rebuild the os-mirror-raidz1
# preset. The first group is auto-named "data" at /data (preset parity), then
# data1, … Shared by the data-pools editor's "+ Add storage group".
_controller_add_storage_group() {
  local count name group state
  local append='.storage_groups = (.storage_groups // []) + [$group]'
  local new_group='{name: $name, mount: ("/" + $name),'
  new_group+=' topology: "mirror", disk_count: 2}'
  # How many storage groups there are.
  count="$(printf '%s\n' "$1" | jq '(.storage_groups // []) | length')"
  name=data
  ((count > 0)) && name="data${count}"
  # The new group: <name> at /<name>, a 2-disk mirror.
  group="$(jq -c -n --arg name "$name" "$new_group")"
  # The state with the group appended.
  state="$(printf '%s\n' "$1" | jq --argjson group "$group" "$append")"
  _controller_force_multi "$state"
}

# _controller_force_multi <state> → <state> in multi mode, with the default OS
# pool (rpool, one disk) when it has none.
_controller_force_multi() {
  local state
  local os_pool='{"pool_name":"rpool","topology":"none","disk_count":1}'
  state="$(config_state_set "$1" mode '"multi"')"
  config_state_is_overridden "$state" os_pool \
    || state="$(config_state_set "$state" os_pool "$os_pool")"
  printf '%s\n' "$state"
}

# ── pool-group reference (kind, index) ───────────────────────────────────────
# The pool editor addresses any group through one uniform reference so a later
# slice can bind/edit the OS pool and storage groups, not just data_pools. kind
# is os (singleton) | storage | data; index selects within the array kinds. Pure
# resolvers: state + kind + index in, group JSON / new state out.

# _controller_pool_kind <nav> — the group kind carried by a pooledit nav,
# defaulting to data (so a nav authored before this reference existed still
# resolves).
_controller_pool_kind() {
  local kind; kind="$(navigation_get "$1" kind)"; printf '%s' "${kind:-data}"
}

# _controller_pool_path <kind> — the jq path of a group of that kind, indexed
# by $i for the array kinds.
_controller_pool_path() {
  case "$1" in
  os)      printf '%s\n' '.os_pool' ;;
  storage) printf '%s\n' '.storage_groups[$i]' ;;
  *)       printf '%s\n' '.data_pools[$i]' ;;
  esac
}

# _controller_pool_get <state> <kind> <index> — the group object at (kind,
# index), or {} when absent.
_controller_pool_get() {
  local path
  path="$(_controller_pool_path "$2")"
  # The group, empty when absent.
  printf '%s\n' "$1" | jq -c --argjson i "${3:-0}" "${path} // {}"
}

# _controller_pool_set <state> <kind> <index> <group> — state with the group at
# (kind, index) replaced by <group>.
_controller_pool_set() {
  local path
  path="$(_controller_pool_path "$2")"
  # The state with the group replaced.
  printf '%s\n' "$1" \
    | jq -c --argjson i "${3:-0}" --argjson g "$4" "${path} = \$g"
}

# _controller_pool_delete <state> <kind> <index> — state with the group at
# (kind, index) removed. The OS pool is structural, not removable — a del on os
# is a no-op.
_controller_pool_delete() {
  local path='.'
  [[ "$2" == os ]] || path="del($(_controller_pool_path "$2"))"
  # The state without the group.
  printf '%s\n' "$1" | jq -c --argjson i "${3:-0}" "$path"
}

# ── In-Menu Disk Binding: device-mode, Free Set, bind toggle (ADR 0047) ──────
# On a machine with real disks the pool editor binds actual /dev/disk/by-id/*
# devices (device-mode); off-target it keeps the abstract disk_count cycle
# (count-mode). The mode is decided once at guided launch (guided.sh caches it
# in GUIDED_DEVICE_MODE) and read here; GUIDED_LIVE_SET carries the live-medium
# disks to exclude, so the controller never probes hardware itself.

# _controller_live_set — the newline-separated live-medium whole-disk set to
# exclude from enumeration (empty when unset — no exclusion).
_controller_live_set() { printf '%s' "${GUIDED_LIVE_SET-}"; }

# _controller_detect_device_mode — "1" when any install disk is enumerable, else
# "0". guided.sh calls this once at launch; the pure result drives the cached
# flag.
_controller_detect_device_mode() {
  [[ -n "$(picker_enum_disks "$(_controller_live_set)")" ]] && echo 1 || echo 0
}

# _controller_device_mode — rc 0 when In-Menu Disk Binding is active (the cached
# flag).
_controller_device_mode() { [[ "${GUIDED_DEVICE_MODE:-0}" == "1" ]]; }

# ── Rich chrome version gate (ADR 0047) ──────────────────────────────────────
# The rich chrome (footer + breadcrumb + rounded borders, actions on keys) needs
# fzf ≥ 0.62; a lagging install ISO (ADR 0023) may ship an older fzf, where the
# menu degrades to today's action-rows layout. The mode is decided ONCE at
# guided
# launch (guided.sh caches it in GUIDED_RICH_CHROME) — never a network/pacman
# step, so offline Save/Export authoring is never gated.

# _controller_fzf_rich_for_version <version-string> — rc 0 when the parsed
# "MAJOR.MINOR"
# is ≥ 0.62 (any major > 0 qualifies). Pure: the first token's first two dotted
# fields, base-10 to dodge a leading-zero octal read.
_controller_fzf_rich_for_version() {
  local version major minor _rest
  # The first token's first two dotted fields.
  version="$(first_word "$1")"
  IFS=. read -r major minor _rest < <(printf '%s\n' "$version")
  [[ "$major" =~ ^[0-9]+$ ]] || major=0
  [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  (( 10#$major > 0 || 10#$minor >= 62 ))
}

# _controller_detect_rich_chrome — "1" when the installed fzf supports rich
# chrome, else "0" (also 0 when fzf is absent — legacy is the safe floor).
# guided.sh calls this once at launch; the pure result drives the cached flag.
_controller_detect_rich_chrome() {
  local version; version="$(fzf --version 2>/dev/null)"
  if [[ -n "$version" ]] && _controller_fzf_rich_for_version "$version"; then
    echo 1
  else
    echo 0
  fi
}

# _controller_rich_chrome — rc 0 when the rich chrome is active (the cached
# flag). Unset defaults to legacy, so every non-interactive seam renders action
# rows.
_controller_rich_chrome() { [[ "${GUIDED_RICH_CHROME:-0}" == "1" ]]; }

# _controller_action_row <line...> — emit action rows (Back/Add/remove/create)
# as visible list rows in BOTH chromes (ADR 0063, amends 0047). Rich fzf still
# keeps the ^A/^X/Esc keybindings + footer as accelerators, but the rows render
# too, so every action is discoverable at a glance (a footer-only ^A proved
# invisible — the only way to add a user was an undocumented shortcut). Rich
# chrome otherwise (footer, breadcrumb, borders) is untouched.
_controller_action_row() { printf '%s\n' "$@"; }

# ── rich-chrome footer + breadcrumb (ADR 0047) ───────────────────────────────
# _controller_breadcrumb <nav> — the location breadcrumb for the list
# border-label (`--list-label`): Guided ▸ Category ▸ … . Pure: reads the nav (+
# the pool name from state for the pool screens).
_controller_breadcrumb() {
  local navigation="$1" cat pool; cat="$(navigation_get "$navigation" category)"
  case "$(navigation_screen "$navigation")" in
  top)         printf ' Guided ' ;;
  category)    printf ' Guided ▸ %s ' "$cat" ;;
  values|text) printf ' Guided ▸ %s ▸ %s ' "$cat" \
    "$(navigation_get "$navigation" label)" ;;
  swapedit)    printf ' Guided ▸ %s ▸ swap ' "$cat" ;;
  manualparts) printf ' Guided ▸ %s ▸ partitions ' "$cat" ;;
  partedit)    printf ' Guided ▸ %s ▸ partition ' "$cat" ;;
  datapools)   printf ' Guided ▸ %s ▸ layout ' "$cat" ;;
  rootdisk)    printf ' Guided ▸ %s ▸ root disk ' "$cat" ;;
  pooledit | pooldisks)
    local group
    group="$(_controller_pool_get "$(_controller_live_effective)" \
      "$(_controller_pool_kind "$navigation")" \
      "$(navigation_get "$navigation" index)")"
    # The pool's name, "pool" when unnamed.
    pool="$(printf '%s\n' "$group" | jq -r '.name // .pool_name // "pool"')"
    printf ' Guided ▸ %s ▸ layout ▸ %s ' "$cat" "$pool" ;;
  *) printf ' Guided ' ;;
  esac
}

# _controller_footer_summary <nav> — the live one-line summary for the footer.
# On a pool screen it describes THAT pool ("tank0 · mirror · 2 bound");
# elsewhere it is the whole-layout label. Pure: reads state.
_controller_footer_summary() {
  local navigation="$1" group
  local summary='"\(.name // .pool_name // "pool") · \(.topology // "?") · "'
  summary+=' + (if (.devices // null) != null'
  summary+=' then "\(.devices | length) bound"'
  summary+=' else "\(.disk_count // "?") disks" end)'
  case "$(navigation_screen "$navigation")" in
  pooledit | pooldisks)
    group="$(_controller_pool_get "$(_controller_live_effective)" \
      "$(_controller_pool_kind "$navigation")" \
      "$(navigation_get "$navigation" index)")"
    # "name · topology · bound disks (or the disk count)".
    printf '%s\n' "$group" | jq -r "$summary" ;;
  *)
    # The OS layout label belongs to the Disks context only — printed on every
    # screen's footer it read as a stray "single disk" on Locales/Kernels/etc.
    [[ "$(navigation_get "$navigation" category)" == "Disks" ]] || return 0
    _controller_layout_label \
      "$(_controller_live_effective)" ;;
  esac
}

# _controller_footer <nav> — the rich-chrome footer: this screen's context
# actions and a live summary, separated by a bar. Pure: reads the nav + state.
_controller_footer() {
  local navigation="$1" acts
  case "$(navigation_screen "$navigation")" in
  datapools) acts='^A data pool · ^S storage group · ^X remove · Esc back' ;;
  pooledit)
    case "$(_controller_pool_kind "$navigation")" in
    data)    acts='^X remove pool · Esc back' ;;
    storage) acts='^X remove group · Esc back' ;;
    *)       acts='Esc back' ;;
    esac ;;
  pooldisks) acts='Enter bind/unbind · Esc back' ;;
  rootdisk)  acts='Enter pick · Esc back' ;;
  values)
    case "$(navigation_get "$navigation" field)" in
    sysctl | users) acts='^A add · Esc back' ;;
    *)              acts='Enter choose · Esc back' ;;
    esac ;;
  category)  acts='Enter edit · Esc back' ;;
  pkgbrowse) acts='Enter add/remove · Esc back' ;;
  *)         acts='Esc back' ;;
  esac
  local sum; sum="$(_controller_footer_summary "$navigation")"
  if [[ -n "$sum" ]]; then printf '%s   │   %s' "$acts" "$sum"
  else printf '%s' "$acts"; fi
}
