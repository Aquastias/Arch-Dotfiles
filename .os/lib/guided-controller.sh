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

# INSTALL_DEFAULT_ENC_PASSPHRASE (ADR 0059) — the 8-char passphrase default.
# shellcheck source=lib/globals.sh
[[ -n "${INSTALL_DEFAULT_ENC_PASSPHRASE:-}" ]] \
  || source "${BASH_SOURCE[0]%/*}/globals.sh"
# shellcheck source=lib/config/state.sh
declare -F cfgstate_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/state.sh"
# shellcheck source=lib/config/nav.sh
declare -F nav_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/nav.sh"
# shellcheck source=lib/config/edits.sh
declare -F edit_set_bool >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/edits.sh"
# shellcheck source=lib/config/menu.sh
declare -F menu_categories >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/menu.sh"
# shellcheck source=lib/guided-rows.sh
declare -F guided_row_inert >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/guided-rows.sh"

declare -F esp_budget_fits_size >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/boot/esp-budget.sh"
# shellcheck source=lib/config/manual-partition.sh
declare -F manual_kind_active >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/manual-partition.sh"
# shellcheck source=lib/config/skeleton.sh
declare -F skeleton_preset >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/skeleton.sh"
# shellcheck source=lib/picker.sh
declare -F picker_enum_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/picker.sh"
# shellcheck source=lib/config/history.sh
declare -F hist_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/history.sh"
# shellcheck source=lib/config/display.sh
declare -F display_label >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/display.sh"
# shellcheck source=lib/guided-secrets-file.sh
declare -F guided_secretsfile_has_root >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/guided-secrets-file.sh"
# shellcheck source=lib/config/profile.sh
declare -F load_user_profile >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/profile.sh"
# shellcheck source=lib/config/printing.sh
declare -F printing_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/printing.sh"
# shellcheck source=lib/config/bluetooth.sh
declare -F bluetooth_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/bluetooth.sh"
# shellcheck source=lib/config/power.sh
declare -F power_owned_programs >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/power.sh"
# shellcheck source=lib/config/profiles.sh
declare -F profiles_list >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/profiles.sh"
# shellcheck source=lib/config/layers.sh
declare -F _configs_parse >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/layers.sh"
# shellcheck source=lib/guided-userforms.sh
declare -F guided_userform_get >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/guided-userforms.sh"
# Curated Persist Defaults, for the Impermanence Editor's read-only count line
# (ADR 0066).
# shellcheck source=lib/impermanence-common.sh
[[ -n "${CURATED_FILES:-}" ]] \
  || source "${BASH_SOURCE[0]%/*}/impermanence-common.sh"
# shellcheck source=lib/guided-mask.sh
declare -F guided_mask_apply >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/guided-mask.sh"
# shellcheck source=lib/packages/resolver.sh
declare -F pkgres_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/packages/resolver.sh"
# shellcheck source=lib/config/seed.sh
declare -F cfgstate_host_core >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/seed.sh"
# shellcheck source=lib/config/layer-resolver.sh
declare -F layer_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config/layer-resolver.sh"

# _ctl_secret_state <root|user|enc> [name] → "(set)" / "(not set)" for the
# in-menu credential rows, read from GUIDED_SECRETS_FILE. Never emits the value.
# With no secrets file wired (non-persistent), everything reads "(not set)".
_ctl_secret_state() {
  local f="${GUIDED_SECRETS_FILE:-}"
  if [[ -n "$f" ]]; then
    case "$1" in
    root) guided_secretsfile_has_root "$f" && { echo "(set)"; return; } ;;
    enc)  guided_secretsfile_has_enc  "$f" && { echo "(set)"; return; } ;;
    *)    guided_secretsfile_has_user "$f" "$2" && { echo "(set)"; return; } ;;
    esac
  fi
  echo "(not set)"
}

# _ctl_secret_tag <root|user|enc> [name] → the ADR-0055 source tag for a
# credential: `custom` (operator typed it into GUIDED_SECRETS_FILE), else
# `from age` (a committed secret will decrypt via the wired age key — .secrets.*
# wins over .guided_passwords.* in the resolver), else the default tag. The
# default is role-dependent (ADR 0059): the disk passphrase reports its 8-char
# default, accounts their 5-char one. Never emits the value. Reads the secrets
# file + effective state.
_ctl_secret_tag() {
  local f="${GUIDED_SECRETS_FILE:-}" role="$1" name="${2:-}"
  if [[ -n "$f" ]]; then
    case "$role" in
    root) guided_secretsfile_has_root "$f" && { echo "custom"; return; } ;;
    enc)  guided_secretsfile_has_enc  "$f" && { echo "custom"; return; } ;;
    *)    guided_secretsfile_has_user "$f" "$name" && { echo "custom"; return; } ;;
    esac
  fi
  [[ -n "$(cfgstate_get "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
      options.age_key_url)" ]] && { echo "from age"; return; }
  if [[ "$role" == "enc" ]]; then echo "default $INSTALL_DEFAULT_ENC_PASSPHRASE"
  else echo "default 12345"; fi
}

# _ctl_pw_missing — count of required-but-unset passwords (root + each enabled
# user), from GUIDED_SECRETS_FILE over the effective user list. 0 when no secrets
# file is wired (non-persistent contexts), so the top screen stays undecorated.
_ctl_pw_missing() {
  local f="${GUIDED_SECRETS_FILE:-}"
  [[ -n "$f" ]] || { printf '0'; return; }
  local users
  users="$(jq -c '.users // []' \
    <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")"
  guided_secretsfile_missing "$f" "$users" | grep -c .
}

# _ctl_enc_missing — rc 0 when the encryption passphrase is required but unset
# (ADR 0054): encryption is on AND no passphrase captured. Inert (rc 1) when no
# secrets file is wired or encryption is off — so toggling encryption off drops
# the requirement even though a stored passphrase is retained.
_ctl_enc_missing() {
  local f="${GUIDED_SECRETS_FILE:-}"
  [[ -n "$f" ]] || return 1
  [[ "$(cfgstate_get "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" \
    options.encryption)" == "true" ]] || return 1
  guided_secretsfile_has_enc "$f" && return 1
  return 0
}

# _ctl_display_values <field> → 0 when <field>'s enum/toggle VALUES are human
# words that should render through the Display Label formatter (desktop, gpu,
# kernel, filesystem, bootloader, firewall). Every other field's values are
# technical (keymap codes, mirror countries, program names), free-text, or
# booleans and are shown verbatim. Labels are always formatted; only VALUES are
# gated by this allowlist.
_ctl_display_values() {
  case "$1" in
  environment.desktop | environment.gpu | environment.display_manager \
    | options.kernel | filesystem \
    | options.bootloader | post_install.security.firewall) return 0 ;;
  *) return 1 ;;
  esac
}

# _ctl_display_value_str <field> <value-string> → the value formatted for
# display when <field> is value-formattable, else verbatim. Multi-value fields
# render as ", "-joined tokens (menu_render_value), so each token is formatted
# and re-joined; single values are one token.
_ctl_display_value_str() {
  local field="$1" val="$2"
  { _ctl_display_values "$field" && [[ -n "$val" ]]; } \
    || { printf '%s' "$val"; return; }
  local out="" part
  while [[ "$val" == *", "* ]]; do
    part="${val%%, *}"; val="${val#*, }"
    out+="${out:+, }$(display_label "$part")"
  done
  printf '%s' "${out:+$out, }$(display_label "$val")"
}

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

# _ctl_is_cycle_field <path> → rc 0 when <path> is a Cycle Field: an enum leaf
# whose whole value set is {true,false}, so Enter flips it in place on the
# category screen instead of drilling into the values submenu (ADR 0075).
# Structural (not a path list) — any bare bool qualifies with nothing to keep in
# sync; the editor-backed bools (encryption, impermanence) are ▸ rows that never
# reach this, and the other enums (filesystem, bootloader, …) carry real option
# lists, so only the bare bools match.
_ctl_is_cycle_field() {
  # The two editor-backed bools are ▸ rows with their own screens (Encryption /
  # Impermanence editors) — bare-bool by shape but NOT Cycle Fields (Q8); the
  # dispatch never routes them here, but the detail pane resolves them directly,
  # so exclude them so they are never labelled a Cycle Field.
  case "$1" in
  options.encryption | options.impermanence.enabled) return 1 ;;
  esac
  [[ "$(_ctl_field_kind "$1")" == enum ]] || return 1
  [[ "$(_ctl_enum_options "$1")" == $'true\nfalse' ]]
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
  __layout__) printf '%s\n' single os-mirror os-mirror-raidz1 data-pools "custom…" ;;
  filesystem) _ctl_built_root_filesystems ;;
  options.bootloader | post_install.security.firewall \
    | environment.display_manager | disk_config.kind \
    | options.power.profile) menu_enum_options "$1" ;;
  *) printf '%s\n' true false ;;
  esac
}

# _ctl_manual_locked <state> <path> → 0 (locked) when Manual Partitioning is on
# and <path> is one of the pool-dependent Disks fields it disables (ADR 0073).
# The one guard both apply paths call, so a locked field can never be edited.
_ctl_manual_locked() {
  [[ "$(cfgstate_get "$1" disk_config.kind)" == "manual" ]] \
    && menu_manual_locked_paths | grep -qxF "$2"
}

# _ctl_biglist_options <path> → the big, filterable option set for a system
# identity field, from the live system (localectl/timedatectl) with a filesystem
# fallback (the install host is the Arch live ISO; the fallback also covers a dev
# box where the systemd commands return nothing).
_ctl_biglist_options() {
  local out
  case "$1" in
  system.keymap)
    out="$(locale_list_keymaps)" ;;
  system.timezone)
    out="$(timedatectl list-timezones 2>/dev/null)"
    [[ -n "$out" ]] || out="$(find /usr/share/zoneinfo -type f -printf '%P\n' \
      2>/dev/null | grep -E '^[A-Z][A-Za-z_]+/' | sort)" ;;
  __language__)
    out="$(locale_list_languages)" ;;
  __encoding__)
    # only the encodings valid for the currently-chosen language (ADR 0076).
    out="$(locale_list_encodings "$(locale_language "$(_ctl_locale_current)")")" ;;
  system.console_font)
    out="$(locale_list_console_fonts)" ;;
  esac
  [[ -n "$out" ]] && printf '%s\n' "$out"
}

# _ctl_locale_current → the effective default locale (system.locale element 0),
# en_US.UTF-8 when unset. The basis the language/encoding projections read.
_ctl_locale_current() {
  local loc
  loc="$(jq -r '(.system.locale) as $l
    | if ($l | type) == "array" then ($l[0] // "") else ($l // "") end' \
    <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")"
  [[ -n "$loc" ]] || loc="en_US.UTF-8"
  printf '%s\n' "$loc"
}

# _ctl_apply_locale_part <state> <__language__|__encoding__> <value> → new state
# with system.locale recomposed from the edited part (ADR 0076). Reads the
# effective locale, swaps the one part, recomposes exactly once, and preserves a
# multi-locale array's tail (only element 0 — the default — is edited).
_ctl_apply_locale_part() {
  local state="$1" which="$2" val="$3" cur lang enc newloc locjson
  cur="$(_ctl_locale_current)"
  lang="$(locale_language "$cur")"; enc="$(locale_encoding "$cur")"
  case "$which" in
  __language__) lang="$val" ;;
  __encoding__) enc="$val" ;;
  esac
  newloc="$(locale_compose "$lang" "$enc")"
  locjson="$(jq -c --arg n "$newloc" '
    (.system.locale) as $l
    | if ($l | type) == "array" and ($l | length) > 1 then ([$n] + $l[1:])
      else $n end' <<<"$(_ctl_effective "$state" "$(_ctl_baseline)")")"
  cfgstate_set "$state" system.locale "$locjson"
}

# _ctl_apply_enum <state> <path> <value> → new state. Reserved filesystems are a
# no-op (rc 1, unchanged). Bools route to edit_set_bool; the rest are scalars.
_ctl_apply_enum() {
  local state="$1" path="$2" val="$3"
  # Manual Partitioning locks the pool-dependent Disks fields (ADR 0073): a
  # locked field is a no-op (rc 1, unchanged).
  _ctl_manual_locked "$state" "$path" && { printf '%s' "$state"; return 1; }
  case "$path" in
  disk_config.kind)
    case "$val" in auto | manual) ;; *) printf '%s' "$state"; return 1 ;; esac
    edit_set_scalar "$state" disk_config.kind "$val" ;;
  filesystem)
    # Commit only a BUILT root filesystem (issue 09); an unbuilt/unknown value is
    # a no-op (rc 1, unchanged) so the picker can never author an uninstallable fs.
    _ctl_built_root_filesystems | grep -qxF "$val" \
      || { printf '%s' "$state"; return 1; }
    edit_set_scalar "$state" filesystem "$val" ;;
  options.bootloader | post_install.security.firewall \
    | environment.display_manager)
    edit_set_scalar "$state" "$path" "$val" ;;
  options.power.profile)
    # Power Profile enum (ADR 0080): a 3-value scalar, NOT a bool — commit only a
    # known backend so the picker can never author an invalid daemon; an unknown
    # value is a no-op (rc 1, unchanged).
    case "$val" in none | power-profiles-daemon | tuned) ;;
      *) printf '%s' "$state"; return 1 ;; esac
    edit_set_scalar "$state" options.power.profile "$val" ;;
  *) edit_set_bool "$state" "$path" "$val" ;;
  esac
}

# _ctl_apply_text <state> <path> <value> → new state for a free-text field.
# sysctl parses key=value; the extra-packages row appends; rest are scalars.
_ctl_apply_text() {
  local state="$1" path="$2" val="$3"
  # Manual Partitioning locks the pool-dependent Disks fields (ADR 0073), incl.
  # the free-text esp size: a locked field is a no-op (rc 1, unchanged).
  _ctl_manual_locked "$state" "$path" && { printf '%s' "$state"; return 1; }
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
  options.mirror_servers)
    # A custom mirror Server= URL, appended (dedup) — ADR 0072.
    [[ -n "$val" ]] || { printf '%s' "$state"; return 1; }
    cfgstate_set "$state" options.mirror_servers "$(jq -cn \
      --argjson a "$(jq -c '.options.mirror_servers // []' <<<"$state")" \
      --arg v "$val" 'if any($a[]; . == $v) then $a else $a + [$v] end')" ;;
  options.custom_repositories)
    # "name url [sign_check] [sign_option]" → an object appended (dedup by name);
    # sign_check/sign_option default to Required/TrustedOnly (ADR 0072).
    local -a _rf; read -ra _rf <<<"$val"
    [[ ${#_rf[@]} -ge 2 ]] || { printf '%s' "$state"; return 1; }
    cfgstate_set "$state" options.custom_repositories "$(jq -cn \
      --argjson a "$(jq -c '.options.custom_repositories // []' <<<"$state")" \
      --arg n "${_rf[0]}" --arg u "${_rf[1]}" \
      --arg c "${_rf[2]:-Required}" --arg o "${_rf[3]:-TrustedOnly}" \
      'if any($a[]; .name == $n) then $a
       else $a + [{name:$n, url:$u, sign_check:$c, sign_option:$o}] end')" ;;
  packages.repo.extra) _ctl_route_package_entry "$state" "$val" repo ;;
  packages.aur.extra)  _ctl_route_package_entry "$state" "$val" aur ;;
  *) edit_set_scalar "$state" "$path" "$val" ;;
  esac
}

