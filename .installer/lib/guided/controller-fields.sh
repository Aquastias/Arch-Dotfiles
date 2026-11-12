#!/usr/bin/env bash
# =============================================================================
# lib/guided/controller-fields.sh — field model: kinds, cycles, options, apply
# =============================================================================
# Part of the guided controller (lib/guided/controller.sh, ADR 0042).
#
# Used by: lib/guided/controller.sh (sources it).
# =============================================================================

# ── field model ──────────────────────────────────────────────────────────────
# _controller_field_kind <path> → text | enum | multi. text → native query-line
# editor; enum → native value picker; multi → one-shot (slice 03). Everything
# not text/multi is an enum (filesystem, bootloader, firewall, and every bool).
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

_controller_field_kind() {
  case "$1" in
  system.hostname) echo text ;;
  # multi: select several keymaps (element 0 = default)
  system.keymap) echo toggle ;;
  system.timezone) echo biglist ;;
  __language__ | __encoding__) echo biglist ;;   # locale projections (ADR 0076)
  system.console_font) echo biglist ;;           # console font (ADR 0076)
  options.swap_size | options.esp_size | options.age_key_url) echo text ;;
  options.pacman.parallel_downloads) echo text ;;  # numeric value (ADR 0074)
  packages.repo.extra | packages.aur.extra) echo text ;;
  sysctl) echo list ;;   # a list of key=value pairs + an Add action
  options.mirror_servers) echo list ;;        # custom Server= URLs (0072)
  options.custom_repositories) echo list ;;   # archinstall-style repos (0072)
  options.kernel | environment.desktop | environment.gpu) echo toggle ;;
  options.fonts) echo toggle ;;   # Font Catalog multi-select (ADR 0080)
  options.mirror_countries | host_programs \
    | options.optional_repos) echo toggle ;;
  users) echo users ;;   # toggle existing users + in-fzf create
  *) echo enum ;;
  esac
}

# _controller_is_cycle_field <path> → rc 0 when <path> is a Cycle Field: an enum
# leaf whose value set is {true,false}, so Enter flips it in place instead of
# drilling into the values submenu (ADR 0075). Structural — any bare bool
# qualifies.
_controller_is_cycle_field() {
  # The editor-backed bools (encryption, impermanence) are ▸ rows with their own
  # screens — bare-bool by shape but NOT Cycle Fields; exclude them so they are
  # never labelled one.
  case "$1" in
  options.encryption | options.impermanence.enabled) return 1 ;;
  esac
  [[ "$(_controller_field_kind "$1")" == enum ]] || return 1
  [[ "$(_controller_enum_options "$1")" == $'true\nfalse' ]]
}

# _controller_built_root_filesystems — the root filesystems whose Root Layout
# Adapter is BUILT, one per line (issue 09). Kept in lockstep with
# lib/layout/dispatch.sh's root_adapter_source (the dispatch is the source of
# truth for what's built); the guided layer lists a value only when the operator
# can actually install it.
_controller_built_root_filesystems() { printf '%s\n' zfs btrfs ext4 xfs; }

# _controller_topologies_for_filesystem <fs> → the ordered topology cycle for a
# group of that filesystem (issue 09), matching the validation contract in
# lib/config/validation.sh::_validation_topology_for_filesystem. zfs keeps
# mirror/raidz/stripe; btrfs offers native raid; ext4/xfs are single-disk only.
# The order is the cycle order — the zfs list ends in `stripe` so the historical
# stripe→mirror wrap is preserved.
_controller_topologies_for_filesystem() {
  case "$1" in
  btrfs)      printf '%s\n' single raid0 raid1 raid10 ;;
  ext4 | xfs) printf '%s\n' single ;;
  *)          printf '%s\n' mirror raidz1 raidz2 stripe ;;
  esac
}

# _controller_cycle_next <current> <item...> → the item after <current>
# (wrapping); the first item when <current> is absent. The shared cycle
# primitive behind the pool editor's topology and filesystem rows.
_controller_cycle_next() {
  local current="$1"; shift; local -a list=("$@"); local i
  for i in "${!list[@]}"; do
    [[ "${list[$i]}" == "$current" ]] \
      && { printf '%s\n' "${list[$(( (i + 1) % ${#list[@]} ))]}"; return 0; }
  done
  printf '%s\n' "${list[0]}"
}

# _controller_cycle_topology <fs> <current> → the next topology in <fs>'s cycle
# after <current>, wrapping; the first entry when <current> is not in the set
# (e.g. after the group's filesystem changed and left a stale topology).
_controller_cycle_topology() {
  # deliberately word-split the topology list to args
  # shellcheck disable=SC2046
  _controller_cycle_next "$2" $(_controller_topologies_for_filesystem "$1")
}

