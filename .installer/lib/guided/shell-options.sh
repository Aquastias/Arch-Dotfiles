#!/usr/bin/env bash
# =============================================================================
# lib/guided/shell-options.sh — Guided shell option, package and advanced edits
# =============================================================================
# Part of the Guided Installer fzf shell (lib/guided/shell.sh, ADR 0039).
#
# Used by: lib/guided/shell.sh (sources it).
# =============================================================================

# =============================================================================
# OPTIONS + ENVIRONMENT (issue 05) — the FS-agnostic host knobs
# =============================================================================
# Each edit routes a value through the selection seam into the Config State, so
# the interactive menu and a replay file drive the same writes. Multi-select
# fields (kernel / desktop / gpu) store a JSON array, primary/first token first.

# _guided_shell_collect_multi <key> <prompt> <opt...> — the multi-select picks
# with empty lines dropped, one per line (pick order preserved). The shared
# collector behind every multi field; the caller mapfiles it so an empty result
# (absent replay answer) is an empty array, never a phantom [""] token.
_guided_shell_collect_multi() {
  guided_multi "$@" | grep -v '^[[:space:]]*$' || true
}

# _guided_shell_multi_array <key> <prompt> <opt...> — collect a multi-select
# into a JSON string array (pick order preserved). rc 1 + no output when nothing
# was picked, so an absent replay answer no-ops the edit.
_guided_shell_multi_array() {
  local -a picks=()
  mapfile -t picks < <(_guided_shell_collect_multi "$@")
  ((${#picks[@]})) || return 1
  printf '%s\n' "${picks[@]}" | jq -R . | jq -s -c .
}

# _guided_shell_edit_scalar <key> <prompt> <path> — a typed free-text value
# committed at <path> as a JSON string. rc 1 (no commit) on empty input.
_guided_shell_edit_scalar() {
  local key="$1" prompt="$2" path="$3" value
  value="$(guided_prompt "$key" "$prompt")"
  _GUIDED_STATE="$(edit_set_scalar "$_GUIDED_STATE" "$path" "$value")"
}

# _guided_shell_edit_multi <key> <label> <path> — a multi-select over the
# menu's enumerated options for <path>, stored as a JSON array. rc 1 (no
# commit) when nothing is picked.
_guided_shell_edit_multi() {
  local key="$1" label="$2" path="$3" selection_json
  local -a options; mapfile -t options < <(menu_enum_options "$path")
  selection_json="$(_guided_shell_multi_array "$key" "$label" \
    "${options[@]}")" || return 1
  _GUIDED_STATE="$(config_state_set "$_GUIDED_STATE" "$path" \
    "$selection_json")"
}

# _guided_shell_edit_choice <key> <label> <path> — a single-select over the
# menu's enumerated options for <path>, stored as a JSON string.
_guided_shell_edit_choice() {
  local key="$1" label="$2" path="$3" value
  local -a options; mapfile -t options < <(menu_enum_options "$path")
  value="$(guided_select "$key" "$label" "${options[@]}")"
  [[ -n "$value" ]] || return 1
  _GUIDED_STATE="$(config_state_set "$_GUIDED_STATE" "$path" \
    "$(jq -n --arg x "$value" '$x')")"
}

# _guided_shell_edit_kernel — Kernel Selection: a multi-select over the flavour
# tokens (first = Primary Kernel). All tokens are offered even on ZFS; the ZFS
# Module Guard is the install-time backstop for a flavour archzfs can't build
# (ADR 0024).
_guided_shell_edit_kernel() {
  _guided_shell_edit_multi kernel "Kernels (first = primary)" options.kernel
}

# _guided_shell_edit_bootloader — pick the bootloader (grub | systemd-boot).
_guided_shell_edit_bootloader() {
  _guided_shell_edit_choice bootloader "Bootloader" options.bootloader
}

# _guided_shell_edit_display_manager — pick the greeter (auto | greetd |
# noctalia-greeter | sddm), a single-select like the bootloader/firewall
# radiolists (ADR 0069).
_guided_shell_edit_display_manager() {
  _guided_shell_edit_choice display_manager "Display manager" \
    environment.display_manager
}

# _guided_shell_edit_swap / _guided_shell_edit_ssh — the two FS-agnostic bool
# toggles.
_guided_shell_edit_swap() {
  _guided_shell_edit_bool swap "Swap (true/false)" options.swap
}
_guided_shell_edit_ssh() {
  _guided_shell_edit_bool ssh "SSH (true/false)" options.ssh.enabled
}

# Free-text Options: swap size, ESP size, and the age-key URL.
_guided_shell_edit_swap_size() {
  _guided_shell_edit_scalar swap_size "Swap size (e.g. 8G)" options.swap_size
}
_guided_shell_edit_esp_size() {
  _guided_shell_edit_scalar esp_size "ESP size (auto, or e.g. 2G)" \
    options.esp_size
}
_guided_shell_edit_age_key_url() {
  _guided_shell_edit_scalar age_key_url "Age key URL" options.age_key_url
}

# _guided_shell_edit_desktop — Environment desktop: a multi-select over kde
# (one, both, or none → a server install). Stored as a JSON array.
_guided_shell_edit_desktop() {
  _guided_shell_edit_multi desktop "Desktop" environment.desktop
}

# _guided_shell_edit_gpu — Environment gpu: auto, or a multi-select of vendors.
# auto is mutually exclusive — choosing it clears explicit vendors and stores
# the scalar "auto" (the accessor default shape); vendors store a JSON array
# (ADR: GPU Resolution).
_guided_shell_edit_gpu() {
  local -a options; mapfile -t options < <(menu_enum_options environment.gpu)
  local -a picks=()
  mapfile -t picks < <(_guided_shell_collect_multi gpu \
    "GPU (auto clears vendors)" \
    "${options[@]}")
  _GUIDED_STATE="$(edit_set_gpu "$_GUIDED_STATE" ${picks[@]+"${picks[@]}"})"
}

# =============================================================================
# PACMAN + PACKAGES + HOST ▸ ADVANCED (issue 06 Pass B)
# =============================================================================
# The rarely-touched host knobs. Pacman/Advanced scalar+bool+multi fields reuse
# the issue-05 helpers; the list builders (packages.repo, host_programs,
# sysctl) append through the seam like _guided_shell_add_persist.

# Mirror Countries (Pacman): a multi-select feeding reflector --country. The
# enumerated set is curated (reflector --list-countries needs network); a replay
# answer drives any value. Stored as a JSON array.
_guided_shell_edit_mirror_countries() {
  _guided_shell_edit_multi mirror_countries "Mirror countries" \
    options.mirror_countries
}

# Optional Repositories (ADR 0072): a multi-select over multilib + the testing
# repos (replaces the old multilib bool). Stored as a JSON array; unset keeps
# the
# accessor's `multilib` default.
_guided_shell_edit_optional_repos() {
  _guided_shell_edit_multi optional_repos "Optional repositories" \
    options.optional_repos
}

# Custom mirror Server= URL, appended dedup (ADR 0072). rc 1 (no commit) on
# empty.
_guided_shell_add_mirror_server() {
  local raw; raw="$(guided_prompt mirror_server "Custom mirror Server URL")"
  _GUIDED_STATE="$(edit_add_mirror_server "$_GUIDED_STATE" "$raw")"
}

# Custom repository "name url [sign_check] [sign_option]" → object appended
# dedup
# by name (ADR 0072). rc 1 on fewer than 2 tokens.
_guided_shell_add_custom_repository() {
  local raw; raw="$(guided_prompt custom_repository \
    "Custom repo: name url [Never|Optional|Required] [TrustAll|TrustedOnly]")"
  _GUIDED_STATE="$(edit_add_custom_repository "$_GUIDED_STATE" "$raw")"
}
# Security & Backup Extras editors (ADR 0041). The firewall is a single-choice
# radiolist (firewalld | ufw | none) — picking one IS the mutual exclusion; the
# rest are bool toggles over the structured post_install object. Each commits a
# leaf under post_install.{security,backup}.*; the resolver maps the object to
# the installed program list.
_guided_shell_edit_firewall() {
  local -a options
  mapfile -t options < <(menu_enum_options post_install.security.firewall)
  local value; value="$(guided_select firewall "Firewall" "${options[@]}")"
  case "$value" in
  firewalld | ufw | none) ;;
  *) return 1 ;;
  esac
  _GUIDED_STATE="$(config_state_set "$_GUIDED_STATE" \
    post_install.security.firewall "\"$value\"")"
}
_guided_shell_edit_antivirus() {
  _guided_shell_edit_bool antivirus "Antivirus / clamav (true/false)" \
    post_install.security.antivirus
}
_guided_shell_edit_rootkit() {
  _guided_shell_edit_bool rootkit "Rootkit scanner / rkhunter (true/false)" \
    post_install.security.rootkit
}
_guided_shell_edit_apparmor() {
  _guided_shell_edit_bool apparmor "AppArmor (true/false)" \
    post_install.security.apparmor
}
_guided_shell_edit_zfs_snapshot() {
  _guided_shell_edit_bool zfs_snapshot "ZFS auto-snapshot (true/false)" \
    post_install.backup.zfs_auto_snapshot
}
_guided_shell_edit_borg() {
  _guided_shell_edit_bool borg "Borg backup (true/false)" \
    post_install.backup.borg
}