# _ctl_route_package_entry <state> <raw> [slot] — split the space-separated
# typed into the extra-packages row by kind, at ENTRY time, and file each into
# the slot it belongs in: a system Program → host_programs, a user Program →
# the Primary User's programs, anything else → packages.repo.extra.
#
# This is the guided convenience the deleted promotion rule used to provide,
# moved from the emit path to entry so it cannot cause front-end divergence:
# what lands in Config State is already canonical, so Save, Export and Proceed
# all agree, and the config-load exclusivity check has nothing to reject.
# The notice naming what was rerouted is emitted on stderr (the controller's
# out-of-band channel) so the operator learns where their name went.
_ctl_route_package_entry() {
  local state="$1" raw="$2" slot="${3:-repo}"
  [[ -n "$raw" ]] || { printf '%s' "$state"; return 1; }

  local -a pkgs=() sys=() usr=()
  local name
  for name in $raw; do
    case "$(program_kind "$name")" in
    host) sys+=("$name") ;;
    user) usr+=("$name") ;;
    *)    pkgs+=("$name") ;;
    esac
  done

  ((${#pkgs[@]})) \
    && state="$(edit_append_packages "$state" "${pkgs[*]}" "$slot")"
  if ((${#sys[@]})); then
    state="$(edit_append_host_programs "$state" "${sys[@]}")"
    printf 'routed to host programs: %s\n' "${sys[*]}" >&2
  fi
  if ((${#usr[@]})); then
    state="$(_ctl_append_primary_user_programs "$state" "${usr[@]}")"
    printf 'routed to user programs: %s\n' "${usr[*]}" >&2
  fi
  printf '%s' "$state"
}

# _ctl_append_primary_user_programs <state> <name...> — dedup-append user
# Program name(s) to the Primary User's (users[0]) programs override. With no
# users declared there is nowhere host-independent to put them, so they fall
# back to being plain repo packages rather than being silently dropped.
_ctl_append_primary_user_programs() {
  local state="$1"; shift
  local primary
  primary="$(jq -r '.users[0] // empty' \
    <<<"$(_ctl_effective "$state" "$(_ctl_baseline)")")"
  if [[ -z "$primary" || -z "${GUIDED_USERFORMS_FILE:-}" ]]; then
    edit_append_packages "$state" "$*"
    return 0
  fi
  local cur add
  cur="$(guided_userform_get "$GUIDED_USERFORMS_FILE" "$primary" \
    | jq -c '.programs // []')"
  add="$(printf '%s\n' "$@" | jq -R . | jq -s -c .)"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$primary" programs \
    "$(jq -cn --argjson a "$cur" --argjson b "$add" \
      'reduce ($a + $b)[] as $x ([];
         if any(.[]; . == $x) then . else . + [$x] end)')"
  printf '%s' "$state"
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

# _ctl_curated_persist_count — the number of Curated Persist Defaults always
# persisted under impermanence (files + dirs, ADR 0066), for the Impermanence
# Editor's read-only summary line. Reads the single-source arrays sourced from
# impermanence-common.sh at load.
_ctl_curated_persist_count() {
  printf '%s' "$(( ${#CURATED_FILES[@]} + ${#CURATED_DIRS[@]} ))"
}

# _ctl_host_program_names / _ctl_user_program_names — the option set for each
# program picker, filtered on the registry's kind (R22). The two screens have
# opposite requirements: host host_programs needs kind host (else
# validate_programs rejects the config at Proceed), the User Editor's programs
# row needs kind user (else the reference silently no-ops or aborts). One
# unfiltered list used to feed both.
#
# Programs the Printing toggle owns (cups) are filtered out (ADR 0079): they are
# derived from options.printing.enabled, so the Printing service category is
# their sole home — offering cups here too would be the double representation
# the toggle exists to remove. Keyed on the toggle-owned sets, not literals —
# each toggle-derived Host Program (cups, bluetooth — ADR 0079/0080) has its
# category as its sole home, so all are filtered from this Packages picker.
_ctl_host_program_names() {
  program_names_of_kind host \
    | grep -vxF -f <(printing_owned_programs; bluetooth_owned_programs; \
                     power_owned_programs)
}
_ctl_user_program_names()   { program_names_of_kind user; }

# _ctl_toggle_options <field> → the raw option lines for a toggle (multi) field.
_ctl_toggle_options() {
  case "$1" in
  options.kernel | environment.desktop | environment.gpu \
    | options.mirror_countries | options.optional_repos | options.fonts)
    menu_enum_options "$1" ;;
  host_programs)     _ctl_host_program_names ;;
  system.keymap)       _ctl_biglist_options system.keymap ;;
  esac
}

# _ctl_field_has_preview <field> → rc 0 if this values screen shows a side panel
# (the layout graph, the selection panel for the big keymap/locale/timezone, or
# the per-user detail panel on the Users screen — ADR 0063).
_ctl_field_has_preview() {
  case "$1" in
  __layout__ | system.keymap | system.timezone | users \
    | __language__ | __encoding__ | system.console_font)
    return 0 ;;
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

# _ctl_default_user_shell — the login shell an ad-hoc user gets: User Core's
# declared shell, else /bin/zsh. Reading User Core rather than hardcoding keeps
# the guided default in step with the committed base (ADR 0056 curation), so a
# name typed into the menu lands in the same shell a declared user would.
_ctl_default_user_shell() {
  local s=""
  [[ -n "${OS_DIR:-}" && -f "${OS_DIR}/users/core/profile.jsonc" ]] \
    && s="$(_configs_parse "${OS_DIR}/users/core/profile.jsonc" 2>/dev/null \
          | jq -r '.shell // empty' 2>/dev/null)"
  printf '%s' "${s:-/bin/zsh}"
}

# _ctl_user_shell_full <name> — the effective login shell PATH: the User Editor's
# install-scoped override (userforms file) if set, else the committed User
# Profile's shell merged over User Core, else the User Core default (an ad-hoc
# name with no committed profile). The single source of truth the list display,
# the editor row, and the shell cycle all read.
_ctl_user_shell_full() {
  local n="$1" s=""
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && s="$(guided_userform_field "$GUIDED_USERFORMS_FILE" "$n" shell)"
  if [[ -z "$s" && -n "${OS_DIR:-}" && -f "${OS_DIR}/users/${n}/profile.jsonc" ]]; then
    s="$(load_user_profile "$n" 2>/dev/null | jq -r '.shell // empty' 2>/dev/null)"
  fi
  [[ -n "$s" ]] || s="$(_ctl_default_user_shell)"
  printf '%s' "$s"
}

# _ctl_user_shell <name> — the short login shell (basename) for the list row.
_ctl_user_shell() { local s; s="$(_ctl_user_shell_full "$1")"; printf '%s' "${s##*/}"; }

# _ctl_root_shell_full — root's effective login shell PATH (ADR 0054): the
# Config State override (options.root_shell) merged over the baseline, else the
# baseline's, else /bin/bash. The single source the Users row + the cycle read.
_ctl_root_shell_full() {
  local s
  s="$(jq -r '.options.root_shell // "/bin/bash"' \
    <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")"
  printf '%s' "$s"
}

# _ctl_root_shell — root's short login shell (basename) for the Users row.
_ctl_root_shell() {
  local s; s="$(_ctl_root_shell_full)"; printf '%s' "${s##*/}"
}

# _ctl_root_shell_committed — the baseline (launch-state) root shell, or
# /bin/bash. The strict-delta reference: cycling onto it drops the override.
_ctl_root_shell_committed() {
  jq -r '.options.root_shell // "/bin/bash"' <<<"$(_ctl_baseline)"
}

# _ctl_user_is_committed <name> — rc 0 when the user has a committed profile
# (users/<name>/profile.jsonc under OS_DIR): the editor shows `enabled` for those
# and `✗ remove user` for a session-created (ad-hoc) name instead.
_ctl_user_is_committed() {
  [[ -n "${OS_DIR:-}" && -f "${OS_DIR}/users/${1}/profile.jsonc" ]]
}

# _ctl_user_committed <name> — the committed (core-merged) User Profile as JSON,
# or {} for a session-created name. The strict-delta baseline the User Editor
# compares an override against; also the display base before the override.
_ctl_user_committed() {
  local c='{}'
  _ctl_user_is_committed "$1" \
    && c="$(load_user_profile "$1" 2>/dev/null || printf '{}')"
  printf '%s' "${c:-{\}}"
}

# _ctl_user_effective <name> — committed profile `*` the install-scoped override
# (userforms file): what the installed user will actually get. Every User Editor
# row displays from this.
_ctl_user_effective() {
  local n="$1" c f='{}'
  c="$(_ctl_user_committed "$n")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && f="$(guided_userform_get "$GUIDED_USERFORMS_FILE" "$n")"
  jq -n --argjson c "$c" --argjson f "$f" '$c * $f'
}

# _ctl_userfield_kind <field> — multi (groups/programs) | text (git.name/
# git.email) | list (ssh). Drives the userfield screen's render + enter.
_ctl_userfield_kind() {
  case "$1" in
  groups | programs)              echo multi ;;
  git.name | git.email | ssh.add) echo text ;;
  ssh)                            echo list ;;
  esac
}

# _ctl_userfield_options <field> — the candidate lines for a multi userfield: a
# curated group set (matching the create form) or the resolvable program names.
_ctl_userfield_options() {
  case "$1" in
  groups)   printf '%s\n' wheel docker libvirt kvm ;;
  programs) _ctl_user_program_names ;;
  esac
}

# _ctl_userform_set_strict <user> <key> <new-json> <committed-json> — set the
# per-user override at <key>, or DROP it when <new> equals the committed value
# (strict delta: an edit that lands on the committed value leaves no override).
# No-op when no userforms file is wired.
_ctl_userform_set_strict() {
  local u="$1" k="$2" new="$3" committed="$4"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  if [[ "$(jq -cS . <<<"$new")" == "$(jq -cS . <<<"$committed")" ]]; then
    guided_userform_unset "$GUIDED_USERFORMS_FILE" "$u" "$k"
  else
    guided_userform_set "$GUIDED_USERFORMS_FILE" "$u" "$k" "$new"
  fi
}

# _ctl_clone_seed <source> <newname> — copy the source user's effective
# account-shape (shell, sudo, groups, programs) into <newname>'s install-scoped
# delta (ADR 0064). Personal fields (git identity, ssh keys) and the
# password are NOT copied — a clone shares setup, not identity — so the clone
# lands password-less (Proceed stays blocked until set). shell is materialised
# from the resolved full path so a defaulted source shell still copies. No-op
# without a userforms file (non-persistent contexts): the name is still created,
# just without a delta.
_ctl_clone_seed() {
  local src="$1" new="$2" eff
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || return 0
  eff="$(_ctl_user_effective "$src")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" shell \
    "$(jq -Rn --arg s "$(_ctl_user_shell_full "$src")" '$s')"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" sudo \
    "$(jq -c 'if .sudo then true else false end' <<<"$eff")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" groups \
    "$(jq -c '.groups // []' <<<"$eff")"
  guided_userform_set "$GUIDED_USERFORMS_FILE" "$new" programs \
    "$(jq -c '.programs // []' <<<"$eff")"
}

# _ctl_userfield_toggle_multi <user> <field> <value> — flip <value> in the user's
# effective array for a multi field, stored as the full override (strict delta vs
# the committed array).
_ctl_userfield_toggle_multi() {
  local u="$1" field="$2" val="$3" eff cur new committed
  eff="$(_ctl_user_effective "$u")"
  cur="$(jq -c --arg f "$field" '.[$f] // []' <<<"$eff")"
  new="$(jq -cn --argjson a "$cur" --arg v "$val" \
    'if any($a[]; . == $v) then ($a - [$v]) else ($a + [$v]) end')"
  committed="$(jq -c --arg f "$field" '.[$f] // []' <<<"$(_ctl_user_committed "$u")")"
  _ctl_userform_set_strict "$u" "$field" "$new" "$committed"
}

# _ctl_userfield_set_git <user> <subkey> <value> — set git.name / git.email into
# the user's override git object (strict delta vs the committed git). An empty
# value drops that sub-key.
_ctl_userfield_set_git() {
  local u="$1" sub="$2" val="$3" cur committed new
  cur="$(jq -c '.git // {}' <<<"$(_ctl_user_effective "$u")")"
  committed="$(jq -c '.git // {}' <<<"$(_ctl_user_committed "$u")")"
  new="$(jq -c --arg k "$sub" --arg v "$val" \
    'if $v == "" then del(.[$k]) else .[$k] = $v end' <<<"$cur")"
  _ctl_userform_set_strict "$u" git "$new" "$committed"
}

# _ctl_userfield_add_ssh <user> <key> — append one SSH authorized key to the
# user's effective list, stored as the full override (strict delta vs committed).
_ctl_userfield_add_ssh() {
  local u="$1" key="$2" cur committed new
  [[ -n "$key" ]] || return 0
  cur="$(jq -c '.ssh_authorized_keys // []' <<<"$(_ctl_user_effective "$u")")"
  new="$(jq -c --arg k "$key" '. + [$k]' <<<"$cur")"
  committed="$(jq -c '.ssh_authorized_keys // []' \
    <<<"$(_ctl_user_committed "$u")")"
  _ctl_userform_set_strict "$u" ssh_authorized_keys "$new" "$committed"
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
  # Labels render through the Display Label formatter, so reverse-map the
  # formatted label back to a field by formatting each candidate and comparing.
  local cat="$1" want="$2" field label
  while IFS=$'\t' read -r field label; do
    [[ "$(display_label "$label")" == "$want" ]] \
      && { printf '%s' "$field"; return; }
  done < <(menu_category_rows "$cat" "$(_ctl_state)" "$(_ctl_baseline)" \
    | jq -r '.[] | [.field, .label] | @tsv')
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
  profiles) b='Enter seed from profile   Esc back' ;;
  newhost)  b='Enter confirm reset   Esc cancel' ;;
  rooteditor) b='Enter edit/cycle   Esc back' ;;
  category) b='Enter edit / cycle   Esc back' ;;
  values)
    if [[ "$(nav_get "$1" field)" == "users" ]]; then
      b='Enter toggle / set pw   Esc back'
    elif [[ "$(_ctl_field_kind "$(nav_get "$1" field)")" == "toggle" ]]; then
      b='Enter toggle ✓   Esc done'
    else
      b='Enter choose   Esc back'
    fi ;;
  text)     b='Type a value, Enter save   Esc back' ;;
  swapedit)  b='Enter edit/toggle   Esc back' ;;
  manualparts) b='Enter open / cfdisk   Esc back' ;;
  partedit)  b='Enter cycle/toggle   Esc back' ;;
  encryption) b='Enter edit/toggle   Esc back' ;;
  impermanence) b='Enter edit/toggle/remove   Esc back' ;;
  datapools) b='Enter open/add   Esc back' ;;
  pooledit)  b='Enter cycle/remove   Esc back' ;;
  pooldisks) b='Enter bind/unbind ✓   Esc back' ;;
  rootdisk)  b='Enter pick   Esc back' ;;
  useredit)  b='Enter edit/toggle   Esc back' ;;
  userfield)
    case "$(_ctl_userfield_kind "$(nav_get "$1" field)")" in
    multi) b='Enter toggle ✓   Esc back' ;;
    text)  b='Type a value, Enter save   Esc back' ;;
    list)  b='Enter add   Esc back' ;;
    esac ;;
  secret)    b='Type the password, Enter continues   Esc cancels' ;;
  pkgcat)    b='Enter open / add   Esc back' ;;
  pkgs)      b='Enter toggle ✓   Esc back' ;;
  pkgderived)    b='Enter open (read-only)   Esc back' ;;
  pkgderivedsrc) b='Read-only — change it in Environment/Security/Backup' ;;
  *)        b='Esc back' ;;
  esac
  printf '%s   ·   ^Z undo  ^Y redo  ^R reset' "$b"
}
_ctl_nav_prompt() {
  case "$(nav_screen "$1")" in
  top)         printf 'guided> ' ;;
  profiles)    printf 'profiles> ' ;;
  newhost)     printf 'reset> ' ;;
  rooteditor)  printf 'root> ' ;;
  category)    printf '%s> ' "$(nav_get "$1" category)" ;;
  values|text) printf '%s> ' "$(nav_get "$1" label)" ;;
  swapedit)    printf 'swap> ' ;;
  manualparts) printf 'partitions> ' ;;
  partedit)    printf 'partition> ' ;;
  encryption)  printf 'encryption> ' ;;
  impermanence) printf 'impermanence> ' ;;
  datapools)   printf 'data pools> ' ;;
  pooledit)    printf 'pool> ' ;;
  pooldisks)   printf 'disks> ' ;;
  rootdisk)    printf 'root disk> ' ;;
  useredit)    printf '%s> ' "$(nav_get "$1" user)" ;;
  userfield)   printf '%s> ' "$(nav_get "$1" label)" ;;
  secret)      printf 'password> ' ;;
  pkgcat)        printf '%s> ' "$(nav_get "$1" slot)" ;;
  pkgs)          printf '%s/%s> ' "$(nav_get "$1" slot)" \
                   "$(nav_get "$1" pkgcat)" ;;
  pkgderived)    printf 'derived> ' ;;
  pkgderivedsrc) printf 'derived/%s> ' "$(nav_get "$1" source)" ;;
  *)           printf 'guided> ' ;;
  esac
}

