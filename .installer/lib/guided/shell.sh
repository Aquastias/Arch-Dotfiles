#!/usr/bin/env bash
# =============================================================================
# lib/guided/shell.sh — Guided Installer fzf shell (ADR 0039)
# =============================================================================
# The only impure module of the Guided Installer: it renders menus, reads the
# operator's choices, and dispatches to the pure cores (Config State, Emitter,
# Menu model). It holds no decision logic — every value flows through the pure
# layer, and the assembled Effective Config is the same artifact the back-end
# and VM suite already cover.
#
# Selection seam — the shell selects ONLY through these:
#   guided_prompt <key> <prompt>            free-text (read, or replay)
#   guided_select <key> <prompt> <opt...>   enumerable pick (fzf, or replay)
#   guided_pick_disk [<key>]                disk pick w/ picker preview, or
#                                           replay
# Interactively they render fzf / a typed prompt; under a replay answers file
# (guided_load_replay, set by `install.sh --guided <file>`) each returns the
# scripted answer by key — no fzf, no tty. This is the seam a headless harness
# (issue 01b) drives.
#
# guided_build → the device-baked Effective Config on stdout. The review screen
# + typed INSTALL are the single consent gate; the caller (install.sh) runs the
# back-end `--unattended`.
#
# Used by: install.sh (--guided), tools/guided-preview.sh.
# =============================================================================

# shellcheck source=../common.sh
declare -F error >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"
# shellcheck source=../config/config-state.sh
declare -F config_state_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-state.sh"
# shellcheck source=../config/config-store.sh
declare -F config_store_state >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/config-store.sh"
# shellcheck source=../config/layer-resolver.sh
declare -F layer_resolver_resolve >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/layer-resolver.sh"
# shellcheck source=../config/edit.sh
declare -F edit_set_scalar >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/edit.sh"
# shellcheck source=../config/emit.sh
declare -F emit_effective >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/emit.sh"
# shellcheck source=../config/menu.sh
declare -F menu_rows >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/menu.sh"
# shellcheck source=../config/history.sh
declare -F history_new >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/history.sh"
# shellcheck source=../config/skeleton.sh
declare -F skeleton_preset >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/skeleton.sh"
# shellcheck source=../config/manual-partition.sh
declare -F manual_partition_scan_and_store >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/manual-partition.sh"
# shellcheck source=../picker.sh
declare -F picker_enum_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../picker.sh"
# shellcheck source=../live-medium.sh
declare -F live_medium_disks >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../live-medium.sh"
# shellcheck source=secrets.sh
declare -F guided_write_passwords >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/secrets.sh"
# shellcheck source=save.sh
declare -F guided_save_host_profile >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/save.sh"
# shellcheck source=controller.sh
declare -F guided_controller_list >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/controller.sh"
# shellcheck source=../prompt.sh
declare -F prompt_secret >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../prompt.sh"

# The shell's parts: session state + edits, options, users, the persistent fzf
# front-end.
_GUIDED_SHELL_DIRECTORY="${BASH_SOURCE[0]%/*}"
# shellcheck source=shell-assembly.sh
source "${_GUIDED_SHELL_DIRECTORY}/shell-assembly.sh"
# shellcheck source=shell-options.sh
source "${_GUIDED_SHELL_DIRECTORY}/shell-options.sh"
# shellcheck source=shell-users.sh
source "${_GUIDED_SHELL_DIRECTORY}/shell-users.sh"
# shellcheck source=shell-session.sh
source "${_GUIDED_SHELL_DIRECTORY}/shell-session.sh"

# =============================================================================
# SELECTION SEAM
# =============================================================================

declare -gA _GUIDED_ANSWERS=()
_GUIDED_REPLAY=0

# guided_load_replay <file> — load a key=value answers file (one per line) for
# headless replay. Subsequent seam calls return the scripted answer by key.
guided_load_replay() {
  local file="$1" line key value
  declare -gA _GUIDED_ANSWERS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    _GUIDED_ANSWERS["$key"]="$value"
  done <"$file"
  _GUIDED_REPLAY=1
}

# guided_prompt <key> <prompt> — a typed free-text value.
guided_prompt() {
  local key="$1" prompt="$2" value
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  read -rp "  ${prompt}: " value </dev/tty
  printf '%s' "$value"
}