# _guided_shell_add_package — append typed repo package name(s)
# (whitespace-split) to packages.extra. The emitter promotes any that resolve to
# a Host Program at build time (emit_promote_programs); the rest stay plain repo
# packages. rc 1 (no commit) on empty input.
_guided_shell_add_package() {
  local raw; raw="$(guided_prompt package "Extra package(s)")"
  _GUIDED_STATE="$(edit_append_packages "$_GUIDED_STATE" "$raw")"
}

# _guided_shell_program_names — the resolvable Host Program names
# (programs/*/*/), one per line. The enumerable source for the host_programs
# multi-select.
_guided_shell_program_names() {
  local program_directory
  for program_directory in "${INSTALLER_DIR}/programs"/*/*; do
    [[ -d "$program_directory" ]] && printf '%s\n' "${program_directory##*/}"
  done
}

# _guided_shell_add_host_program — append Host Program name(s) chosen from
# the resolvable set (multi-select; replay = whitespace list) to host_programs.
# rc 1 (no commit) when nothing is picked.
_guided_shell_add_host_program() {
  local -a names
  mapfile -t names < <(_guided_shell_program_names)
  local -a picks=()
  mapfile -t picks < <(_guided_shell_collect_multi system_program \
    "Host programs" \
    "${names[@]}")
  _GUIDED_STATE="$(edit_append_host_programs "$_GUIDED_STATE" \
    ${picks[@]+"${picks[@]}"})"
}

# _guided_shell_add_sysctl — set/override one sysctl pair from a typed
# "key=value" (numeric values stored as numbers, matching Host Core's
# swappiness=10). The key may itself contain dots (vm.swappiness), so it is set
# as a literal object key, never a dotted path. rc 1 (no commit) on a malformed
# entry.
_guided_shell_add_sysctl() {
  local raw; raw="$(guided_prompt sysctl "sysctl key=value")"
  _GUIDED_STATE="$(edit_add_sysctl_pair "$_GUIDED_STATE" "$raw")"
}