# _ctl_esp_budget_warn <effective-json> → a one-line ⚠ when a PINNED esp_size is
# too small for the selected kernels on an ESP-mirroring loader (ADR 0078), so
# the conflict shows live on the Kernels / Disks screens, not only at Proceed.
# Nothing when esp_size is auto, the loader is grub, or the pin fits.
_ctl_esp_budget_warn() {
  local eff="$1" size n fs bl
  size="$(jq -r '.options.esp_size // "auto"' <<<"$eff")"
  [[ "$size" == auto ]] && return 0
  n="$(jq -r '(.options.kernel // ["lts"])
              | if type == "string" then 1 else length end' <<<"$eff")"
  fs="$(jq -r '.filesystem // "zfs"' <<<"$eff")"
  bl="$(jq -r '.options.bootloader // "systemd-boot"' <<<"$eff")"
  esp_budget_fits_size "$size" "$n" "$fs" "$bl" && return 0
  printf '⚠ ESP too small: %s %s kernel(s) need ≥ %s (esp size is %s)\n' \
    "$n" "$bl" "$(esp_budget_auto_size "$n" "$fs" "$bl")" "$size"
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

# _ctl_encryption_label <effective-json> <tag> → the one-line summary for the
# collapsed Disks Encryption row (ADR 0059): "off" when encryption is disabled,
# else "on · <tag>" where <tag> is the source tag (default <value> / custom /
# from age) computed by the caller. Pure: JSON + a string in, a string out — so
# the row text is testable without fzf or the secrets file, the way _ctl_swap_
# label is.
_ctl_encryption_label() {
  local eff="$1" tag="$2"
  if [[ "$(cfgstate_get "$eff" options.encryption)" == "true" ]]; then
    printf 'on · %s' "$tag"
  else
    printf 'off'
  fi
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

# _ctl_action_row <line...> — emit action rows (Back/Add/remove/create) as
# visible list rows in BOTH chromes (ADR 0063, amends 0047). Rich fzf still
# keeps the ^A/^X/Esc keybindings + footer as accelerators, but the rows render
# too, so every action is discoverable at a glance (a footer-only ^A proved
# invisible — the only way to add a user was an undocumented shortcut). Rich
# chrome otherwise (footer, breadcrumb, borders) is untouched.
_ctl_action_row() { printf '%s\n' "$@"; }

# ── Packages screen helpers (ADR 0058) ───────────────────────────────────────
# Provenance is three-state, reusing the existing override dot rather than
# inventing glyphs:
#   checked, no dot   — inherited from Host Core
#   checked, with dot — added by this profile or session
#   unchecked, with dot — excluded by this profile
#
# The toggle list can only offer the DECLARED UNION across Host Core and the
# profile: the universe of Arch packages is not enumerable, so adding a
# brand-new package stays a free-text entry (the `+ Add package` row).

# _ctl_pkg_union <effective> <slot> <cat> — the package names offerable in one
# category: everything the effective view carries plus everything Host Core
# declares there plus anything currently excluded (so it can be re-checked).
_ctl_pkg_union() {
  local eff="$1" slot="$2" cat="$3" core
  core="$(cfgstate_host_core)"
  jq -rn --argjson e "$eff" --argjson c "$core" \
     --arg s "$slot" --arg k "$cat" '
    (($e.packages[$s][$k] // []) + ($c.packages[$s][$k] // [])
     + [($e.packages.exclude // [])[]
        | select(. as $x | ($c.packages[$s][$k] // []) | index($x))])
    | unique | .[]'
}

# _ctl_pkg_categories <effective> <slot> — the categories to list, unioned
# across the effective view and Host Core so a core-only category still shows.
_ctl_pkg_categories() {
  local eff="$1" slot="$2" core
  core="$(cfgstate_host_core)"
  jq -rn --argjson e "$eff" --argjson c "$core" --arg s "$slot" '
    (($e.packages[$s] // {}) + ($c.packages[$s] // {}))
    | keys_unsorted | sort | .[]'
}

# _ctl_pkg_slot_count <effective> <slot> — how many packages the slot resolves
# to right now (post-exclusion), for the category row summary.
_ctl_pkg_slot_count() {
  jq -rn --argjson e "$1" --arg s "$2" \
    '[($e.packages[$s] // {}) | to_entries[]
      | select(.value | type == "array") | .value[]] | unique | length'
}

# _ctl_pkg_excluded <state> <pkg> — rc 0 when <pkg> is in packages.exclude.
_ctl_pkg_excluded() {
  jq -e --arg p "$2" '(.packages.exclude // []) | index($p)' \
    <<<"$1" >/dev/null 2>&1
}

# _ctl_pkg_in_core <slot> <cat> <pkg> — rc 0 when Host Core declares it there.
_ctl_pkg_in_core() {
  jq -e --arg s "$1" --arg k "$2" --arg p "$3" \
    '(.packages[$s][$k] // []) | index($p)' \
    <<<"$(cfgstate_host_core)" >/dev/null 2>&1
}

# _ctl_pkg_derived <effective> — the Package Resolver's derived rows for this
# config (TSV: source, layer, package). The SAME resolver the CLI inspector
# calls, so the menu's derived section and `explain-packages` cannot drift.
_ctl_pkg_derived() {
  pkgres_resolve "$1" 2>/dev/null | awk -F'\t' '$2 == "derived"'
}

# _ctl_pkg_derived_total <effective> — unique derived package count.
_ctl_pkg_derived_total() {
  local n; n="$(_ctl_pkg_derived "$1" | cut -f3 | sort -u | grep -c .)"
  printf '%s' "${n:-0}"
}

# The source → driving-category mapping lives with the source table in
# resolver.sh (pkgres_source_origin), so a new derived source cannot render
# here with a missing origin.

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

# _ctl_user_panel <name> — the hovered user's detail panel (ADR 0063): the
# effective (committed-core-merged, session-override-applied) User Profile a
# session-created user shows its in-progress editor-form state, since
# _ctl_user_effective folds the userforms file. Pure over the effective view.
_ctl_user_panel() {
  local u="$1" eff gn ge
  eff="$(_ctl_user_effective "$u")"
  printf '%s\n' "$u"
  printf '  shell:    %s\n' "$(jq -r '.shell // "/bin/zsh"' <<<"$eff")"
  printf '  sudo:     %s\n' \
    "$(jq -r 'if .sudo then "on" else "off" end' <<<"$eff")"
  printf '  groups:   %s\n' "$(jq -r \
    '(.groups // []) | join(", ") | if . == "" then "(none)" else . end' \
    <<<"$eff")"
  printf '  programs: %s\n' "$(jq -r \
    '(.programs // []) | if length == 0 then "(none)"
       else "\(length) · \(join(", "))" end' <<<"$eff")"
  gn="$(jq -r '.git.name // ""' <<<"$eff")"
  ge="$(jq -r '.git.email // ""' <<<"$eff")"
  [[ -n "$gn" || -n "$ge" ]] && printf '  git:      %s <%s>\n' "$gn" "$ge"
  printf '  ssh keys: %s\n' \
    "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$eff")"
}

# _ctl_profile_tree <resolved-profile-json> — a deep ASCII tree of a machine for
# the Profiles preview (ADR 0063): hostname; users expanded to shell·groups;
# options (kernel, bootloader, encryption, impermanence, swap, ssh); environment
# (desktop/gpu); security; backup; and the disk skeleton (reusing the layout
# graph). Input is the RESOLVED profile (merged over Host Core) so it shows what
# selecting it installs, not the raw on-disk delta. Uses the same ▸ / └─ tree
# style as _ctl_layout_graph so previews feel consistent.
_ctl_profile_tree() {
  local prof="$1" u up sh grp
  jq -r '.system.hostname // "(unnamed host)"' <<<"$prof"
  printf '  ▸ users\n'
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    up="$(load_user_profile "$u" 2>/dev/null || printf '{}')"
    [[ -n "$up" ]] || up='{}'
    sh="$(jq -r '.shell // "/bin/zsh"' <<<"$up")"
    grp="$(jq -r '(.groups // []) | join(", ")' <<<"$up")"
    [[ -n "$grp" ]] || grp="-"
    printf '      └─ %s  (%s · %s)\n' "$u" "$sh" "$grp"
  done < <(jq -r '(.users // [])[]' <<<"$prof")
  jq -r '
    def onoff(v): if v == true then "on" else "off" end;
    "  ▸ options",
    "      └─ kernel: \((.options.kernel // ["lts"])
       | if type == "array" then join(", ") else . end)",
    "      └─ bootloader: \(.options.bootloader // "systemd-boot")",
    "      └─ encryption: \(onoff(.options.encryption))",
    "      └─ impermanence: \(onoff(.options.impermanence.enabled))",
    "      └─ swap: \(if .options.swap == false then "off"
       else (.options.swap_size // "auto") end)",
    "      └─ ssh: \(onoff(.options.ssh.enabled))",
    "  ▸ environment",
    "      └─ desktop: \((.environment.desktop // [])
       | if type == "array"
         then (if length == 0 then "(none)" else join(", ") end)
         else . end)",
    "      └─ gpu: \(.environment.gpu // "auto"
       | if type == "array" then join(", ") else . end)",
    "  ▸ security",
    "      └─ firewall: \(.post_install.security.firewall // "none")",
    "      └─ antivirus: \(onoff(.post_install.security.antivirus))",
    "      └─ rootkit: \(onoff(.post_install.security.rootkit))",
    "      └─ apparmor: \(onoff(.post_install.security.apparmor))",
    "  ▸ backup",
    "      └─ snapshots: \(onoff(.post_install.backup.zfs_auto_snapshot))",
    "      └─ borg: \(onoff(.post_install.backup.borg))"
  ' <<<"$prof"
  printf '  ▸ disks\n'
  _ctl_layout_graph "$prof" \
    | while IFS= read -r _l; do printf '      %s\n' "$_l"; done
}

# ── always-on master-detail pane (ADR 0071) ──────────────────────────────────
# On the top + category screens the preview pane is a live detail column: a
# parent column (the siblings, current item marked "▶", the rest dimmed) above
# the highlighted item's detail. Pure: reads state + nav from files like
# guided_ctl_list, so it is asserted headless (tests/config/guided-detail.bats).
_CTL_DIM=$'\033[2m'; _CTL_BOLD=$'\033[1m'; _CTL_RST=$'\033[0m'

# _ctl_detail_column <current> < "name\toverridden"-lines — the parent column:
# each name a row, the one equal to <current> marked "▶", the rest dimmed, and a
# "●" appended to any overridden sibling (user story 14).
_ctl_detail_column() {
  local current="$1" n ov dot
  while IFS=$'\t' read -r n ov; do
    dot=""; [[ "$ov" == true ]] && dot="  ●"
    if [[ -n "$current" && "$n" == "$current" ]]; then
      printf '  %s▶ %s%s%s\n' "$_CTL_BOLD" "$n" "$dot" "$_CTL_RST"
    else
      printf '%s    %s%s%s\n' "$_CTL_DIM" "$n" "$dot" "$_CTL_RST"
    fi
  done
}

# _ctl_detail_leaf <field> <state> <base> — one field's leaf detail, shared by
# the category-screen field row and the field editor screens: its label, current
# value (● when overridden), then either its option set (enumerable) or a
# free-text hint (a text field). Pure.
_ctl_detail_leaf() {
  local field="$1" state="$2" base="$3" row label val ov dot opts
  row="$(menu_rows "$state" "$base" \
    | jq -c --arg p "$field" 'first(.[] | select(.field == $p)) // {}')"
  label="$(jq -r '.label // ""' <<<"$row")"
  val="$(jq -r '.value // ""' <<<"$row")"
  ov="$(jq -r '.overridden // false' <<<"$row")"
  dot=""; [[ "$ov" == true ]] && dot="  ●"
  printf '%s%s%s\n  %s: %s%s\n' "$_CTL_BOLD" "$label" "$_CTL_RST" \
    "$label" "${val:-(none)}" "$dot"
  if [[ "$(_ctl_field_kind "$field")" == text ]]; then
    printf '%s  (free text — type a value)%s\n' "$_CTL_DIM" "$_CTL_RST"
    return 0
  fi
  # A Cycle Field has no menu_enum_options list; render its two values with the
  # current one marked so Enter-flips-here stays discoverable (ADR 0075).
  if _ctl_is_cycle_field "$field"; then
    printf '%sCycle:%s\n' "$_CTL_DIM" "$_CTL_RST"
    local o
    for o in true false; do
      if [[ "$o" == "$val" ]]; then printf '  ● %s\n' "$o"
      else printf '    %s\n' "$o"; fi
    done
    return 0
  fi
  opts="$(menu_enum_options "$field")"
  [[ -n "$opts" ]] || return 0
  printf '%sOptions:%s\n' "$_CTL_DIM" "$_CTL_RST"
  sed 's/^/  /' <<<"$opts"
}

# _ctl_detail_reflector_note <category> — the reflector consumer line, shown
# only under Mirrors & Repositories: the countries feed reflector's ranking.
_ctl_detail_reflector_note() {
  [[ "$1" == "Mirrors & Repositories" ]] || return 0
  printf '%s  countries → reflector --country --latest 10 --sort rate%s\n' \
    "$_CTL_DIM" "$_CTL_RST"
}

# _ctl_detail_user_table <state> <base> — the Users account table for the detail
# pane (ticket 03): root's row plus each user's shell/sudo/groups panel, reusing
# the existing _ctl_user_panel builder (no new render). Disabled users show as
# such. Mirrors the flattened Users screen's rows.
_ctl_detail_user_table() {
  local state="$1" base="$2" um un
  printf '\n%sAccounts%s\n' "$_CTL_BOLD" "$_CTL_RST"
  printf 'root — %s · pw %s\n' "$(_ctl_root_shell)" "$(_ctl_secret_tag root)"
  while IFS= read -r um; do
    un="${um:4}"
    [[ -n "$un" ]] || continue
    if [[ "${um:0:3}" == "[x]" ]]; then _ctl_user_panel "$un"
    else printf '%s — disabled\n' "$un"; fi
  done < <(_ctl_user_marked "$state" "$base")
}

# _ctl_detail_top <line> <state> <base> — top-screen preview: the highlighted
# category's OWN detail only. The category parent column is gone (ADR 0082) — the
# current selection is marked by the fzf triangle pointer in the main list, so
# the pane no longer duplicates the category list. Users shows its table (ticket
# 03); every other category shows its fields as "label: value" (● on overrides).
# A non-category row (Profiles/Proceed/a bucket header/…) previews nothing.
_ctl_detail_top() {
  local line="$1" state="$2" base="$3" cur rows
  cur="${line%% — *}"
  if [[ "$cur" == "Users" ]]; then
    _ctl_detail_user_table "$state" "$base"; return 0
  fi
  rows="$(menu_category_rows "$cur" "$state" "$base" 2>/dev/null)"
  [[ -n "$rows" && "$rows" != "[]" ]] || return 0
  printf '%s%s%s\n' "$_CTL_BOLD" "$cur" "$_CTL_RST"
  jq -r '.[] | "  \(.label): \(.value // "")"
               + (if .overridden then "  ●" else "" end)' <<<"$rows"
  _ctl_detail_reflector_note "$cur"
}

# _ctl_detail_category <line> <state> <base> <cat> — category-screen preview:
# the sibling-field parent column + the highlighted leaf's value and options.
_ctl_detail_category() {
  local line="$1" state="$2" base="$3" cat="$4" label rows cur_field cur_label
  label="${line%%:*}"; label="${label%% ▸*}"
  cur_field="$(_ctl_field_for_label "$cat" "$label")"
  rows="$(menu_category_rows "$cat" "$state" "$base")"
  cur_label=""
  [[ -n "$cur_field" ]] && cur_label="$(jq -r --arg p "$cur_field" \
    'first(.[] | select(.field == $p) | .label) // ""' <<<"$rows")"
  printf '%s%s%s\n' "$_CTL_BOLD" "$cat" "$_CTL_RST"
  jq -r '.[] | "\(.label)\t\(.overridden)"' <<<"$rows" \
    | _ctl_detail_column "$cur_label"
  _ctl_detail_reflector_note "$cat"
  # The Disks Layout row is a synthetic leaf: preview the live ZFS pool tree,
  # reusing the layout-graph builder (ticket 03).
  if [[ "$cat" == "Disks" && "$label" == "$(display_label layout)" ]]; then
    printf '\n%sLayout%s\n' "$_CTL_BOLD" "$_CTL_RST"
    _ctl_layout_graph "$(_ctl_effective "$state" "$base")"
    return 0
  fi
  [[ -n "$cur_field" ]] || return 0
  printf '\n'
  _ctl_detail_leaf "$cur_field" "$state" "$base"
}

# _ctl_detail_pane <line> — the master-detail preview for the top / category
# screens (ADR 0071); empty on any other screen (they keep their own preview).
_ctl_detail_pane() {
  local line="$1" nav state base
  nav="$(_ctl_nav)"; state="$(_ctl_state)"; base="$(_ctl_baseline)"
  case "$(nav_screen "$nav")" in
  top)      _ctl_detail_top "$line" "$state" "$base" ;;
  category) _ctl_detail_category "$line" "$state" "$base" \
              "$(nav_get "$nav" category)" ;;
  esac
}

# guided_ctl_preview <line> — the fzf preview body. On the top + category +
# field screens it is the always-on master-detail pane (ADR 0071); on the
# layout / profiles / users screens it is that screen's own rich preview (the
# layout graph, profile tree, per-user panel); empty elsewhere.
guided_ctl_preview() {
  local line="$1" nav field
  nav="$(_ctl_nav)"
  case "$(nav_screen "$nav")" in
  top | category) _ctl_detail_pane "$line"; return 0 ;;
  esac
  # The data-pools editor screens graph the LIVE state (not a preset line) so the
  # tree reflects pools/disks as you add and cycle them.
  case "$(nav_screen "$nav")" in
  datapools | pooledit)
    _ctl_layout_graph "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    return 0 ;;
  profiles)
    # A deep ASCII tree of the resolved (Host-Core-merged) profile (ADR 0063),
    # down to its leaves — replacing the header-comment-only preview. The
    # Reset-to-blank / Back rows preview nothing.
    [[ "$line" == "← Back" || "$line" == "↺ Reset to blank"* || -z "$line" ]] \
      && return 0
    local _pf _prof
    _pf="$(_ctl_hosts_root)/${line}/profile.jsonc"
    if _prof="$(_configs_parse "$_pf" 2>/dev/null)"; then
      _ctl_profile_tree "$(layer_resolve host "$(cfgstate_host_core)" "$_prof")"
    else
      printf '\033[2m(no profile — hosts/%s/profile.jsonc)\033[0m\n' "$line"
    fi
    return 0 ;;
  text)
    # The free-text editor screen (hostname / URL / size / package name): the
    # shared leaf detail so the pane is populated here too (ADR 0071).
    _ctl_detail_leaf "$(nav_get "$nav" field)" \
      "$(_ctl_state)" "$(_ctl_baseline)"
    return 0 ;;
  esac
  [[ "$(nav_screen "$nav")" == "values" ]] || return 0
  field="$(nav_get "$nav" field)"
  # A field with no dedicated selection panel (kernel, bootloader, gpu, a bool)
  # gets the shared leaf detail, so every field screen shows a populated pane.
  if ! _ctl_field_has_preview "$field"; then
    _ctl_detail_leaf "$field" "$(_ctl_state)" "$(_ctl_baseline)"
    return 0
  fi
  case "$field" in
  users)
    # The hovered account's detail panel (ADR 0063). The root row shows its
    # shell + password source; a user row shows the effective (core-merged,
    # override-applied) User Profile — shell, sudo, groups, programs, git, ssh.
    [[ "$line" == "+ Create"* || "$line" == "← Back" || -z "$line" ]] \
      && return 0
    if [[ "$line" == "root — "* ]]; then
      printf 'root\n'
      printf '  shell:    %s\n' "$(_ctl_root_shell)"
      printf '  password: %s\n' "$(_ctl_secret_tag root)"
      return 0
    fi
    # "name — shell · pw tag" (enabled) or "name — disabled": name before " — ".
    local _pu; _pu="${line%% — *}"
    [[ -n "$_pu" ]] && _ctl_user_panel "$_pu" ;;
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