# _controller_pool_normalise_filesystem <state> <index> <fs> → state with
# data_pools[index]'s filesystem set to <fs> and the group made consistent for
# it (issue 09, ADR 0043): ext4/xfs are single-disk (topology single, disk_count
# 1); otherwise a topology no longer valid for <fs> resets to that fs's first (a
# still-valid one is kept). Keeps the editor from authoring a group validation
# would reject.
_controller_pool_normalise_filesystem() {
  local state="$1" i="$2" filesystem="$3" pool topology first valid=0
  local -a topologies=()
  mapfile -t topologies < <(_controller_topologies_for_filesystem "$filesystem")
  first="${topologies[0]:-}"
  pool="$(_controller_pool_get "$state" data "$i")"
  # The pool's topology, empty when unset.
  topology="$(printf '%s\n' "$pool" | jq -r '.topology // ""')"
  pool="$(edit_set_scalar "$pool" filesystem "$filesystem")"
  if [[ "$filesystem" == ext4 || "$filesystem" == xfs ]]; then
    pool="$(edit_set_scalar "$pool" topology single)"
    pool="$(config_state_set "$pool" disk_count 1)"
    # Only the first bound device stays.
    config_state_is_overridden "$pool" devices \
      && pool="$(printf '%s\n' "$pool" | jq '.devices |= .[0:1]')"
  else
    local each
    for each in "${topologies[@]}"; do
      [[ "$each" == "$topology" ]] && valid=1
    done
    ((valid)) || pool="$(edit_set_scalar "$pool" topology "$first")"
  fi
  _controller_pool_set "$state" data "$i" "$pool"
}

# _controller_enum_options <path> → the value-picker lines for an enum field (or
# the synthetic __layout__ disk-layout preset list).
_controller_enum_options() {
  case "$1" in
  __layout__)
    printf '%s\n' single os-mirror os-mirror-raidz1 data-pools "custom…" ;;
  filesystem) _controller_built_root_filesystems ;;
  options.bootloader | post_install.security.firewall \
    | environment.display_manager | disk_config.kind \
    | options.power.profile) menu_enum_options "$1" ;;
  *) printf '%s\n' true false ;;
  esac
}

# _controller_manual_locked <state> <path> → 0 (locked) when Manual Partitioning
# is on and <path> is one of the pool-dependent Disks fields it disables (ADR
# 0073). The one guard both apply paths call, so a locked field can never be
# edited.
_controller_manual_locked() {
  [[ "$(config_state_get "$1" disk_config.kind)" == "manual" ]] \
    && menu_manual_locked_paths | grep -qxF "$2"
}

# _controller_zfs_locked <state> <path> → 0 (locked) when <path> is a
# no-ZFS-locked field (zfs snapshots) and the effective state puts no ZFS
# anywhere.
_controller_zfs_locked() {
  menu_zfs_locked_paths | grep -qxF "$2" \
    && ! menu_state_any_zfs \
    "$(_controller_effective "$1" "$(_controller_baseline)")"
}

# _controller_big_list_options <path> → the big, filterable option set for a
# system identity field, from the live system (localectl/timedatectl) with a
# filesystem fallback (the install host is the Arch live ISO; the fallback also
# covers a dev box where the systemd commands return nothing).
_controller_big_list_options() {
  local out
  case "$1" in
  system.keymap)
    out="$(locale_source_keymaps)" ;;
  system.timezone)
    out="$(timedatectl list-timezones 2>/dev/null)"
    # The zone names under the zoneinfo tree, region-qualified, sorted.
    [[ -n "$out" ]] || out="$(find /usr/share/zoneinfo -type f -printf '%P\n' \
      2>/dev/null | grep -E '^[A-Z][A-Za-z_]+/' | sort)" ;;
  __language__)
    out="$(locale_source_languages)" ;;
  __encoding__)
    # only the encodings valid for the currently-chosen language (ADR 0076).
    out="$(locale_source_encodings \
      "$(locale_parts_language "$(_controller_locale_current)")")" ;;
  system.console_font)
    out="$(locale_source_console_fonts)" ;;
  esac
  [[ -n "$out" ]] && printf '%s\n' "$out"
}

