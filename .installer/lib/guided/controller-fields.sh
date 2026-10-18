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
  local state="$1" i="$2" filesystem="$3" valid first
  valid="$(_controller_topologies_for_filesystem "$filesystem" \
    | awk '{ printf "%s ", $0 }')"
  first="$(_controller_topologies_for_filesystem "$filesystem" \
    | awk 'NR == 1 { print; exit }')"
  jq --argjson i "$i" --arg fs "$filesystem" --arg valid "$valid" \
    --arg first "$first" '
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
  local loc
  loc="$(jq -r '(.system.locale) as $l
    | if ($l | type) == "array" then ($l[0] // "") else ($l // "") end' \
    <<<"$(_controller_live_effective)")"
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
  locjson="$(jq -c --arg n "$newloc" '
    (.system.locale) as $l
    | if ($l | type) == "array" and ($l | length) > 1 then ([$n] + $l[1:])
      else $n end' \
      <<<"$(_controller_effective "$state" "$(_controller_baseline)")")"
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
    # is
    # a no-op (rc 1, unchanged) so the picker can never author an uninstallable
    # fs.
    _controller_built_root_filesystems | grep -qxF "$value" \
      || { printf '%s' "$state"; return 1; }
    edit_set_scalar "$state" filesystem "$value" ;;
  options.bootloader | post_install.security.firewall \
    | environment.display_manager)
    edit_set_scalar "$state" "$path" "$value" ;;
  options.power.profile)
    # Power Profile enum (ADR 0080): a 3-value scalar, NOT a bool — commit only
    # a
    # known backend so the picker can never author an invalid daemon; an unknown
    # value is a no-op (rc 1, unchanged).
    case "$value" in none | power-profiles-daemon | tuned) ;;
      *) printf '%s' "$state"; return 1 ;; esac
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
    local current; current="$(jq -c '.users // []' \
      <<<"$(_controller_effective "$state" "$(_controller_baseline)")")"
    config_state_set "$state" users "$(jq -cn --argjson a "$current" \
      --arg v "$value" \
      'if any($a[]; . == $v) then $a else ($a + [$v]) end')" ;;
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
    primary="$(jq -r '.users[0] // empty' \
      <<<"$(_controller_effective "$state" "$(_controller_baseline)")")"
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
  primary="$(jq -r '.users[0] // empty' \
    <<<"$(_controller_effective "$state" "$(_controller_baseline)")")"
  if [[ -z "$primary" || -z "${GUIDED_USERFORMS_FILE:-}" ]]; then
    edit_append_packages "$state" "$*"
    return 0
  fi
  local current add
  current="$(guided_userform_get "$GUIDED_USERFORMS_FILE" "$primary" \
    | jq -c '.programs // []')"
  add="$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$primary" programs \
    "$(jq -cn --argjson a "$current" --argjson b "$add" \
      'reduce ($a + $b)[] as $x ([];
         if any(.[]; . == $x) then . else . + [$x] end)')"
  printf '%s' "$state"
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
# _controller_host_program_names is not reached. (`|| :` keeps an empty result a
# success, not grep's rc 1.)
_controller_host_program_names() {
  program_registry_names_of_kind host | grep -vxF -f <(menu_owned_programs) || :
}
_controller_user_program_names() {
  program_registry_names_of_kind user | grep -vxF -f <(menu_owned_programs) || :
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
  local field="$1" state="$2" base="$3" sel option
  sel="$(jq -c --arg p "$field" \
    'getpath($p | split(".")) // [] | if type == "array" then . else [.] end' \
    <<<"$(_controller_effective "$state" "$base")")"
  while IFS= read -r option; do
    # jq -n (null input) so it does NOT consume the loop's stdin (the option
    # list)
    if jq -ne --argjson s "$sel" --arg o "$option" 'any($s[]; . == $o)' \
        >/dev/null 2>&1; then
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
  if [[ "$field" == "environment.gpu" ]]; then
    current="$(jq -c '.environment.gpu // []
      | if type == "array" then . else [.] end' \
      <<<"$effective")"
    new="$(jq -cn --argjson a "$current" --arg v "$value" '
      if $v == "auto"
        then (if any($a[]; . == "auto") then [] else ["auto"] end)
        else (($a - ["auto"]) as $c
              | if any($c[]; . == $v) then ($c - [$v]) else ($c + [$v]) end)
      end')"
    case "$new" in
    '["auto"]') config_state_set   "$state" environment.gpu '"auto"' ;;
    '[]')       config_state_unset "$state" environment.gpu ;;
    *)          config_state_set   "$state" environment.gpu "$new" ;;
    esac
    return
  fi
  current="$(jq -c --arg p "$field" \
    'getpath($p | split(".")) // [] | if type == "array" then . else [.] end' \
    <<<"$effective")"
  new="$(jq -cn --argjson a "$current" --arg v "$value" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  if [[ "$new" == '[]' ]]; then
    config_state_unset "$state" "$field"
  else
    config_state_set "$state" "$field" "$new"
  fi
}