# ── Profiles picker (ADR 0055) ───────────────────────────────────────────────
# _ctl_hosts_root — the hosts/ tree the Profiles picker enumerates.
_ctl_hosts_root() { printf '%s' "${OS_DIR:-.}/hosts"; }

# _ctl_profiles_available — rc 0 when at least one installable Host Profile
# exists (so the top-screen `Profiles ▸` row is shown), rc 1 otherwise.
_ctl_profiles_available() {
  [[ -n "$(profiles_list "$(_ctl_hosts_root)" 2>/dev/null)" ]]
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
    # Profiles picker (ADR 0055/0063): a `Profiles ▸` row leads the screen, set
    # off by its own divider above the categories. Unconditional now — even a
    # fresh repo with no committed profiles shows it, because the picker leads
    # with `+ New host (start blank)`, so it is always a first-class entry.
    printf '%s\n' "Profiles ▸ start from a saved machine"
    printf '%s\n' "$_CTL_DIVIDER"
    # Secrets are never a gate (ADR 0055): root, every user, and the encryption
    # passphrase default to 12345, so Proceed always installs. The per-secret
    # source is surfaced (default 12345 / custom / from age) on the Users screen,
    # not as a top-row block. Save/Export are likewise never gated.
    menu_top_lines "$state" "$base"
    printf '%s\n' "$_CTL_DIVIDER"
    printf '%s\n' "Proceed ▸ review & install"
    # Manual Partitioning is Proceed-only (ADR 0073): a hand-drawn partition
    # table cannot be replayed from a committed file, so Save and Export are
    # withheld while it is active.
    if ! manual_kind_active "$state"; then
      printf '%s\n' \
        "Save profile ▸ write a device-less profile" \
        "Export config ▸ write a device-baked config"
    fi
    # Abort is always available (Esc-equivalent): a pre-destructive clean exit
    # so install.sh skips the back-end. Unconditional, unlike Save/Export which
    # are withheld under Manual Partitioning (ADR 0077).
    printf '%s\n' "Abort ▸ quit without installing" ;;
  profiles)
    # The picker leads with `↺ Reset to blank` (a confirm-gated full session
    # reset, ADR 0063), then the installable Host Profiles (ADR 0055) one row
    # each, then Back. The deep profile tree previews in the pane; picking a
    # profile seeds the menu. On a fresh repo only the reset row + Back show — a
    # consistent entry point.
    printf '%s\n' "↺ Reset to blank"
    profiles_list "$(_ctl_hosts_root)"
    _ctl_action_row "← Back" ;;
  newhost)
    # The `+ New host` confirmation (ADR 0063): a full session reset discards
    # ALL session work, so it is confirm-gated. Enter on the confirm row resets;
    # Back cancels. Broader than Reset-all (which clears Config State only).
    printf '%s\n' "Yes — discard session work and start blank"
    _ctl_action_row "← Back" ;;
  category)
    local cat; cat="$(nav_get "$nav" category)"
    # Live ESP budget warning (ADR 0078): surfaced on the Kernels + Disks
    # screens where kernels / esp_size are picked, not only at Proceed.
    if [[ "$cat" == "Disks" || "$cat" == "Kernels" ]]; then
      _ctl_esp_budget_warn "$(_ctl_effective "$state" "$base")"
    fi
    # Disks leads with the layout row (the headline storage choice), then fields.
    if [[ "$cat" == "Disks" ]] && manual_kind_active "$state"; then
      # Manual Partitioning (ADR 0073): the pool layout / root-disk / swap rows
      # are replaced by a single Partitions row that launches cfdisk and shows
      # how many partitions the operator has assigned so far.
      local _np
      _np="$(jq '(.disk_config.partitions // []) | length' <<<"$state")"
      printf 'Partitions ▸ %s assigned (run cfdisk)\n' "$_np"
    elif [[ "$cat" == "Disks" ]]; then
      local _ov=""
      jq -e '.os_pool or .mode or .storage_groups or .data_pools' \
        <<<"$state" >/dev/null 2>&1 && _ov="  ●"
      printf '%s: %s%s\n' "$(display_label layout)" \
        "$(_ctl_layout_label "$(_ctl_effective "$state" "$base")")" "$_ov"
      # Single-disk root binds in-menu on-target: a device-mode single-disk
      # layout gets a root disk row (ADR 0047). Multi layouts bind per pool;
      # off-target (count-mode) the single disk is resolved post-menu as before.
      local _deff; _deff="$(_ctl_effective "$state" "$base")"
      if _ctl_device_mode \
        && [[ "$(jq -r '.mode // "single"' <<<"$_deff")" != "multi" ]]; then
        local _rd; _rd="$(jq -r '.root_disk // ""' <<<"$_deff")"
        printf '%s: %s   (Enter to pick)\n' "$(display_label "root disk")" \
          "$([[ -n "$_rd" ]] && _ctl_disk_label "$_rd" || echo "(none)")"
      fi
      local _sov=""
      jq -e '.options.swap != null or .options.swap_size != null' \
        <<<"$state" >/dev/null 2>&1 && _sov="  ●"
      printf '%s: %s%s\n' "$(display_label swap)" \
        "$(_ctl_swap_label "$(_ctl_effective "$state" "$base")")" "$_sov"
    fi
    # Packages leads with the slot drill-downs (ADR 0058). packages.repo/aur had
    # no menu representation at all: seeding a profile carried its whole package
    # payload into Config State where the operator could neither see nor
    # deselect it. `derived` is read-only — it reports what the Environment,
    # Security and Backup choices pull in.
    if [[ "$cat" == "Packages" ]]; then
      local _eff_pkg; _eff_pkg="$(_ctl_effective "$state" "$base")"
      local _slot _n _sov
      for _slot in repo aur; do
        _n="$(_ctl_pkg_slot_count "$_eff_pkg" "$_slot")"
        _sov=""
        jq -e --arg s "$_slot" \
          '(.packages[$s] != null) or (.packages.exclude != null)' \
          <<<"$state" >/dev/null 2>&1 && _sov="  ●"
        printf '%s ▸ %s package%s%s\n' "$_slot" "$_n" \
          "$([[ "$_n" == 1 ]] || echo s)" "$_sov"
      done
      local _dtot; _dtot="$(_ctl_pkg_derived_total "$_eff_pkg")"
      printf 'derived ▸ %s package%s (read-only)\n' \
        "$_dtot" "$([[ "$_dtot" == 1 ]] || echo s)"
    fi
    # Unit-separator (\x1f), not @tsv: a tab IFS is whitespace, so read collapses
    # the double delimiter of an EMPTY value field and shifts the columns. \x1f
    # is non-whitespace, so empty fields are preserved.
    local _ffield _flabel _fval _fov
    while IFS=$'\x1f' read -r _ffield _flabel _fval _fov; do
      # Disks encryption collapses to ONE drill-down row (ADR 0059): the toggle
      # + passphrase live in the Encryption Editor, not on a bool row plus a
      # passphrase sub-row. The row still carries options.encryption's override
      # dot (_fov) so it reads like every other field.
      if [[ "$cat" == "Disks" && "$_ffield" == "options.encryption" ]]; then
        # Manual Partitioning forces it off (ADR 0073); show that, not the
        # retained-but-locked override the operator can no longer edit.
        if manual_kind_active "$state"; then
          printf 'Encryption ▸ off (manual)\n'
        else
          printf 'Encryption ▸ %s%s\n' \
            "$(_ctl_encryption_label "$(_ctl_effective "$state" "$base")" \
              "$(_ctl_secret_tag enc)")" \
            "$([[ "$_fov" == "true" ]] && printf '  ●')"
        fi
        continue
      fi
      # Impermanence collapses to ONE drill-down row (ADR 0066): the toggle +
      # persist-directory management live in the Impermanence Editor, not on a
      # bool row plus a separate Add-persist action. Carries the override dot.
      if [[ "$cat" == "Disks" \
            && "$_ffield" == "options.impermanence.enabled" ]]; then
        if manual_kind_active "$state"; then
          printf 'Impermanence ▸ off (manual)\n'   # forced off (ADR 0073)
          continue
        fi
        local _impon; _impon=off
        [[ "$(cfgstate_get "$(_ctl_effective "$state" "$base")" \
          options.impermanence.enabled)" == "true" ]] && _impon=on
        printf 'Impermanence ▸ %s%s\n' "$_impon" \
          "$([[ "$_fov" == "true" ]] && printf '  ●')"
        continue
      fi
      # Manual Partitioning is an on/off toggle (ADR 0073): the stored kind is
      # auto/manual, but the operator sees on/off. Enter flips it in place.
      if [[ "$cat" == "Disks" && "$_ffield" == "disk_config.kind" ]]; then
        local _mp=off
        [[ "$_fval" == "manual" ]] && _mp=on
        printf 'Manual partitioning: %s%s\n' "$_mp" \
          "$([[ "$_fov" == "true" ]] && printf '  ●')"
        continue
      fi
      printf '%s: %s%s\n' "$(display_label "$_flabel")" \
        "$(_ctl_display_value_str "$_ffield" "$_fval")" \
        "$([[ "$_fov" == "true" ]] && printf '  ●')"
    done < <(menu_category_rows "$cat" "$state" "$base" | jq -r \
      '.[] | [.field, .label, (.value // ""), (.overridden // false | tostring)]
             | join("\u001f")')
    _ctl_action_row "← Back" ;;
  pkgcat)
    # The categories inside one slot, each with its package count — mirroring
    # the Categorized List shape so the screen matches the file.
    local _pslot; _pslot="$(nav_get "$nav" slot)"
    local _peff; _peff="$(_ctl_effective "$state" "$base")"
    local _pk _pn
    while IFS= read -r _pk; do
      [[ -n "$_pk" ]] || continue
      _pn="$(_ctl_pkg_union "$_peff" "$_pslot" "$_pk" | grep -c .)"
      printf '%s ▸ %s\n' "$_pk" "$_pn"
    done < <(_ctl_pkg_categories "$_peff" "$_pslot")
    _ctl_action_row "+ Add package ▸ type a name not in the list"
    _ctl_action_row "← Back" ;;
  pkgs)
    # Package toggles with three-state provenance. An inherited entry renders
    # checked WITHOUT a dot; anything this profile or session touched carries
    # one, whether it was added or excluded.
    local _pslot _pcat _peff
    _pslot="$(nav_get "$nav" slot)"; _pcat="$(nav_get "$nav" pkgcat)"
    _peff="$(_ctl_effective "$state" "$base")"
    local _pp _mark _dot
    while IFS= read -r _pp; do
      [[ -n "$_pp" ]] || continue
      if _ctl_pkg_excluded "$_peff" "$_pp"; then
        _mark="[ ]"; _dot="  ●"          # excluded by this profile
      else
        _mark="[x]"
        if _ctl_pkg_in_core "$_pslot" "$_pcat" "$_pp"; then
          _dot=""                        # inherited from Host Core
        else
          _dot="  ●"                     # added here
        fi
      fi
      printf '%s %s%s\n' "$_mark" "$_pp" "$_dot"
    done < <(_ctl_pkg_union "$_peff" "$_pslot" "$_pcat")
    _ctl_action_row "← Back" ;;
  pkgderived)
    # Read-only (ADR 0021 keeps the DE adapter owning its own package set).
    # Each row names the category that drives it, so the operator knows where
    # to go to change it.
    # Resolve ONCE, then count per source — the resolver is the expensive part
    # of this render and the loop used to re-run it for every source.
    local _drows
    _drows="$(_ctl_pkg_derived "$(_ctl_effective "$state" "$base")")"
    local _dsrc _dn
    while IFS= read -r _dsrc; do
      [[ -n "$_dsrc" ]] || continue
      _dn="$(awk -F'\t' -v s="$_dsrc" '$1 == s { print $3 }' <<<"$_drows" \
        | sort -u | grep -c .)"
      [[ "$_dn" -gt 0 ]] || continue
      printf '%s ▸ %s   (from %s)\n' "$_dsrc" "$_dn" \
        "$(pkgres_source_origin "$_dsrc")"
    done < <(pkgres_sources 2>/dev/null)
    _ctl_action_row "← Back" ;;
  pkgderivedsrc)
    # One derived source's package list. Not toggleable — these are
    # consequences of choices made elsewhere in the menu.
    local _dsrc2; _dsrc2="$(nav_get "$nav" source)"
    _ctl_pkg_derived "$(_ctl_effective "$state" "$base")" \
      | awk -F'\t' -v s="$_dsrc2" '$1 == s { print "    " $3 }' | sort -u
    _ctl_action_row "← Back" ;;
  values)
    local vf; vf="$(nav_get "$nav" field)"
    if [[ "$vf" == "sysctl" ]]; then
      _ctl_sysctl_lines "$state" "$base"
      _ctl_action_row "+ Add sysctl (key=value)"
    elif [[ "$vf" == "options.mirror_servers" ]]; then
      # Custom mirror Server= URLs (ADR 0072): one per line + an Add action.
      jq -r '(.options.mirror_servers // [])[]' \
        <<<"$(_ctl_effective "$state" "$base")"
      _ctl_action_row "+ Add server (URL)"
    elif [[ "$vf" == "options.custom_repositories" ]]; then
      # Custom repositories (ADR 0072): "name — url · <SigLevel>" + an Add action.
      jq -r '(.options.custom_repositories // [])[]
        | "\(.name) — \(.url) · "
          + "\(.sign_check // "Required") \(.sign_option // "TrustedOnly")"' \
        <<<"$(_ctl_effective "$state" "$base")"
      _ctl_action_row "+ Add repository (name url [check] [trust])"
    elif [[ "$vf" == "users" ]]; then
      # Flattened Users screen — the account override surface. One merged root
      # row (ADR 0063) symmetric with a user row, then one row per user, each
      # tagged with its password source (default 12345 / custom / from age).
      # Never the value. Enter on the root row opens the Root Editor (password +
      # shell); Enter on a user row opens its User Editor. The disk passphrase
      # lives on the Disks Encryption Editor, not here (ADR 0059).
      local _rsh; _rsh="$(_ctl_root_shell)"
      printf 'root — %s · pw %s\n' "$_rsh" "$(_ctl_secret_tag root)"
      local _um _un _ushell _utag
      while IFS= read -r _um; do
        _un="${_um:4}"
        if [[ "${_um:0:3}" == "[x]" ]]; then
          _ushell="$(_ctl_user_shell "$_un")"
          _utag="$(_ctl_secret_tag user "$_un")"
          printf '%s — %s · pw %s\n' "$_un" "$_ushell" "$_utag"
          printf '      password (%s): %s\n' "$_un" "$_utag"
        else
          printf '%s — disabled\n' "$_un"
        fi
      done < <(_ctl_user_marked "$state" "$base")
      _ctl_action_row "+ Create user (name)"
    elif [[ "$(_ctl_field_kind "$vf")" == "biglist" ]]; then
      _ctl_biglist_options "$vf"
    elif [[ "$(_ctl_field_kind "$vf")" == "toggle" ]]; then
      if _ctl_display_values "$vf"; then
        local _ml; while IFS= read -r _ml; do
          printf '%s %s\n' "${_ml:0:3}" "$(display_label "${_ml:4}")"
        done < <(_ctl_marked_options "$vf" "$state" "$base")
      else
        _ctl_marked_options "$vf" "$state" "$base"
      fi
    else
      if _ctl_display_values "$vf"; then
        local _el; while IFS= read -r _el; do display_label "$_el"; done \
          < <(_ctl_enum_options "$vf")
      else
        _ctl_enum_options "$vf"
      fi
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
  manualparts)
    # Manual Partitioning assignment table (ADR 0073): a validity line, the
    # cfdisk hand-off, then one row per partition (device → mountpoint · fs).
    local _pj _probs
    _pj="$(cfgstate_get "$state" disk_config.partitions)"; _pj="${_pj:-[]}"
    if _probs="$(manual_partition_problems "$_pj")"; then
      printf '✓ layout is valid — ready to Proceed\n'
    else
      printf '⚠ not installable: %s\n' \
        "$(printf '%s' "$_probs" | head -n1 | sed 's/^• //')"
    fi
    _ctl_action_row "⟳ Run cfdisk (edit the partition table)"
    jq -c '.[]' <<< "$_pj" | while IFS= read -r _p; do
      manual_row_label "$_p"; printf '\n'
    done
    _ctl_action_row "← Back" ;;
  partedit)
    # Per-partition editor: mountpoint / filesystem / format, each cycled by
    # Enter. Only supported values are offered (ADR 0073).
    local _dev _mp _fs _fmt
    _dev="$(nav_get "$nav" device)"
    _mp="$(_ctl_manual_field "$state" "$_dev" mountpoint)"
    _fs="$(_ctl_manual_field "$state" "$_dev" fs)"
    _fmt="$(_ctl_manual_field "$state" "$_dev" format)"
    printf 'device: %s\n' "$_dev"
    printf 'mountpoint: %s   (Enter cycles)\n' \
      "${_mp:-(unassigned)}"
    printf 'filesystem: %s   (Enter cycles)\n' "${_fs:-(none)}"
    printf 'format: %s   (Enter toggles)\n' \
      "$([[ "$_fmt" == "true" ]] && echo on || echo off)"
    _ctl_action_row "← Back" ;;
  encryption)
    # The Encryption Editor (ADR 0059), collapsing like the swap editor above:
    # only the enablement row when off (a passphrase configures nothing then),
    # the passphrase row too when on. The passphrase row shows its source tag,
    # never the value.
    local _eff; _eff="$(_ctl_effective "$state" "$base")"
    if [[ "$(cfgstate_get "$_eff" options.encryption)" == "true" ]]; then
      printf 'enabled: on\n'
      printf 'password: %s\n' "$(_ctl_secret_tag enc)"
    else
      printf 'enabled: off\n'
    fi
    _ctl_action_row "← Back" ;;
  impermanence)
    # The Impermanence Editor (ADR 0066), collapsing like swap/encryption: only
    # the enablement row when off; when on, the persist directories (each a
    # removable row), a read-only curated-defaults count, and the Add action.
    local _eff _impen; _eff="$(_ctl_effective "$state" "$base")"
    _impen="$(cfgstate_get "$_eff" options.impermanence.enabled)"
    if [[ "$_impen" != "true" ]]; then
      printf 'enabled: off\n'
    else
      printf 'enabled: on\n'
      local _pd
      while IFS= read -r _pd; do
        [[ -n "$_pd" ]] && printf '%s\n' "$_pd"
      done < <(jq -r '(.persist.directories // [])[]' <<<"$_eff")
      printf 'curated defaults: %s paths always persisted (read-only)\n' \
        "$(_ctl_curated_persist_count)"
      _ctl_action_row "Add persist directory ▸ extend the curated defaults"
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
  rooteditor)
    # Root Editor (ADR 0063): root's two settings behind one editor, symmetric
    # with the per-user editor. Password uses the same masked capture + no-SOPS
    # root role; shell cycles /bin/bash → /bin/zsh → /bin/fish. Storage is
    # unchanged (options.root_shell + the root manifest role); only the surface
    # differs.
    printf 'password: %s\n' "$(_ctl_secret_tag root)"
    printf 'shell: %s   (Enter cycles)\n' "$(_ctl_root_shell)"
    _ctl_action_row "← Back" ;;
  useredit)
    # Per-user User Editor (ADR 0051): a committed user shows an `enabled` toggle
    # (in/out of the install), an ad-hoc user a `✗ remove user` row; both show the
    # full profile — shell, sudo, groups, git identity, ssh keys, programs — read
    # from the effective (committed `*` install-scoped override) view.
    local un ueff; un="$(nav_get "$nav" user)"
    ueff="$(_ctl_user_effective "$un")"
    if _ctl_user_is_committed "$un"; then
      local _en; _en="$(jq -r --arg u "$un" \
        'if ((.users // []) | any(. == $u)) then "on" else "off" end' \
        <<<"$(_ctl_effective "$state" "$base")")"
      printf 'enabled: %s   (Enter toggles)\n' "$_en"
    fi
    printf 'shell: %s   (Enter cycles)\n' "$(_ctl_user_shell "$un")"
    printf 'sudo: %s   (Enter toggles)\n' \
      "$(jq -r 'if .sudo then "on" else "off" end' <<<"$ueff")"
    printf 'groups: %s   (Enter edits)\n' \
      "$(jq -r '(.groups // []) | join(", ") | if . == "" then "(none)" else . end' \
        <<<"$ueff")"
    printf 'git name: %s   (Enter edits)\n' "$(jq -r '.git.name // "(unset)"' <<<"$ueff")"
    printf 'git email: %s   (Enter edits)\n' "$(jq -r '.git.email // "(unset)"' <<<"$ueff")"
    printf 'ssh keys: %s   (Enter edits)\n' \
      "$(jq -r '(.ssh_authorized_keys // []) | length' <<<"$ueff")"
    printf 'programs: %s   (Enter edits)\n' \
      "$(jq -r '(.programs // []) | join(", ") | if . == "" then "(none)" else . end' \
        <<<"$ueff")"
    printf '%s\n' "⧉ Clone this user"
    _ctl_user_is_committed "$un" || printf '%s\n' "✗ remove user"
    _ctl_action_row "← Back" ;;
  userfield)
    # A user-scoped sub-editor (ADR 0051): multi (groups/programs) marks options
    # against the effective value; text (git.name/git.email) shows current + hint;
    # list (ssh) shows the keys + an add action.
    local un field; un="$(nav_get "$nav" user)"; field="$(nav_get "$nav" field)"
    case "$(_ctl_userfield_kind "$field")" in
    multi)
      local _sel _opt
      _sel="$(jq -c --arg f "$field" '.[$f] // []' <<<"$(_ctl_user_effective "$un")")"
      while IFS= read -r _opt; do
        if jq -ne --argjson s "$_sel" --arg o "$_opt" 'any($s[]; . == $o)' \
            >/dev/null 2>&1; then printf '[x] %s\n' "$_opt"
        else printf '[ ] %s\n' "$_opt"; fi
      done < <(_ctl_userfield_options "$field")
      _ctl_action_row "← Back" ;;
    text)
      local _cur
      if [[ "$field" == git.* ]]; then
        _cur="$(jq -r --arg k "${field#git.}" '.git[$k] // ""' \
          <<<"$(_ctl_user_effective "$un")")"
        printf 'current: %s\n' "${_cur:-(unset)}"
      fi
      printf '%s\n' "(type above, Enter saves · Esc cancels)" ;;
    list)
      local _k
      while IFS= read -r _k; do [[ -n "$_k" ]] && printf '%s\n' "$_k"; done \
        < <(jq -r '(.ssh_authorized_keys // [])[]' <<<"$(_ctl_user_effective "$un")")
      _ctl_action_row "+ Add SSH key" ;;
    esac ;;
  secret)
    # Inline masked password entry (ADR 0051): the operator types into the fzf
    # query line (masked to bullets by the change bind); this body is just the
    # hint for the current target + phase. The value is read from the buffer file
    # on Enter, never shown here.
    local _tgt _ph _who
    _tgt="$(nav_get "$nav" target)"; _ph="$(nav_get "$nav" phase)"
    case "$_tgt" in
    user) _who="$(nav_get "$nav" user)" ;;
    enc)  _who="encryption" ;;
    *)    _who="root" ;;
    esac
    if [[ "$_ph" == "confirm" ]]; then
      printf 'confirm %s password — type it again, Enter saves\n' "$_who"
    else
      printf 'set %s password — type it, Enter continues\n' "$_who"
    fi
    printf '%s\n' "(masked · backspace to fix · Esc cancels)" ;;
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
  profiles)  _ctl_enter_profiles "$line" ;;
  newhost)   _ctl_enter_newhost "$line" ;;
  rooteditor) _ctl_enter_rooteditor "$line" ;;
  swapedit)  _ctl_enter_swapedit "$line" ;;
  manualparts) _ctl_enter_manualparts "$line" ;;
  partedit)  _ctl_enter_partedit "$line" ;;
  encryption) _ctl_enter_encryption "$line" ;;
  impermanence) _ctl_enter_impermanence "$line" ;;
  datapools) _ctl_enter_datapools "$line" ;;
  pooledit)  _ctl_enter_pooledit "$line" ;;
  pooldisks) _ctl_enter_pooldisks "$line" ;;
  rootdisk)  _ctl_enter_rootdisk "$line" ;;
  useredit)  _ctl_enter_useredit "$line" ;;
  userfield) _ctl_enter_userfield "$line" "$query" ;;
  secret)    _ctl_enter_secret ;;
  pkgcat)    _ctl_enter_pkgcat "$line" "$query" ;;
  pkgs)      _ctl_enter_pkgs "$line" ;;
  pkgderived)    _ctl_enter_pkgderived "$line" ;;
  pkgderivedsrc) _ctl_enter_pkgderivedsrc "$line" ;;
  *)         echo noop ;;
  esac
}