# _controller_locale_current → the effective default locale (system.locale
# element 0), en_US.UTF-8 when unset. The basis the language/encoding
# projections read.
_controller_locale_current() {
  local loc locale
  local first='if type == "array" then .[0] // "" else . // "" end'
  locale="$(config_state_get_json "$(_controller_live_effective)" \
    system.locale)"
  # The first locale of a list, or the lone one.
  loc="$(printf '%s\n' "$locale" | jq -r "$first")"
  [[ -n "$loc" ]] || loc="en_US.UTF-8"
  printf '%s\n' "$loc"
}

# _controller_apply_locale_part <state> <__language__|__encoding__> <value> →
# new state with system.locale recomposed from the edited part (ADR 0076). Reads
# the effective locale, swaps the one part, recomposes exactly once, and
# preserves a multi-locale array's tail (only element 0 — the default — is
# edited).
_controller_apply_locale_part() {
  local state="$1" which="$2" value="$3" current lang encoding newloc locjson
  current="$(_controller_locale_current)"
  lang="$(locale_parts_language "$current")"; \
    encoding="$(locale_parts_encoding "$current")"
  case "$which" in
  __language__) lang="$value" ;;
  __encoding__) encoding="$value" ;;
  esac
  newloc="$(locale_parts_compose "$lang" "$encoding")"
  local locales
  local replaced='if type == "array" and length > 1'
  replaced+=' then [$n] + .[1:] else $n end'
  locales="$(config_state_get_json \
    "$(_controller_effective "$state" "$(_controller_baseline)")" \
    system.locale)"
  # The new locale in place of the first, a list's tail kept.
  locjson="$(printf '%s\n' "$locales" | jq -c --arg n "$newloc" "$replaced")"
  config_state_set "$state" system.locale "$locjson"
}

# _controller_apply_enum <state> <path> <value> → new state. Reserved
# filesystems are a no-op (rc 1, unchanged). Bools route to edit_set_bool; the
# rest are scalars.
_controller_apply_enum() {
  local state="$1" path="$2" value="$3"
  # Manual Partitioning locks the pool-dependent Disks fields (ADR 0073): a
  # locked field is a no-op (rc 1, unchanged).
  _controller_manual_locked "$state" "$path" \
    && { printf '%s' "$state"; return 1; }
  # No ZFS on the install: zfs snapshots is locked the same way (ADR 0041).
  _controller_zfs_locked "$state" "$path" && { printf '%s' "$state"; return 1; }
  case "$path" in
  disk_config.kind)
    case "$value" in auto | manual) ;; *) printf '%s' "$state"; return 1 ;; esac
    edit_set_scalar "$state" disk_config.kind "$value" ;;
  filesystem)
    # Commit only a BUILT root filesystem (issue 09); an unbuilt/unknown value
    # is a no-op (rc 1, unchanged) so the picker can never author an
    # uninstallable fs.
    _controller_built_root_filesystems | grep -qxF "$value" \
      || { printf '%s' "$state"; return 1; }
    edit_set_scalar "$state" filesystem "$value" ;;
  options.bootloader | post_install.security.firewall \
    | environment.display_manager)
    edit_set_scalar "$state" "$path" "$value" ;;
  options.power.profile)
    # Power Profile enum (ADR 0080): a 3-value scalar, NOT a bool — commit only
    # a known backend so the picker can never author an invalid daemon; an
    # unknown value is a no-op (rc 1, unchanged).
    case "$value" in
    none | power-profiles-daemon | tuned) ;;
    *) printf '%s' "$state"; return 1 ;;
    esac
    edit_set_scalar "$state" options.power.profile "$value" ;;
  *) edit_set_bool "$state" "$path" "$value" ;;
  esac
}

# _controller_apply_text <state> <path> <value> → new state for a free-text
# field. sysctl parses key=value; the extra-packages row appends; rest are
# scalars.
_controller_apply_text() {
  local state="$1" path="$2" value="$3"
  # Manual Partitioning locks the pool-dependent Disks fields (ADR 0073), incl.
  # the free-text esp size: a locked field is a no-op (rc 1, unchanged).
  _controller_manual_locked "$state" "$path" \
    && { printf '%s' "$state"; return 1; }
  case "$path" in
  __persist__)    edit_append_persist "$state" "$value" ;;
  __newuser__)
    # create: add the typed name to the user list (dedup); a default profile is
    # materialized at Proceed/Save for any name without a committed profile.
    [[ -n "$value" ]] || { printf '%s' "$state"; return 1; }
    local current
    # The effective user names.
    current="$(_controller_effective "$state" "$(_controller_baseline)" \
      | jq -c '.users // []')"
    # The user names, the typed one added unless listed.
    config_state_set "$state" users \
      "$(_controller_json_with "$current" "$value")" ;;
  # sysctl / custom mirror Server / custom repository — the routing-heavy adds
  # share one implementation with the replay helpers via edit.sh (ADR 0072).
  sysctl)                      edit_add_sysctl_pair "$state" "$value" ;;
  options.mirror_servers)      edit_add_mirror_server "$state" "$value" ;;
  options.custom_repositories) edit_add_custom_repository "$state" "$value" ;;
  packages.repo.extra) _controller_route_package_entry "$state" "$value" repo ;;
  packages.aur.extra)  _controller_route_package_entry "$state" "$value" aur ;;
  *) edit_set_scalar "$state" "$path" "$value" ;;
  esac
}