# guided_select <key> <prompt> <option...> — pick one of the enumerated values.
guided_select() {
  local key="$1" prompt="$2"
  shift 2
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  printf '%s\n' "$@" | fzf --reverse --prompt="${prompt}> "
}

# guided_multi <key> <prompt> <option...> — pick zero or more of the enumerated
# values. Interactive: an fzf multi-select (TAB to mark). Replay: the scripted
# answer is a whitespace-separated list. Emits one picked option per line; the
# first line is the primary (kernel/desktop ordering). The replay/interactive
# parity mirrors guided_pick_disks.
guided_multi() {
  local key="$1" prompt="$2"
  shift 2
  if ((_GUIDED_REPLAY)); then
    # answer is a whitespace-separated token list
    # shellcheck disable=SC2086
    printf '%s\n' ${_GUIDED_ANSWERS[$key]-}
    return
  fi
  printf '%s\n' "$@" | fzf --reverse --multi \
    --prompt="${prompt} (TAB to mark)> "
}

# guided_pick_disk [<key>] — resolve one disk via the Pre-Install Picker
# (lsblk/SMART preview), or the scripted answer under replay.
guided_pick_disk() {
  local key="${1:-disk}" live
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  live="$(live_medium_disks)"
  local -a candidates
  mapfile -t candidates < <(picker_enum_disks "$live")
  ((${#candidates[@]})) || {
    error "guided: no /dev/disk/by-id/* candidates found"
    return 1
  }
  # Show a readable "/dev/sda <size> <model> …" label (field 1); the by-id path
  # rides along as hidden field 2 — the value returned and previewed ({2}).
  local pick path
  pick="$(
    for path in "${candidates[@]}"; do
      printf '%s\t%s\n' "$(picker_disk_label "$path")" "$path"
    done | fzf --reverse --prompt='disk> ' --delimiter='\t' --with-nth=1 \
      --preview="bash -c 'source \"${INSTALLER_DIR}/lib/picker.sh\"; \
        picker_format_disk_preview {2}'" \
      --preview-window=right,60%
  )"
  [[ -n "$pick" ]] && printf '%s' "${pick#*$'\t'}"
}


# _guided_shell_seed_from_profile — headless replay seed (ADR 0055): when the
# answers declare `profile=<name>`, merge hosts/<name>/profile.jsonc over
# _GUIDED_STATE (profiles_seed — profile wins, devices flattened) BEFORE the
# per-field edits, so a replay can install a committed machine yet still
# override any field. A missing/unreadable profile is a no-op; disks stay
# operator/replay-resolved.
_guided_shell_seed_from_profile() {
  local name="${_GUIDED_ANSWERS[profile]-}" profile_file profile
  [[ -n "$name" ]] || return 0
  profile_file="${INSTALLER_DIR}/hosts/${name}/profile.jsonc"
  profile="$(_program_registry_parse "$profile_file" 2>/dev/null)" || return 0
  # Resolve over Host Core first — see _controller_enter_profiles: seeding the raw
  # delta would install a different set from `install.sh --profile <name>`.
  profile="$(layer_resolver_resolve host "$(config_state_host_core)" "$profile")"
  _GUIDED_STATE="$(profiles_seed "$_GUIDED_STATE" "$profile")"
}

guided_build() {
  local assignment effective hostname
  _GUIDED_STATE="$(config_state_new)"
  _GUIDED_DISK=""
  _guided_shell_set_identity
  _guided_shell_users_reset
  _guided_shell_seed_primary_user

  if ((_GUIDED_REPLAY)); then
    _guided_shell_replay_edits
  else
    guided_run_persistent || { error "guided: cancelled"; return 1; }
  fi

  local action; action="$(_guided_shell_terminal_action)"

  # No-user guard (M5), ahead of every terminal action.
  _guided_shell_guard_post_install || return 1

  hostname="$(config_state_get "$(_guided_shell_effective)" system.hostname)"

  # Save + Export return _GUIDED_ACTION_DONE (64) so the caller does NOT run
  # the back-end install.
  if [[ "$action" == "save" ]]; then
    _guided_shell_save || return 1
    return "$_GUIDED_ACTION_DONE"
  fi

  # Proceed + Export both bake the picked disks onto the layout. The assignment
  # carries the devices (bound in-menu and/or flat-picked); the skeleton handed
  # to emit is flattened device-less so devices[] never leaks into the Effective
  # Config — picker_assign_disks re-adds them from the assignment.
  assignment="$(_guided_shell_resolve_assignment)" || return 1
  effective="$(emit_effective \
    "$(skeleton_flatten_devices "$(_guided_shell_effective)")" "$assignment")" \
    || return 1

  if [[ "$action" == "export" ]]; then
    _guided_shell_export "$effective" "$hostname" || return 1
    return "$_GUIDED_ACTION_DONE"
  fi

  _guided_shell_review "$hostname" "$assignment" || return 1

  # Past consent: materialize ad-hoc User Profiles + stage the no-SOPS password
  # manifest (issue 07). Passwords never enter $effective, only the side file.
  _guided_shell_finalize_users

  printf '%s\n' "$effective"
}

# _guided_shell_replay_edits — apply every replay answer through its edit.
_guided_shell_replay_edits() {
  # Each edit reads its own seam key; an absent answer is a no-op returning
  # non-zero. install.sh runs guided_build under `set -e`, so errexit AND the
  # inherited ERR trap are suspended across this best-effort sequence (else
  # every no-op edit aborts the run / spams "aborted"), restored after.
  local had_errexit=0; [[ $- == *e* ]] && had_errexit=1
  local error_trap; error_trap="$(trap -p ERR)"
  set +e
  trap - ERR
  _guided_shell_apply_replay_answers
  ((had_errexit)) && set -e
  eval "${error_trap:-:}"
}

# _guided_shell_apply_replay_answers — every edit, in menu order; each reads
# its own seam key and an absent answer is a no-op.
_guided_shell_apply_replay_answers() {
  # ADR 0055: `profile=<name>` seeds before the edits.
  _guided_shell_seed_from_profile
  _guided_shell_edit_hostname
  _guided_shell_edit_locale
  _guided_shell_edit_timezone
  _guided_shell_edit_keymap
  _guided_shell_edit_layout
  _guided_shell_edit_bound_devices
  _guided_shell_edit_manual
  _guided_shell_edit_filesystem
  _guided_shell_edit_encryption
  _guided_shell_edit_impermanence
  _guided_shell_add_persist
  _guided_shell_edit_kernel
  _guided_shell_edit_bootloader
  _guided_shell_edit_swap
  _guided_shell_edit_swap_size
  _guided_shell_edit_esp_size
  _guided_shell_edit_ssh
  _guided_shell_edit_age_key_url
  _guided_shell_edit_desktop
  _guided_shell_edit_display_manager
  _guided_shell_edit_gpu
  _guided_shell_edit_mirror_countries
  _guided_shell_edit_optional_repos
  _guided_shell_add_mirror_server
  _guided_shell_add_custom_repository
  _guided_shell_add_package
  _guided_shell_add_host_program
  _guided_shell_add_sysctl
  _guided_shell_edit_firewall
  _guided_shell_edit_antivirus
  _guided_shell_edit_rootkit
  _guided_shell_edit_apparmor
  _guided_shell_edit_zfs_snapshot
  _guided_shell_edit_borg
  _guided_shell_pick_users
  _guided_shell_create_user
  _guided_shell_set_root_password
  # The single path resolves its one disk here; multi collects N at accept.
  # Manual replay already set it (its manual_disk is the install disk).
  [[ "$(config_state_get "$(_guided_shell_effective)" mode)" == "multi" \
    || -n "$_GUIDED_DISK" ]] || _guided_shell_edit_disk
}

# _guided_shell_terminal_action — Proceed (install now), Save (device-less
# profile) or Export (device-baked config), issue 08. Replay drives it via the
# `terminal` key; interactively the menu loop set _GUIDED_ACTION.
_guided_shell_terminal_action() {
  local action
  if ((_GUIDED_REPLAY)); then
    action="${_GUIDED_ANSWERS[terminal]-proceed}"
  else
    action="${_GUIDED_ACTION:-proceed}"
  fi
  printf '%s\n' "${action:-proceed}"
}

# _guided_shell_save — Save is device-less: no disks, no install. Write the
# committed profile + materialize ad-hoc User Profiles.
_guided_shell_save() {
  local name; name="$(guided_prompt save_name "Save as hosts/<name>")"
  # Refuse ANY collision before writing anything (Save never overwrites): an
  # ad-hoc user whose users/<n>/ already exists aborts before the host profile
  # is committed, so a failed Save leaves no half-written artifacts.
  local clash
  for clash in "${_GUIDED_ADHOC_ORDER[@]+"${_GUIDED_ADHOC_ORDER[@]}"}"; do
    [[ -e "${INSTALLER_DIR}/users/${clash}/profile.jsonc" ]] && {
      error "guided: users/${clash}/ already exists — choose a new user name."
      return 1
    }
  done
  # Flatten In-Menu Disk Binding back to counts so the committed profile stays
  # device-less (ADR 0036/0047) — bound devices become disk_count, root_disk
  # is dropped.
  # Save-warn (ADR 0051): a committed user's in-menu profile edits are
  # install-only — they are NOT written to the saved profile (users are
  # names-only) nor back to the committed users/<name>/profile.jsonc. Name them
  # so the drop is never silent. Computed before materialize (which writes
  # ad-hoc profiles) so only genuinely-committed users are reported.
  local edited_users
  edited_users="$(_guided_shell_committed_userform_edits \
    | awk 'NR > 1 { printf "%s", (NR % 2 == 0 ? "," : " ") }
        { printf "%s", $0 }')"
  guided_save_host_profile \
    "$(skeleton_flatten_devices "$(_guided_shell_effective)")" "$name" \
    || return 1
  _guided_shell_materialize_users save || return 1
  [[ -n "$edited_users" ]] && warn "guided: install-only edits NOT saved for:" \
    "${edited_users} — edit users/<name>/profile.jsonc to persist them." >&2
  info "Saved hosts/${name}/profile.jsonc — install via \
--profile ${name}." >&2
}

# _guided_shell_export <effective> <hostname> — write the device-baked config
# to an operator path (default /root, which is RAM on the live ISO), never
# under hosts/. No install.
_guided_shell_export() {
  local effective="$1" hostname="$2"
  local path; path="$(guided_prompt export_path \
    "Export path (default /root/${hostname:-host}.effective.jsonc)")"
  [[ -n "$path" ]] || path="/root/${hostname:-host}.effective.jsonc"
  warn "/root is RAM on the live ISO — point at a USB to keep the export." >&2
  guided_export_config "$effective" "$path" || return 1
  info "Exported ${path} — install via install.sh ${path}." >&2
}

# _guided_shell_review <hostname> <assignment> — the review + the single
# consent gate. Human-facing → stderr; stdout carries only the Effective Config
# the caller captures. Credentials are captured IN the menu (ticket 03) or via
# replay answers, so there is no post-menu credential prompt here.
_guided_shell_review() {
  local hostname="$1" assignment="$2" mode confirm
  mode="$(config_state_get "$(_guided_shell_effective)" mode)"
  section "Review" >&2
  printf '  Host:        %s\n' "${hostname:-(prompted at install)}" >&2
  if manual_partition_kind_active "$_GUIDED_STATE"; then
    printf '  MANUAL:      your partitions on %s (no wipe)\n' \
      "$(jq -r '.disk // ""' <<<"$assignment")" >&2
  elif [[ "$mode" == "multi" ]]; then
    printf '  WILL ERASE:  the disks in the layout above\n' >&2
  else
    # Read the resolved disk from the assignment, not $_GUIDED_DISK: the
    # in-menu disk binding (ADR 0047) stores the pick as root_disk and leaves
    # _GUIDED_DISK empty, so the old var showed a blank WILL ERASE line.
    printf '  WILL ERASE:  %s\n' \
      "$(jq -r '.disk // ""' <<<"$assignment")" >&2
  fi
  confirm="$(guided_prompt confirm "Type INSTALL to continue")"
  [[ "$confirm" == "INSTALL" ]] \
    || { error "guided: aborted — INSTALL not typed"; return 1; }
}