# _ctl_enter_pkgcat <line> [query] — drill into a category, or take a free-text
# package name. The universe of Arch packages is not enumerable, so a name
# outside the declared union arrives here rather than as a toggle.
_ctl_enter_pkgcat() {
  local line="$1" query="${2:-}" nav cat slot
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  slot="$(nav_get "$nav" slot)"
  case "$line" in
  "← Back") _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "+ Add package"*)
    _ctl_write_nav "$(nav_to_text "$cat" "packages.${slot}.extra" \
      "${slot} package")"
    echo render; return ;;
  esac
  # A typed name that matched no row still adds — same free-text affordance.
  if [[ -z "$line" && -n "$query" ]]; then
    _ctl_write_state \
      "$(_ctl_route_package_entry "$(_ctl_state)" "$query")"
    echo refresh; return
  fi
  _ctl_write_nav "$(nav_to_pkgs "$cat" "$slot" "${line%% ▸*}")"
  echo render
}

# _ctl_enter_pkgs <line> — toggle one package. Unchecking an INHERITED entry
# writes a packages.exclude entry (that is what makes the exclusion mechanism
# reachable from the menu at all); re-checking removes it. Unchecking a package
# this session added just drops it from the override.
_ctl_enter_pkgs() {
  local line="$1" nav cat slot pcat pkg
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  slot="$(nav_get "$nav" slot)"; pcat="$(nav_get "$nav" pkgcat)"
  [[ "$line" == "← Back" ]] && {
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return; }

  # strip the "[x] " / "[ ] " mark and any trailing override dot
  pkg="${line:4}"; pkg="${pkg%%  ●}"
  [[ -n "$pkg" ]] || { echo noop; return; }

  local state; state="$(_ctl_state)"
  if [[ "${line:0:3}" == "[x]" ]]; then
    # currently installed → remove it
    if _ctl_pkg_in_core "$slot" "$pcat" "$pkg"; then
      state="$(jq --arg p "$pkg" \
        '.packages.exclude = (((.packages.exclude // []) + [$p]) | unique)' \
        <<<"$state")"
    else
      state="$(jq --arg s "$slot" --arg k "$pcat" --arg p "$pkg" \
        'if .packages[$s][$k] then
           .packages[$s][$k] |= map(select(. != $p)) else . end' <<<"$state")"
    fi
  else
    # currently excluded or absent → put it back
    state="$(jq --arg p "$pkg" \
      'if .packages.exclude then
         .packages.exclude |= map(select(. != $p)) else . end
       | if (.packages.exclude // null) == [] then del(.packages.exclude)
         else . end' <<<"$state")"
    _ctl_pkg_in_core "$slot" "$pcat" "$pkg" || state="$(jq \
      --arg s "$slot" --arg k "$pcat" --arg p "$pkg" \
      '.packages[$s][$k] = (((.packages[$s][$k] // []) + [$p]) | unique)' \
      <<<"$state")"
  fi
  _ctl_write_state "$state"
  echo refresh
}

# _ctl_enter_pkgderived <line> — drill into one derived source. Nothing here is
# toggleable: these are consequences of choices made in Environment, Security
# and Backup, and ADR 0021 gives the DE adapter ownership of its own set.
_ctl_enter_pkgderived() {
  local line="$1" nav cat
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  [[ "$line" == "← Back" ]] && {
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return; }
  _ctl_write_nav "$(nav_to_pkgderivedsrc "$cat" "${line%% ▸*}")"
  echo render
}

# _ctl_enter_pkgderivedsrc <line> — Back only; every other row is read-only.
_ctl_enter_pkgderivedsrc() {
  [[ "$1" == "← Back" ]] && {
    _ctl_write_nav "$(nav_back "$(_ctl_nav)")"; echo render; return; }
  echo noop
}

# _ctl_open_secret <root|user> [name] — start inline masked entry: clear the typed
# buffer + any pending first entry, then render the secret screen (phase entry).
# The render directive turns masking on (rebind change, unbind cursor). Writes the
# directive to stdout like the other enter handlers.
_ctl_open_secret() {
  : > "${GUIDED_PWBUF_FILE:-/dev/null}"
  : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
  # The screen we open from IS the screen the capture returns to (ADR 0059):
  # carry the current nav as the secret's origin so both cancel and save land
  # back here, whether that is the Disks category, the Users list, or the
  # Encryption Editor — no per-target conditional.
  local nav; nav="$(_ctl_nav)"
  local cat; cat="$(nav_get "$nav" category)"
  _ctl_write_nav "$(nav_to_secret "$cat" "$1" "${2:-}" entry "$nav")"
  echo render
}

# _ctl_enter_secret — Enter on the masked screen: the typed value lives in the
# buffer file. Phase entry stashes it as pending and switches to confirm; phase
# confirm compares — a match writes the password to GUIDED_SECRETS_FILE and backs
# to the Users list, a mismatch notices and restarts entry. An empty first entry
# is refused (stay). Never echoes the value.
_ctl_enter_secret() {
  local nav cat tgt user phase origin buf pending
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  tgt="$(nav_get "$nav" target)"; user="$(nav_get "$nav" user)"
  phase="$(nav_get "$nav" phase)"
  # The return screen carried since open (ADR 0059); propagated across the
  # entry↔confirm phase rewrites so it survives to the save.
  origin="$(jq -c '.origin // empty' <<<"$nav")"
  buf="$(cat "${GUIDED_PWBUF_FILE:-/dev/null}" 2>/dev/null)"
  if [[ "$phase" != "confirm" ]]; then
    [[ -n "$buf" ]] || { echo "notice ⚠ password cannot be empty"; return; }
    # The encryption passphrase must be ≥ 8 (ZFS keyformat=passphrase minimum,
    # ADR 0054): reject a short first entry inline before it can fail at pool
    # creation. Passwords keep the non-empty-only rule.
    if [[ "$tgt" == "enc" && ${#buf} -lt 8 ]]; then
      echo "notice ⚠ passphrase must be 8+ chars"; return
    fi
    printf '%s' "$buf" > "${GUIDED_PWPENDING_FILE:-/dev/null}"
    : > "${GUIDED_PWBUF_FILE:-/dev/null}"
    _ctl_write_nav "$(nav_to_secret "$cat" "$tgt" "$user" confirm "$origin")"
    echo render; return
  fi
  pending="$(cat "${GUIDED_PWPENDING_FILE:-/dev/null}" 2>/dev/null)"
  if [[ "$buf" != "$pending" ]]; then
    : > "${GUIDED_PWBUF_FILE:-/dev/null}"; : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
    _ctl_write_nav "$(nav_to_secret "$cat" "$tgt" "$user" entry "$origin")"
    echo "secret-mismatch"; return
  fi
  case "$tgt" in
  user) guided_secretsfile_set_user "${GUIDED_SECRETS_FILE}" "$user" "$buf" ;;
  enc)  guided_secretsfile_set_enc  "${GUIDED_SECRETS_FILE}" "$buf" ;;
  *)    guided_secretsfile_set_root "${GUIDED_SECRETS_FILE}" "$buf" ;;
  esac
  : > "${GUIDED_PWBUF_FILE:-/dev/null}"; : > "${GUIDED_PWPENDING_FILE:-/dev/null}"
  # Return to the screen the capture was opened from — the same place Esc lands,
  # read from the carried origin (ADR 0059).
  _ctl_write_nav "$(nav_back "$nav")"
  echo render
}

# _ctl_user_committed_shell <name> — the committed User Profile's effective shell
# (merged over User Core), or the User Core default. The strict-delta baseline
# the editor compares an override against.
_ctl_user_committed_shell() {
  local s=""
  _ctl_user_is_committed "$1" \
    && s="$(load_user_profile "$1" 2>/dev/null | jq -r '.shell // empty' 2>/dev/null)"
  printf '%s' "${s:-$(_ctl_default_user_shell)}"
}

# _ctl_enter_useredit <line> — the User Editor dispatch (ADR 0051): toggle a
# committed user in/out of the install (enabled), cycle its shell into an
# install-scoped override (dropped when it lands on the committed shell — strict
# delta), or remove a session-created user. Shell/remove write the userforms file;
# enable/disable writes the Config State users list.
_ctl_enter_useredit() {
  local line="$1" nav cat un cur next
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"; un="$(nav_get "$nav" user)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "enabled:"*)
    _ctl_write_state "$(_ctl_toggle_users "$(_ctl_state)" "$(_ctl_baseline)" "$un")"
    echo refresh; return ;;
  "sudo:"*)
    [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || { echo refresh; return; }
    local _cs _ns _com
    _cs="$(jq -r 'if .sudo then true else false end' <<<"$(_ctl_user_effective "$un")")"
    _ns="$([[ "$_cs" == "true" ]] && echo false || echo true)"
    _com="$(jq -c 'if .sudo then true else false end' <<<"$(_ctl_user_committed "$un")")"
    _ctl_userform_set_strict "$un" sudo "$_ns" "$_com"
    echo refresh; return ;;
  "groups:"*)
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" groups groups)"
    echo render; return ;;
  "git name:"*)
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" git.name "git name")"
    echo render; return ;;
  "git email:"*)
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" git.email "git email")"
    echo render; return ;;
  "ssh keys:"*)
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" ssh "ssh keys")"
    echo render; return ;;
  "programs:"*)
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" programs programs)"
    echo render; return ;;
  "shell:"*)
    [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] || { echo refresh; return; }
    cur="$(_ctl_user_shell_full "$un")"
    next="$(_ctl_cycle_next "$cur" /bin/bash /bin/zsh /bin/fish)"
    if [[ "$next" == "$(_ctl_user_committed_shell "$un")" ]]; then
      guided_userform_unset "$GUIDED_USERFORMS_FILE" "$un" shell
    else
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$un" shell \
        "$(jq -n --arg x "$next" '$x')"
    fi
    echo refresh; return ;;
  "⧉ Clone this user")
    # Clone (ADR 0064): drop to a name-entry text screen carrying THIS user
    # as the source. A valid name copies the source's account-shape into a new
    # ad-hoc user and lands in its editor.
    _ctl_write_nav "$(nav_to_clone "$cat" "$un")"; echo render; return ;;
  "✗ remove user")
    # Session-created user: drop it from the install list and its held-aside form,
    # then return to the Users list.
    _ctl_write_state "$(cfgstate_set "$(_ctl_state)" users \
      "$(jq -c --arg u "$un" '(.users // []) - [$u]' \
        <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")")"
    [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
      && guided_userform_clear "$GUIDED_USERFORMS_FILE" "$un"
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  esac
  echo refresh
}