# _controller_route_package_entry <state> <raw> [slot] — the ＋Add guard (ADR
# 0086). It splits the space-separated typed entry and routes each name VISIBLY,
# never by silent reclassification:
#   • a [[Menu-Owned Program]] (grub, clamav, …) → informed ("managed by its
#     control"), NOT added — the control is its sole home;
#   • a free-standing user Program → the Primary User's programs;
#   • a free-standing host Program → host_programs (defensive: none today);
#   • anything else (a raw package name) → packages.<slot>.extra.
# A Program name therefore never reaches packages.* (config-load exclusivity
# stays satisfiable), and every reclassification is announced on stderr (the
# controller's out-of-band channel) so the operator learns where the name went.
_controller_route_package_entry() {
  local state="$1" raw="$2" slot="${3:-repo}"
  [[ -n "$raw" ]] || { printf '%s' "$state"; return 1; }

  local -a packages=() usr=() host=() owned=()
  local name
  for name in $raw; do
    if menu_owned_programs | grep -qxF -- "$name"; then owned+=("$name")
    else
      case "$(program_registry_kind "$name")" in
      user) usr+=("$name") ;;
      host) host+=("$name") ;;
      *)    packages+=("$name") ;;
      esac
    fi
  done

  ((${#packages[@]})) \
    && state="$(edit_append_packages "$state" "${packages[*]}" "$slot")"
  if ((${#host[@]})); then
    state="$(edit_append_host_programs "$state" "${host[@]}")"
    printf 'routed to host programs: %s\n' "${host[*]}" >&2
  fi
  if ((${#usr[@]})); then
    local primary
    primary="$(_controller_primary_user "$state")"
    if [[ -n "$primary" ]]; then
      state="$(_controller_append_primary_user_programs "$state" "${usr[@]}")"
      printf 'routed to Users → %s: %s\n' "$primary" "${usr[*]}" >&2
    else
      printf '“%s” is a user program — add a user first (not added).\n' \
        "${usr[*]}" >&2
    fi
  fi
  for name in "${owned[@]}"; do
    printf '“%s” is managed by %s — set it there (not added).\n' \
      "$name" "$(menu_owned_control "$name")" >&2
  done
  printf '%s' "$state"
}

# _controller_append_primary_user_programs <state> <name...> — dedup-append user
# Program name(s) to the Primary User's (users[0]) programs override. With no
# users declared there is nowhere host-independent to put them, so they fall
# back to being plain repo packages rather than being silently dropped.
_controller_append_primary_user_programs() {
  local state="$1"; shift
  local primary
  primary="$(_controller_primary_user "$state")"
  if [[ -z "$primary" || -z "${GUIDED_USERFORMS_FILE:-}" ]]; then
    edit_append_packages "$state" "$*"
    return 0
  fi
  local programs='[]' name
  local -a names=()
  # The primary user's programs override, one per line.
  mapfile -t names < <(guided_userform_get "$GUIDED_USERFORMS_FILE" \
    "$primary" | jq -r '(.programs // [])[]')
  # Those, then the new names, each kept once in first-seen order.
  for name in "${names[@]}" "$@"; do
    programs="$(_controller_json_with "$programs" "$name")"
  done
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$primary" programs "$programs"
  printf '%s' "$state"
}

# _controller_primary_user <state> — the Primary User (users[0] of the
# effective view), empty when there are no users.
_controller_primary_user() {
  # The first user name.
  _controller_effective "$1" "$(_controller_baseline)" \
    | jq -r '.users[0] // empty'
}

# _controller_normalise_default <state> <path> → <state> with the override at
# <path> dropped when it renders identically to the seeded default (the "strict
# delta" contract: landing back on the default leaves NO override, so ● never
# lights for an unchanged value). Rendered compare (menu_render_value) survives
# scalar/array shape gaps (keymap "us" vs ["us"], gpu "auto"). Pure.
_controller_normalise_default() {
  local state="$1" path="$2"
  config_state_is_overridden "$state" "$path" || { printf '%s' "$state"; return 0; }
  local override_value default_value
  override_value="$(menu_render_value "$state" "$path")"
  default_value="$(menu_render_value "$(_controller_baseline)" "$path")"
  if [[ "$override_value" == "$default_value" ]]; then
    config_state_unset "$state" "$path"
  else
    printf '%s' "$state"
  fi
}

# _controller_curated_persist_count — the number of Curated Persist Defaults
# always persisted under impermanence (files + dirs, ADR 0066), for the
# Impermanence Editor's read-only summary line. Reads the single-source arrays
# sourced from impermanence-common.sh at load.
_controller_curated_persist_count() {
  printf '%s' "$(( ${#CURATED_FILES[@]} + ${#CURATED_DIRS[@]} ))"
}

# _controller_host_program_names / _controller_user_program_names — the option
# set for each program picker, filtered on the registry's kind (R22): the host
# row needs kind host, the User Editor's row needs kind user. [[Menu-Owned
# Program]]s are filtered from BOTH (ADR 0086): a program a dedicated control
# governs has that control as its sole home. Unconditional base host programs
# (ADR 0089) install via the Fleet Layer's host_programs, never picker-chosen
# either — the host row itself was dropped (ADR 0086), so
# _controller_host_program_names is not reached.
_controller_host_program_names() {
  program_registry_names_of_kind host | _controller_without_menu_owned
}
_controller_user_program_names() {
  program_registry_names_of_kind user | _controller_without_menu_owned
}

# _controller_toggle_options <field> → the raw option lines for a toggle (multi)
# field.
_controller_toggle_options() {
  case "$1" in
  options.kernel | environment.desktop | environment.gpu \
    | options.mirror_countries | options.optional_repos | options.fonts)
    menu_enum_options "$1" ;;
  host_programs)     _controller_host_program_names ;;
  system.keymap)       _controller_big_list_options system.keymap ;;
  esac
}

# _controller_field_has_preview <field> → rc 0 if this values screen shows a
# side panel (the layout graph, the selection panel for the big
# keymap/locale/timezone, or the per-user detail panel on the Users screen — ADR
# 0063).
_controller_field_has_preview() {
  case "$1" in
  __layout__ | system.keymap | system.timezone | users \
    | __language__ | __encoding__ | system.console_font)
    return 0 ;;
  *) return 1 ;;
  esac
}

# _controller_marked_options <field> <state> <base> — each option prefixed [x]/[
# ] by whether it is currently selected (gpu's scalar "auto" counts as an
# array).
_controller_marked_options() {
  local field="$1" state="$2" base="$3" option value
  local -A selected=()
  # The field's selected values, one per line (a lone value counts as one).
  while IFS= read -r value; do
    [[ -n "$value" ]] && selected["$value"]=1
  done < <(_controller_selected_values "$field" \
    "$(_controller_effective "$state" "$base")" | jq -r '.[]')
  while IFS= read -r option; do
    if [[ -n "$option" && -n "${selected["$option"]:-}" ]]; then
      printf '[x] %s\n' "$option"
    else
      printf '[ ] %s\n' "$option"
    fi
  done < <(_controller_toggle_options "$field")
}

# _controller_toggle_multi <state> <base> <field> <value> → flip <value>'s
# membership in the field's array (computed against the EFFECTIVE value so a
# seeded baseline is honoured), written back as an override; an empty result
# unsets the override. gpu is mutually-exclusive with "auto" and normalizes to
# scalar "auto" / a vendor array / unset.
_controller_toggle_multi() {
  local state="$1" base="$2" field="$3" value="$4" effective current new
  effective="$(_controller_effective "$state" "$base")"
  current="$(_controller_selected_values "$field" "$effective")"
  if [[ "$field" == "environment.gpu" ]]; then
    if [[ "$value" == auto ]]; then
      new='["auto"]'
      _controller_json_has "$current" auto && new='[]'
    else
      # The vendors without "auto", the value flipped in or out.
      current="$(printf '%s\n' "$current" | jq -c '. - ["auto"]')"
      new="$(_controller_json_toggled "$current" "$value")"
    fi
    case "$new" in
    '["auto"]') config_state_set   "$state" environment.gpu '"auto"' ;;
    '[]')       config_state_unset "$state" environment.gpu ;;
    *)          config_state_set   "$state" environment.gpu "$new" ;;
    esac
    return
  fi
  new="$(_controller_json_toggled "$current" "$value")"
  if [[ "$new" == '[]' ]]; then
    config_state_unset "$state" "$field"
  else
    config_state_set "$state" "$field" "$new"
  fi
}