# _ctl_enter_userfield <line> [<query>] — the user-scoped sub-editor dispatch
# (ADR 0051): a multi field toggles membership (STAY), a git text commits the
# typed query and backs to the editor, the ssh list opens an add-key text screen
# and an add commits then re-lists so more keys can follow.
_ctl_enter_userfield() {
  local line="$1" query="${2:-}" nav cat un field
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  un="$(nav_get "$nav" user)"; field="$(nav_get "$nav" field)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  case "$(_ctl_userfield_kind "$field")" in
  multi)
    _ctl_userfield_toggle_multi "$un" "$field" "${line:4}"
    echo refresh; return ;;
  text)
    if [[ "$field" == git.* ]]; then
      [[ -n "$query" ]] && _ctl_userfield_set_git "$un" "${field#git.}" "$query"
      _ctl_write_nav "$(nav_to_useredit "$cat" "$un")"; echo render; return
    fi
    # ssh.add: append the key, then return to the key list for more.
    [[ -n "$query" ]] && _ctl_userfield_add_ssh "$un" "$query"
    _ctl_write_nav "$(nav_to_userfield "$cat" "$un" ssh "ssh keys")"
    echo render; return ;;
  list)
    [[ "$line" == "+ Add"* ]] && {
      _ctl_write_nav "$(nav_to_userfield "$cat" "$un" ssh.add "ssh key")"
      echo render; return; }
    echo refresh; return ;;   # an existing key row is display-only
  esac
  echo refresh
}

# _ctl_proceed_directive — the in-menu Proceed action (ADR 0055). Proceed is
# NEVER gated on a secret: root, every user, and the encryption passphrase
# default to 12345 (filled by the manifest builder), so install always runs. The
# always-on WILL ERASE / typed-INSTALL consent (back-end) remains the real guard.
# Any unset secret is surfaced as `default 12345` on the Users screen, not here.
_ctl_proceed_directive() {
  local state; state="$(_ctl_state)"
  # Manual Partitioning (ADR 0073): refuse to Proceed on an out-of-bounds layout
  # (missing root/ESP, an unsupported filesystem or mountpoint). The full list
  # of problems is shown live on the Partitions screen; this just blocks Proceed
  # with a header notice. The back-end validator is the ultimate hard stop.
  if manual_kind_active "$state"; then
    local _p; _p="$(cfgstate_get "$state" disk_config.partitions)"
    manual_partition_problems "${_p:-[]}" >/dev/null || {
      echo "notice Manual layout not installable — fix it on Partitions ▸"
      return
    }
  fi
  echo "terminal proceed"
}

_ctl_enter_top() {
  local line="$1" cat
  case "$line" in
  "$_CTL_DIVIDER")  echo noop ;;
  "Profiles ▸"*)    _ctl_write_nav "$(nav_to_profiles)"; echo render ;;
  "Proceed"*)       _ctl_proceed_directive ;;
  "Save profile"*)  echo "terminal save" ;;
  "Export config"*) echo "terminal export" ;;
  "Abort"*)         echo abort ;;
  *)
    # The top row is "<name> — <summary>"; split on the em-dash so multi-word
    # category names (e.g. "Mirrors & Repositories") survive whole (ADR 0071).
    # Validity is read from menu_categories (the single source of truth), so a
    # new category needs no edit here.
    cat="${line%% — *}"
    if [[ "$cat" == "Users" ]]; then
      # Flatten (slice 01): Users opens its list directly, skipping the
      # single-row category screen. nav_back from here returns to top.
      _ctl_write_nav "$(nav_to_values Users users users)"; echo render
    elif menu_categories "$(_ctl_state)" "$(_ctl_baseline)" \
         | jq -e --arg c "$cat" 'any(.[]; .name == $c)' >/dev/null 2>&1; then
      _ctl_write_nav "$(nav_to_category "$cat")"; echo render
    else
      echo noop
    fi ;;
  esac
}

# _ctl_enter_profiles <line> — Enter on the Profiles screen (ADR 0055). `← Back`
# returns to the top screen unchanged. A profile row SEEDS the menu: the chosen
# hosts/<name>/profile.jsonc is parsed and merged over the current Config State
# (profiles_seed — profile wins, devices flattened), so every category reflects
# it, then nav returns to the top screen for tweak-or-Proceed. A profile that
# fails to parse leaves the state untouched and warns via a notice.
_ctl_enter_profiles() {
  local line="$1" nav f profile
  nav="$(_ctl_nav)"
  if [[ "$line" == "← Back" ]]; then
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return
  fi
  # `↺ Reset to blank` (ADR 0063): a full session reset is destructive,
  # so drill into a confirm screen rather than resetting on the spot.
  if [[ "$line" == "↺ Reset to blank"* ]]; then
    _ctl_write_nav "$(nav_to_newhost)"; echo render; return
  fi
  f="$(_ctl_hosts_root)/${line}/profile.jsonc"
  if ! profile="$(_configs_parse "$f" 2>/dev/null)"; then
    echo "notice ⚠ Could not read profile '${line}'"; return
  fi
  # Seed the RESOLVED profile, not the raw delta. A committed profile is a
  # delta over Host Core, and the Config State is an override map that
  # REPLACES baseline values — so seeding the delta verbatim would show (and
  # install) `host_programs: ["grub"]` where `install.sh --profile desktop`
  # installs `["cups","grub"]`. Resolving here means one profile produces one
  # install through every front-end.
  profile="$(layer_resolve host "$(cfgstate_host_core)" "$profile")"
  _ctl_write_state "$(profiles_seed "$(_ctl_state)" "$profile")"
  _ctl_write_nav '{"screen":"top"}'
  echo render
}

# _ctl_session_stash — snapshot the pre-reset session side-state (per-user
# editor forms + the password/secret manifest) into GUIDED_SESSION_UNDO_FILE, so
# a single undo after a `+ New host` reset can restore it. The Config State is
# already undoable through the history stack; this covers only the two side
# files the stack does not. No-op when no undo file is wired (non-persistent).
_ctl_session_stash() {
  [[ -n "${GUIDED_SESSION_UNDO_FILE:-}" ]] || return 0
  local uf='{}' sf='{}'
  [[ -s "${GUIDED_USERFORMS_FILE:-}" ]] && uf="$(<"$GUIDED_USERFORMS_FILE")"
  [[ -s "${GUIDED_SECRETS_FILE:-}" ]] && sf="$(<"$GUIDED_SECRETS_FILE")"
  jq -n --argjson u "$uf" --argjson s "$sf" '{userforms:$u, secrets:$s}' \
    >"$GUIDED_SESSION_UNDO_FILE"
}

# _ctl_session_unstash — restore the userforms + secrets files from the stash
# and drop it. Called by the first undo after a `+ New host` reset. No-op when
# the stash is absent/empty (nothing to restore).
_ctl_session_unstash() {
  [[ -s "${GUIDED_SESSION_UNDO_FILE:-/nonexistent}" ]] || return 0
  local b; b="$(<"$GUIDED_SESSION_UNDO_FILE")"
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && jq -c '.userforms // {}' <<<"$b" >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] \
    && jq -c '.secrets // {}' <<<"$b" >"$GUIDED_SECRETS_FILE"
  rm -f "$GUIDED_SESSION_UNDO_FILE"
}

# _ctl_newhost_reset — the `+ New host` full session reset (ADR 0063). Broader
# than Reset-all (which clears Config State only): it returns Config State to
# the Host Core baseline (a `{}` override map — like ^R, and recorded on the
# undo stack) AND clears the session-created users' editor forms and the secret
# / password manifest overrides (the in-menu disk bindings live in Config State,
# so the `{}` reset drops them too). The side files are stashed first, so a
# single undo restores the whole pre-reset session.
_ctl_newhost_reset() {
  _ctl_session_stash
  if [[ -f "${GUIDED_HIST_FILE:-/nonexistent}" ]]; then
    local hist; hist="$(<"$GUIDED_HIST_FILE")"
    hist="$(hist_commit "$hist" '{}')"
    printf '%s\n' "$hist" >"$GUIDED_HIST_FILE"
    _ctl_write_state "$(hist_present "$hist")"
  else
    _ctl_write_state '{}'
  fi
  [[ -n "${GUIDED_USERFORMS_FILE:-}" ]] \
    && printf '{}\n' >"$GUIDED_USERFORMS_FILE"
  [[ -n "${GUIDED_SECRETS_FILE:-}" ]] && printf '{}\n' >"$GUIDED_SECRETS_FILE"
}

# _ctl_enter_newhost <line> — the `+ New host` confirm screen (ADR 0063): the
# confirm row runs the full session reset and returns to a blank top screen; any
# other row (← Back) cancels back to the picker, session work intact.
# _ctl_manual_set <state> <device> <field> <value> → state with one field of the
# partition <device> changed (via the pure manual_set_field), re-stored under
# disk_config.partitions. The single write path the assignment editor uses.
_ctl_manual_set() {
  local st="$1" dev="$2" field="$3" val="$4" parts
  parts="$(cfgstate_get "$st" disk_config.partitions)"
  manual_store_partitions "$st" \
    "$(manual_set_field "${parts:-[]}" "$dev" "$field" "$val")"
}

# _ctl_manual_field <state> <device> <field> → the current value of <field> on
# the partition <device> (empty when unset).
_ctl_manual_field() {
  jq -r --arg d "$2" --arg f "$3" '
    (.disk_config.partitions // [])[]
    | select(.device == $d) | (.[$f] // "")
  ' <<< "$1"
}

# _ctl_enter_manualparts <line> — the assignment table: the cfdisk hand-off
# action, then one row per partition (opens its editor). cfdisk is gated in
# --debug (ADR 0063: inspect-only, no disk touched).
_ctl_enter_manualparts() {
  local line="$1" nav cat; nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back") _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "⟳ Run cfdisk"*)
    [[ "${INSTALL_DEBUG:-0}" == "1" ]] \
      && { echo 'notice cfdisk is disabled in --debug — no disk is touched'
           return; }
    echo cfdisk; return ;;
  "/dev/"*)
    local dev="${line%%  *}"
    _ctl_write_nav "$(nav_to_partedit "$cat" "$dev")"; echo render; return ;;
  *) echo noop ;;
  esac
}

# _ctl_enter_partedit <line> — the per-partition editor: Enter cycles the
# mountpoint / filesystem, or toggles format. Only supported filesystems and
# mountpoints are offered, so the editor can never author an out-of-bounds value
# (the validator is the ultimate guard for anything hand-crafted).
_ctl_enter_partedit() {
  local line="$1" nav dev st cur nxt
  nav="$(_ctl_nav)"; dev="$(nav_get "$nav" device)"; st="$(_ctl_state)"
  case "$line" in
  "← Back") _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "mountpoint:"*)
    cur="$(_ctl_manual_field "$st" "$dev" mountpoint)"
    nxt="$(manual_cycle_mountpoint "$cur")"
    _ctl_write_state "$(_ctl_manual_set "$st" "$dev" mountpoint "$nxt")"
    echo refresh; return ;;
  "filesystem:"*)
    cur="$(_ctl_manual_field "$st" "$dev" fs)"
    nxt="$(manual_cycle_fs "$cur")"
    _ctl_write_state "$(_ctl_manual_set "$st" "$dev" fs "$nxt")"
    echo refresh; return ;;
  "format:"*)
    cur="$(_ctl_manual_field "$st" "$dev" format)"
    [[ "$cur" == "true" ]] && nxt=false || nxt=true
    _ctl_write_state "$(_ctl_manual_set "$st" "$dev" format "$nxt")"
    echo refresh; return ;;
  *) echo noop ;;
  esac
}

_ctl_enter_newhost() {
  local line="$1" nav; nav="$(_ctl_nav)"
  case "$line" in
  "Yes"*)
    _ctl_newhost_reset
    _ctl_write_nav '{"screen":"top"}'
    echo render ;;
  *)
    _ctl_write_nav "$(nav_back "$nav")"; echo render ;;
  esac
}

# _ctl_enter_rooteditor <line> — the Root Editor dispatch (ADR 0063): open the
# masked password capture (rich fzf) or its execute() fallback (older fzf), or
# cycle root's login shell into options.root_shell (strict delta — landing on
# the baseline shell drops the override, like the per-user cycle). Storage is
# unchanged from the old root rows; only the surface moved behind this editor.
_ctl_enter_rooteditor() {
  local line="$1" nav; nav="$(_ctl_nav)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "password:"*)
    if _ctl_rich_chrome; then _ctl_open_secret root; else echo "secret-root"; fi
    return ;;
  "shell:"*)
    local _rc _rn
    _rc="$(_ctl_root_shell_full)"
    _rn="$(_ctl_cycle_next "$_rc" /bin/bash /bin/zsh /bin/fish)"
    if [[ "$_rn" == "$(_ctl_root_shell_committed)" ]]; then
      _ctl_write_state "$(cfgstate_unset "$(_ctl_state)" options.root_shell)"
    else
      _ctl_write_state \
        "$(edit_set_scalar "$(_ctl_state)" options.root_shell "$_rn")"
    fi
    echo refresh; return ;;
  esac
  echo refresh
}

_ctl_enter_category() {
  local line="$1" nav cat label path
  nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "Layout:"*)   # display_label "layout"
    # Manual Partitioning locks the pool-dependent Disks sub-editors (ADR 0073):
    # opening the layout editor is a no-op while it is on.
    manual_kind_active "$(_ctl_state)" && { echo render; return; }
    _ctl_write_nav "$(nav_to_values "$cat" __layout__ "layout")"
    echo render; return ;;
  "Manual partitioning:"*)   # on/off toggle over disk_config.kind (ADR 0073)
    local _mst _mcur _mnew
    _mst="$(_ctl_state)"; _mcur="$(cfgstate_get "$_mst" disk_config.kind)"
    [[ "$_mcur" == "manual" ]] && _mnew=auto || _mnew=manual
    _ctl_write_state "$(_ctl_apply_enum "$_mst" disk_config.kind "$_mnew")"
    # Turning it on: reload + a header notice pointing at the Partitions row.
    [[ "$_mnew" == "manual" ]] && { echo manual-on; return; }
    echo refresh; return ;;
  "Partitions ▸"*)   # Manual Partitioning: open the assignment table (ADR 0073)
    _ctl_write_nav "$(nav_to_manualparts "$cat")"; echo render; return ;;
  "Swap:"*)     # display_label "swap"
    manual_kind_active "$(_ctl_state)" && { echo render; return; }
    _ctl_write_nav "$(nav_to_swapedit "$cat")"; echo render; return ;;
  "Root disk:"*)   # display_label "root disk"
    _ctl_write_nav "$(nav_to_rootdisk "$cat")"; echo render; return ;;
  "Encryption ▸"*)   # the collapsed Disks encryption row (ADR 0059)
    manual_kind_active "$(_ctl_state)" && { echo render; return; }
    _ctl_write_nav "$(nav_to_encryption "$cat")"; echo render; return ;;
  "Impermanence ▸"*)   # the collapsed Disks impermanence row (ADR 0066)
    manual_kind_active "$(_ctl_state)" && { echo render; return; }
    _ctl_write_nav "$(nav_to_impermanence "$cat")"; echo render; return ;;
  "repo ▸"* | "aur ▸"*)
    _ctl_write_nav "$(nav_to_pkgcat "$cat" "${line%% *}")"
    echo render; return ;;
  "derived ▸"*)
    _ctl_write_nav "$(nav_to_pkgderived "$cat")"; echo render; return ;;
  esac
  label="${line%%:*}"
  path="$(_ctl_field_for_label "$cat" "$label")"
  [[ -n "$path" ]] || { echo noop; return; }
  # A Cycle Field (bare bool) flips in place and stays on the category screen —
  # no values submenu (ADR 0075). Read the EFFECTIVE value (a default-true bool
  # with no override must read true), flip it through the strict-delta apply so
  # landing back on the default clears the override; a Manual-Partitioning-locked
  # field is a silent no-op (the apply guard returns the state unchanged).
  if _ctl_is_cycle_field "$path"; then
    local _cur _next _new
    _cur="$(menu_render_value \
      "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" "$path")"
    [[ "$_cur" == true ]] && _next=false || _next=true
    if _new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$_next")"; then
      _ctl_write_state "$(_ctl_normalise_default "$_new" "$path")"
    fi
    echo refresh; return
  fi
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
    local _tval="${line:4}"   # strip the "[x] "/"[ ] " mark
    # Value-formattable toggles render options through the formatter, so map the
    # displayed option back to its stored (lower-case) value before flipping.
    if _ctl_display_values "$path"; then
      local -a _opts; mapfile -t _opts < <(_ctl_toggle_options "$path")
      _tval="$(display_reverse "$_tval" "${_opts[@]}")" || _tval="${line:4}"
    fi
    _ctl_write_state "$(_ctl_normalise_default "$(_ctl_toggle_multi \
      "$(_ctl_state)" "$(_ctl_baseline)" "$path" "$_tval")" "$path")"
    echo refresh; return
  fi
  if [[ "$path" == "sysctl" ]]; then
    if [[ "$line" == "+ Add"* ]]; then
      _ctl_write_nav "$(nav_to_text "$(nav_get "$nav" category)" sysctl sysctl)"
      echo render; return
    fi
    echo refresh; return   # an existing pair is display-only (re-list in place)
  fi
  # Custom mirror servers / custom repositories (ADR 0072): "+ Add" opens the
  # text editor; an existing entry is display-only (re-list in place).
  if [[ "$path" == "options.mirror_servers" \
        || "$path" == "options.custom_repositories" ]]; then
    if [[ "$line" == "+ Add"* ]]; then
      _ctl_write_nav \
        "$(nav_to_text "$(nav_get "$nav" category)" "$path" "$path")"
      echo render; return
    fi
    echo refresh; return
  fi
  if [[ "$path" == "users" ]]; then
    # The merged root row (ADR 0063) opens the Root Editor (password + shell),
    # symmetric with a user row opening its User Editor. Handle it before the
    # toggle / user-row logic (its line is "root — <shell> · pw <tag>").
    if [[ "$line" == "root — "* ]]; then
      _ctl_write_nav "$(nav_to_rooteditor "$(nav_get "$nav" category)")"
      echo render; return
    fi
    # Per-user credential rows: on a capable fzf (rich chrome ≥ 0.62) enter the
    # inline masked screen (ADR 0051); on an older fzf fall back to the
    # execute() masked prompt (ADR 0049). Handle before the toggle logic.
    if [[ "$line" == *"password ("* ]]; then
      local _sn="${line#*password (}"; _sn="${_sn%%)*}"
      if _ctl_rich_chrome; then _ctl_open_secret user "$_sn"
      else echo "secret-user $_sn"; fi
      return
    fi
    if [[ "$line" == "+ Create"* ]]; then
      _ctl_write_nav \
        "$(nav_to_text "$(nav_get "$nav" category)" __newuser__ "new user")"
      echo render; return
    fi
    # A user row opens its User Editor (ADR 0051): enable/disable + shell (and the
    # richer fields in slice 03) live there, not on the list. The row is
    # "name — shell · pw …" (enabled) or "name — disabled", so the name is the
    # text before the " — " separator.
    local _uname="${line%% — *}"
    _ctl_write_nav "$(nav_to_useredit "$(nav_get "$nav" category)" "$_uname")"
    echo render; return
  fi
  if [[ "$(_ctl_field_kind "$path")" == "biglist" ]]; then
    # a big filterable list → set the picked value, then back. The locale
    # projections recompose the canonical system.locale (ADR 0076); every other
    # biglist sets its own scalar path. Both normalise against their real path.
    case "$path" in
    __language__ | __encoding__)
      _ctl_write_state "$(_ctl_normalise_default \
        "$(_ctl_apply_locale_part "$(_ctl_state)" "$path" "$line")" system.locale)" ;;
    system.console_font)
      # Reject a font not installed on the medium (ADR 0076): an off-list value is
      # only ever a typo that breaks the console at boot. Stay on the screen.
      locale_list_console_fonts | grep -qxF "$line" || { echo noop; return; }
      _ctl_write_state "$(_ctl_normalise_default \
        "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")" "$path")" ;;
    *)
      _ctl_write_state "$(_ctl_normalise_default \
        "$(edit_set_scalar "$(_ctl_state)" "$path" "$line")" "$path")" ;;
    esac
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
    if [[ "$line" == "custom…" ]]; then
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
  local _eval="$line"
  # Value-formattable enums render options through the formatter; reverse-map
  # the picked display string back to its stored value.
  if _ctl_display_values "$path"; then
    local -a _eopts; mapfile -t _eopts < <(_ctl_enum_options "$path")
    _eval="$(display_reverse "$line" "${_eopts[@]}")" || _eval="$line"
  fi
  if new="$(_ctl_apply_enum "$(_ctl_state)" "$path" "$_eval")"; then
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
  # Create user (ADR 0051): a typed name that isn't a duplicate is added to the
  # user list, seeded with the create defaults (bash / sudo on / wheel) in its
  # install-scoped form, and the operator is dropped INTO the editor to set the
  # required password and anything else. A blank name backs out; a duplicate
  # (committed or already listed) is refused with a notice.
  if [[ "$path" == "__newuser__" ]]; then
    [[ -n "$query" ]] || { _ctl_write_nav "$(nav_to_values "$cat" users users)"
                           echo render; return; }
    if _ctl_user_is_committed "$query" || jq -e --arg v "$query" \
        '(.users // []) | any(. == $v)' \
        <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" >/dev/null; then
      echo "notice ⚠ user '${query}' already exists — pick another name"; return
    fi
    _ctl_write_state "$(cfgstate_set "$(_ctl_state)" users \
      "$(jq -cn --arg v "$query" --argjson a \
        "$(jq -c '.users // []' \
          <<<"$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")")" '$a + [$v]')")"
    if [[ -n "${GUIDED_USERFORMS_FILE:-}" ]]; then
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" shell \
        "$(jq -Rn --arg s "$(_ctl_default_user_shell)" '$s')"
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" sudo 'true'
      guided_userform_set "$GUIDED_USERFORMS_FILE" "$query" groups '["wheel"]'
    fi
    _ctl_write_nav "$(nav_to_useredit "$cat" "$query")"; echo render; return
  fi
  # Clone user (ADR 0064): like create, but the new name is seeded with the
  # SOURCE user's account-shape (carried on the nav). Same blank-backs-out and
  # duplicate-refused rules, then drop INTO the clone's editor to set the pw.
  if [[ "$path" == "__cloneuser__" ]]; then
    local _src _eff; _src="$(nav_get "$nav" user)"
    _eff="$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    [[ -n "$query" ]] || { _ctl_write_nav "$(nav_to_values "$cat" users users)"
                           echo render; return; }
    if _ctl_user_is_committed "$query" || jq -e --arg v "$query" \
        '(.users // []) | any(. == $v)' <<<"$_eff" >/dev/null; then
      echo "notice ⚠ user '${query}' already exists — pick another name"; return
    fi
    _ctl_write_state "$(cfgstate_set "$(_ctl_state)" users \
      "$(jq -cn --arg v "$query" --argjson a "$(jq -c '.users // []' \
        <<<"$_eff")" '$a + [$v]')")"
    _ctl_clone_seed "$_src" "$query"
    _ctl_write_nav "$(nav_to_useredit "$cat" "$query")"; echo render; return
  fi
  [[ -n "$query" ]] \
    && _ctl_write_state "$(_ctl_normalise_default \
         "$(_ctl_apply_text "$(_ctl_state)" "$path" "$query")" "$path")"
  # sysctl / create-user / persist came from a list or sub-editor screen, so
  # return there (the new entry shows, more can be added); every other text
  # field backs out.
  case "$path" in
  sysctl)            _ctl_write_nav "$(nav_to_values "$cat" sysctl sysctl)" ;;
  options.mirror_servers)
    _ctl_write_nav "$(nav_to_values "$cat" options.mirror_servers \
      "custom servers")" ;;
  options.custom_repositories)
    _ctl_write_nav "$(nav_to_values "$cat" options.custom_repositories \
      "custom repositories")" ;;
  __newuser__)       _ctl_write_nav "$(nav_to_values "$cat" users users)" ;;
  __persist__)       _ctl_write_nav "$(nav_to_impermanence "$cat")" ;;
  options.swap_size) _ctl_write_nav "$(nav_to_swapedit "$cat")" ;;
  *)                 _ctl_write_nav "$(nav_back "$nav")" ;;
  esac
  echo render
}

# _ctl_enter_swapedit <line> — the swap sub-editor: toggle swap on/off, toggle
# zswap, cycle the zswap compressor (zstd→lz4→lzo) and max pool % (5→…→60), or
# open the free-text size editor. Toggles/cycles STAY on the screen (refresh);
# size opens the text screen (which returns here — see _ctl_enter_text).
# _ctl_enter_encryption <line> — the Encryption Editor (ADR 0059): flip the
# enablement toggle in place (strict delta — landing back on the baseline drops
# the override), or drop the passphrase row into the shared masked capture (rich
# fzf enters the masked screen; older fzf falls back to the execute() prompt).
# The capture carries this screen as its origin, so a confirmed passphrase
# returns here. Setting a passphrase never touches the toggle.
_ctl_enter_encryption() {
  local line="$1" nav; nav="$(_ctl_nav)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "enabled:"*)
    # flip options.encryption; has() keeps an explicit value from being read as
    # the default (false). Normalise so toggling back to the baseline (off)
    # leaves no override, exactly like the values-screen edit.
    local _flipped
    _flipped="$(jq '
      (if (.options // {} | has("encryption")) then .options.encryption
       else false end) as $c
      | .options.encryption = ($c | not)' <<<"$(_ctl_state)")"
    _ctl_write_state "$(_ctl_normalise_default "$_flipped" options.encryption)"
    echo refresh; return ;;
  "password:"*)
    if _ctl_rich_chrome; then _ctl_open_secret enc; else echo "secret-enc"; fi
    return ;;
  esac
  echo refresh
}

# _ctl_enter_impermanence <line> — the Impermanence Editor dispatch (ADR 0066):
# flip options.impermanence.enabled in place (strict delta — landing on the
# baseline drops the override, like the encryption toggle) or open the
# __persist__ add-a-directory text screen. The read-only curated-defaults row
# is inert. Modelled on the encryption sub-editor.
_ctl_enter_impermanence() {
  local line="$1" nav cat; nav="$(_ctl_nav)"; cat="$(nav_get "$nav" category)"
  case "$line" in
  "← Back")
    _ctl_write_nav "$(nav_back "$nav")"; echo render; return ;;
  "enabled:"*)
    local _flipped
    _flipped="$(jq '
      (if (.options.impermanence // {} | has("enabled"))
       then .options.impermanence.enabled else false end) as $c
      | .options.impermanence.enabled = ($c | not)' <<<"$(_ctl_state)")"
    _ctl_write_state \
      "$(_ctl_normalise_default "$_flipped" options.impermanence.enabled)"
    echo refresh; return ;;
  "Add persist"*)
    _ctl_write_nav "$(nav_to_text "$cat" __persist__ "persist dir")"
    echo render; return ;;
  "curated defaults:"*)
    echo refresh; return ;;   # read-only summary line
  esac
  # Any other row is a user-added persist directory (ADR 0066): drop it. A stray
  # line that isn't in the list is a harmless no-op (edit returns it unchanged).
  _ctl_write_state "$(edit_remove_persist "$(_ctl_state)" "$line" || true)"
  echo refresh
}

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
    impermanence)
      # Add persist — the editor's ^A accelerator (ADR 0066). Only meaningful
      # with impermanence on (the add row only renders then; else noop).
      if [[ "$(cfgstate_get \
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
  manualparts) printf ' Guided ▸ %s ▸ partitions ' "$cat" ;;
  partedit)    printf ' Guided ▸ %s ▸ partition ' "$cat" ;;
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
  case "$(nav_screen "$nav")" in
  pooledit | pooldisks)
    eff="$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")"
    jq -r --arg k "$(_ctl_pool_kind "$nav")" \
      '. as $g | "\($g.name // $g.pool_name // "pool") · \($g.topology // "?") · "
       + (if ($g.devices // null) != null
          then "\($g.devices | length) bound"
          else "\($g.disk_count // "?") disks" end)' \
      <<<"$(_ctl_pool_get "$eff" "$(_ctl_pool_kind "$nav")" \
            "$(nav_get "$nav" index)")" ;;
  *)
    # The OS layout label belongs to the Disks context only — printed on every
    # screen's footer it read as a stray "single disk" on Locales/Kernels/etc.
    [[ "$(nav_get "$nav" category)" == "Disks" ]] || return 0
    _ctl_layout_label "$(_ctl_effective "$(_ctl_state)" "$(_ctl_baseline)")" ;;
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
  local sum; sum="$(_ctl_footer_summary "$nav")"
  if [[ -n "$sum" ]]; then printf '%s   │   %s' "$acts" "$sum"
  else printf '%s' "$acts"; fi
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
  # A fresh edit voids the `+ New host` reset-undo stash: its side-state no
  # longer matches the current session, so a later undo must not resurrect it.
  rm -f "${GUIDED_SESSION_UNDO_FILE:-/nonexistent}"
}

# _ctl_nav_reconcile <nav> <state> → a nav still valid for <state>. A history op
# (reset/undo/redo) can invalidate the screen the nav sits on: it can delete the
# pool a pooledit/pooldisks nav addresses (rendering "?" for the gone group), or
# drop the layout back to single-disk while the multi-only datapools editor is
# open (the OS pool row vanishes). Reset from inside the custom editor was the
# reported case. When the current screen no longer fits the state, this backs the
# nav out to its category; any other nav is returned unchanged.
_ctl_nav_reconcile() {
  local nav="$1" state="$2" screen kind i exists
  screen="$(nav_screen "$nav")"
  case "$screen" in
  datapools)
    # The unified layout editor only makes sense for a multi layout; after a
    # reset to the single-disk default it would show only the add rows, so back
    # out to the category (which shows the default "layout: single disk").
    if [[ "$(jq -r '.mode // "single"' <<<"$state")" == "multi" ]]; then
      printf '%s' "$nav"
    else nav_to_category "$(nav_get "$nav" category)"; fi
    return ;;
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
  ctrl-z) hist="$(hist_undo "$hist")"
          # The first undo after a `+ New host` reset also restores the stashed
          # userforms + secrets (the side-state the Config-State stack omits).
          _ctl_session_unstash ;;
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
# _ctl_reload_cmd <entry> — the reload command for a re-render. Fast path
# (ticket 04): precompute the current screen's list into GUIDED_LIST_FILE and
# `cat` it — one cheap fork instead of a second bash that re-sources the whole
# controller. Falls back to the bash re-render when no list file is wired (bats
# / non-persistent contexts), so behaviour is identical either way.
_ctl_reload_cmd() {
  local entry="$1"
  if [[ -n "${GUIDED_LIST_FILE:-}" ]]; then
    guided_ctl_list >"$GUIDED_LIST_FILE" 2>/dev/null
    printf 'cat %q' "$GUIDED_LIST_FILE"
  else
    printf 'bash %q list' "$entry"
  fi
}

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
    top | category | values | text)   # the always-on master-detail pane (0071)
      _showpv=1 ;;
    datapools | pooledit) _showpv=1 ;;   # the live layout graph
    profiles) _showpv=1 ;;               # the profile's header comment
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
    # Inline masking (ADR 0051): the password screen turns the change→mask bind on
    # and disables query-cursor movement so the buffer diff can never desync; every
    # other screen turns masking off and restores the cursor keys. rebind/unbind of
    # an already-(un)bound key/event is harmless, so this is safe on all renders.
    local mask
    if [[ "$(nav_screen "$nav")" == "secret" ]]; then
      mask='+rebind(change)+unbind(left)+unbind(right)+unbind(home)+unbind(end)'
    else
      mask='+unbind(change)+rebind(left)+rebind(right)+rebind(home)+rebind(end)'
    fi
    printf 'clear-query+reload(%s)+change-header(%s)+change-prompt(%s)%s%s%s' \
      "$(_ctl_reload_cmd "$entry")" "$(_ctl_nav_header "$nav")" \
      "$(_ctl_nav_prompt "$nav")" "$pv" "$chrome" "$mask" ;;
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
    printf 'reload-sync(%s)+refresh-preview%s' "$(_ctl_reload_cmd "$entry")" \
      "$rfoot" ;;
  abort)            printf 'abort' ;;
  noop)             printf 'ignore' ;;
  "terminal "*)     printf 'execute-silent(printf %%s %q > %q)+accept' \
                      "${d#terminal }" "${GUIDED_RESULT_FILE:-/dev/null}" ;;
  "edit-oneshot "*) printf \
                      'execute(bash %q oneshot %q)+clear-query+reload(bash %q list)' \
                      "$entry" "${d#edit-oneshot }" "$entry" ;;
  "secret-root")
    printf 'execute(bash %q secret root)+clear-query+reload(bash %q list)' \
      "$entry" "$entry" ;;
  "secret-user "*)
    printf 'execute(bash %q secret user %q)+clear-query+reload(bash %q list)' \
      "$entry" "${d#secret-user }" "$entry" ;;
  "secret-enc")
    printf 'execute(bash %q secret enc)+clear-query+reload(bash %q list)' \
      "$entry" "$entry" ;;
  "notice "*)       printf 'change-header(%s)+bell' "${d#notice }" ;;
  manual-on)
    # Reload the Disks screen (locked fields greyed, Partitions row shown) and
    # point the operator at the cfdisk hand-off (ADR 0073).
    printf 'reload(%s)+change-header(%s)+bell' "$(_ctl_reload_cmd "$entry")" \
      'Manual: pool features off — open Partitions ▸ to run cfdisk' ;;
  cfdisk)
    # Suspend fzf, run cfdisk on the target disk, scan + store the assignment,
    # then reload so the Partitions row shows the new count (ADR 0073).
    printf 'execute(bash %q cfdisk)+clear-query+reload(%s)' \
      "$entry" "$(_ctl_reload_cmd "$entry")" ;;
  "secret-mismatch")
    # Re-render the (now entry-phase) masked screen with a warning header, query
    # cleared, masking + cursor-lock kept on. Distinct from `render` only in the
    # header text and the bell.
    printf 'clear-query+reload(%s)+change-header(%s)+change-prompt(password> )+rebind(change)+unbind(left)+unbind(right)+unbind(home)+unbind(end)+bell' \
      "$(_ctl_reload_cmd "$entry")" \
      '⚠ passwords did not match — type it again   ·   Esc cancels' ;;
  *)                printf 'ignore' ;;
  esac
}
