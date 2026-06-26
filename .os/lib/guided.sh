#!/usr/bin/env bash
# =============================================================================
# lib/guided.sh — Guided Installer fzf shell (ADR 0039)
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
# =============================================================================

# shellcheck source=lib/common.sh
[[ "$(type -t error)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=lib/config/state.sh
[[ "$(type -t cfgstate_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/state.sh"
# shellcheck source=lib/config/seed.sh
[[ "$(type -t cfgstate_seed_defaults)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/seed.sh"
# shellcheck source=lib/config/edits.sh
[[ "$(type -t edit_set_scalar)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/edits.sh"
# shellcheck source=lib/config/emit.sh
[[ "$(type -t emit_effective)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/emit.sh"
# shellcheck source=lib/config/menu.sh
[[ "$(type -t menu_rows)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/menu.sh"
# shellcheck source=lib/config/history.sh
[[ "$(type -t hist_new)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/history.sh"
# shellcheck source=lib/config/skeleton.sh
[[ "$(type -t skeleton_preset)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/config/skeleton.sh"
# shellcheck source=lib/picker.sh
[[ "$(type -t picker_enum_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/picker.sh"
# shellcheck source=lib/live-medium.sh
[[ "$(type -t live_medium_disks)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/live-medium.sh"
# shellcheck source=lib/guided-secrets.sh
[[ "$(type -t guided_write_passwords)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/guided-secrets.sh"
# shellcheck source=lib/guided-save.sh
[[ "$(type -t guided_save_host_profile)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/guided-save.sh"
# shellcheck source=lib/guided-controller.sh
[[ "$(type -t guided_ctl_list)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/guided-controller.sh"
# shellcheck source=lib/prompt.sh
[[ "$(type -t prompt_secret)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/prompt.sh"

# =============================================================================
# SELECTION SEAM
# =============================================================================

declare -gA _GUIDED_ANSWERS=()
_GUIDED_REPLAY=0

# guided_load_replay <file> — load a key=value answers file (one per line) for
# headless replay. Subsequent seam calls return the scripted answer by key.
guided_load_replay() {
  local file="$1" line k v
  declare -gA _GUIDED_ANSWERS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    _GUIDED_ANSWERS["$k"]="$v"
  done <"$file"
  _GUIDED_REPLAY=1
}

# guided_prompt <key> <prompt> — a typed free-text value.
guided_prompt() {
  local key="$1" prompt="$2" v
  if ((_GUIDED_REPLAY)); then
    printf '%s' "${_GUIDED_ANSWERS[$key]-}"
    return
  fi
  read -rp "  ${prompt}: " v </dev/tty
  printf '%s' "$v"
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
    # shellcheck disable=SC2086 # the answer is a whitespace-separated token list
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
  local -a cands
  mapfile -t cands < <(picker_enum_disks "$live")
  ((${#cands[@]})) || { error "guided: no /dev/disk/by-id/* candidates found"; \
    return 1; }
  printf '%s\n' "${cands[@]}" | fzf --reverse --prompt='disk> ' \
    --preview="bash -c 'source \"${OS_DIR}/lib/picker.sh\"; \
      picker_format_disk_preview {}'" \
    --preview-window=right,60%
}

# =============================================================================
# ASSEMBLY
# =============================================================================
# In-flight session state for one guided run. Two layers (issue 01):
#   _GUIDED_BASELINE — the seeded launch defaults, set once and held constant for
#     the session. Not snapshotted (it never changes), not an "override".
#   _GUIDED_STATE — the operator's sparse OVERRIDE map (empty at launch). Every
#     edit writes here, so the ● flag / is_overridden reflect operator intent
#     only. The effective config the back-end consumes is BASELINE * STATE.
# The edit helpers (shared by the interactive menu + headless replay) write the
# override; value/mode/hostname reads go through _guided_effective.
_GUIDED_BASELINE=""
_GUIDED_STATE=""
_GUIDED_DISK=""
# Terminal action (issue 08): "proceed" | "save" | "export" — set by the menu
# loop (interactive) or the `terminal` replay key. Save/Export return
# _GUIDED_ACTION_DONE so install.sh skips the back-end (the action is terminal).
_GUIDED_ACTION=""
readonly _GUIDED_ACTION_DONE=64
# The Undo/Redo snapshot stack over the Config State (issue 02). Its present is
# kept in lockstep with _GUIDED_STATE: every interactive mutation commits, and
# undo/redo restore _GUIDED_STATE from the stack — so leaving and re-entering,
# or stepping back and forth, never loses a value.
_GUIDED_HIST=""

# _guided_set_identity — seed this operator's launch defaults into the BASELINE
# layer (hostname, Primary User, single-disk layout, locale/timezone/keymap) via
# the pure seeder. The seed is a default, not an override: it lives in the
# baseline so a fresh run carries no ●, yet still emits — validation.sh requires
# system.locale + system.timezone and the host must never be userless.
# locale/timezone/keymap surface as editable Host rows over these seeds.
_guided_set_identity() {
  _GUIDED_BASELINE="$(cfgstate_seed_defaults "$(cfgstate_new)")"
}

# _guided_effective — the effective override map the back-end consumes: the
# operator's overrides merged over the seeded baseline (jq `*`, so an override
# REPLACES a baseline array/scalar — letting the operator drop a seeded user —
# and deep-merges objects). Emit, Save and the seeded-value reads use this.
_guided_effective() {
  jq -n --argjson b "${_GUIDED_BASELINE:-{\}}" \
    --argjson o "${_GUIDED_STATE:-{\}}" '$b * $o'
}

# _guided_edit_hostname — read the hostname (seam key 'hostname') and commit it.
_guided_edit_hostname() {
  local v
  v="$(guided_prompt hostname "Hostname")"
  _GUIDED_STATE="$(edit_set_scalar "$_GUIDED_STATE" system.hostname "$v")"
}

# _guided_edit_locale / _guided_edit_timezone / _guided_edit_keymap — the three
# editable Host identity rows over the seeded defaults. Each is a free-text
# scalar through the seam (empty input no-ops, keeping the seed). _guided_edit_
# scalar lives in the Options block below; these reuse it for the Host section.
_guided_edit_locale() {
  _guided_edit_scalar locale "Locale (e.g. en_US.UTF-8)" system.locale
}
_guided_edit_timezone() {
  _guided_edit_scalar timezone "Timezone (e.g. Europe/Bucharest)" \
    system.timezone
}
_guided_edit_keymap() {
  _guided_edit_scalar keymap "Keymap (e.g. us)" system.keymap
}

# _guided_edit_disk — resolve the single install disk (Disks ▸ ZFS ▸ single).
_guided_edit_disk() { _GUIDED_DISK="$(guided_pick_disk disk)"; }

# Disk layout presets (issue 04): the named ZFS shapes the operator picks before
# disks are resolved. single keeps the one-disk path; the rest author a
# device-less pool skeleton (skeleton_preset) merged into the Config State, then
# baked at Proceed by collecting Σ disk_count disks.
_GUIDED_LAYOUTS=(single os-mirror os-mirror-raidz1 data-pools advanced)

# _guided_apply_skeleton <skeleton> — drop any previous skeleton keys, then
# merge the new one into the Config State (switching layouts never leaves a
# stale group behind).
_guided_apply_skeleton() {
  _GUIDED_STATE="$(edit_apply_skeleton "$_GUIDED_STATE" "$1")"
}

# _guided_edit_layout — pick a disk-layout preset (or Advanced authoring) and
# merge the resulting skeleton into the Config State. rc 1 (no change) when the
# pick is empty (e.g. an absent replay answer keeps the default single path).
_guided_edit_layout() {
  local pick skel
  pick="$(guided_select layout "Disk layout" "${_GUIDED_LAYOUTS[@]}")"
  [[ -n "$pick" ]] || return 1
  [[ "$pick" == "advanced" ]] && { _guided_author_skeleton; return; }
  skel="$(skeleton_preset "$pick")" || return 1
  _guided_apply_skeleton "$skel"
}

# _guided_author_skeleton — the Advanced door: author an arbitrary pool skeleton
# group by group (OS pool, then N storage groups, then N data pools), each via
# the seam so a replay file (and the interactive menu) drive the same builders.
# skeleton_validate gates the result against the min-disk table before it is
# applied. rc 1 (no change) on a cancelled pick or an un-installable skeleton.
_guided_author_skeleton() {
  local os_topo os_dc skel n i name topo dc owners
  os_topo="$(guided_select adv_os_topology "OS pool topology" \
    mirror stripe raidz1 raidz2 none)"
  [[ -n "$os_topo" ]] || return 1
  os_dc="$(guided_prompt adv_os_disk_count "OS pool disk count")"
  [[ -n "$os_dc" ]] || return 1
  skel="$(skeleton_new_multi "$os_topo" "$os_dc")"

  n="$(guided_prompt adv_storage_count "Number of storage groups")"
  for ((i = 0; i < ${n:-0}; i++)); do
    name="$(guided_prompt "adv_storage_${i}_name" "storage[$i] name")"
    topo="$(guided_select "adv_storage_${i}_topology" "storage[$i] topology" \
      mirror stripe raidz1 raidz2)"
    dc="$(guided_prompt "adv_storage_${i}_disk_count" "storage[$i] disk count")"
    owners="$(guided_prompt "adv_storage_${i}_owners" "storage[$i] owners")"
    skel="$(skeleton_add_storage "$skel" "$name" "$topo" "$dc" "$owners")"
  done

  n="$(guided_prompt adv_data_count "Number of data pools")"
  for ((i = 0; i < ${n:-0}; i++)); do
    name="$(guided_prompt "adv_data_${i}_name" "data[$i] name")"
    topo="$(guided_select "adv_data_${i}_topology" "data[$i] topology" \
      stripe mirror raidz1 raidz2)"
    dc="$(guided_prompt "adv_data_${i}_disk_count" "data[$i] disk count")"
    owners="$(guided_prompt "adv_data_${i}_owners" "data[$i] owners")"
    skel="$(skeleton_add_data_pool "$skel" "$name" "$topo" "$dc" "$owners")"
  done

  skeleton_validate "$skel" || return 1
  _guided_apply_skeleton "$skel"
}

# guided_pick_disks <key> <n> — resolve <n> install disks (multi-disk layouts).
# Replay: the scripted answer is a whitespace-separated device list. Interactive:
# an fzf multi-select over the picker candidates. Emits one device per line.
guided_pick_disks() {
  local key="$1" n="$2" live
  if ((_GUIDED_REPLAY)); then
    # shellcheck disable=SC2086 # the answer is a whitespace-separated disk list
    printf '%s\n' ${_GUIDED_ANSWERS[$key]-}
    return
  fi
  live="$(live_medium_disks)"
  local -a cands
  mapfile -t cands < <(picker_enum_disks "$live")
  ((${#cands[@]} >= n)) || { error "guided: need $n disks, only ${#cands[@]} found"; \
    return 1; }
  printf '%s\n' "${cands[@]}" | fzf --reverse --multi \
    --prompt="pick ${n} disks (TAB to mark)> "
}

# Filesystem Adapter axis (ADR 0040): ZFS is the only built adapter; the rest
# are reserved menu entries so the Disks section is filesystem-first without
# pretending the others work.
_GUIDED_FS_ACTIVE=(zfs)
_GUIDED_FS_RESERVED=(btrfs ext4 xfs)

# _guided_filesystem_options — the filesystem picker lines: active filesystems
# first, then the reserved ones flagged "(reserved)". Pure: emits lines.
_guided_filesystem_options() {
  printf '%s\n' "${_GUIDED_FS_ACTIVE[@]}"
  local f
  for f in "${_GUIDED_FS_RESERVED[@]}"; do printf '%s (reserved)\n' "$f"; done
}

# _guided_edit_filesystem — pick the filesystem; commit only an active one. A
# reserved pick is refused (rc 1, no commit) so the loop never offers an
# unbuilt adapter. The token is the first word of the picked line.
_guided_edit_filesystem() {
  local -a opts
  mapfile -t opts < <(_guided_filesystem_options)
  local pick token f
  pick="$(guided_select filesystem "Filesystem" "${opts[@]}")"
  [[ -n "$pick" ]] || return 0
  token="${pick%% *}"
  for f in "${_GUIDED_FS_ACTIVE[@]}"; do
    if [[ "$token" == "$f" ]]; then
      _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" filesystem \
        "$(jq -n --arg x "$token" '$x')")"
      return 0
    fi
  done
  printf "  Filesystem '%s' is reserved (ADR 0040); only zfs is built.\n" \
    "$token" >&2
  return 1
}

# _guided_edit_bool <key> <prompt> <path> — a true/false toggle through the
# seam (replay-friendly: the answer is the literal "true"/"false"). Sets <path>
# to the JSON bool. rc 1 (no commit) when the pick is neither — e.g. an absent
# replay answer — so a no-op edit never snapshots.
_guided_edit_bool() {
  local key="$1" prompt="$2" path="$3" v
  v="$(guided_select "$key" "$prompt" true false)"
  _GUIDED_STATE="$(edit_set_bool "$_GUIDED_STATE" "$path" "$v")"
}

# _guided_edit_encryption / _guided_edit_impermanence — the two Disks bools.
# Encryption enablement is the bool; the cipher is the filesystem-derived
# encryption_method (ADR 0040). Impermanence-on lets the back-end apply the
# Curated Persist Defaults and surfaces the persist-extension action below.
_guided_edit_encryption() {
  _guided_edit_bool encryption "Encryption (true/false)" options.encryption
}
_guided_edit_impermanence() {
  _guided_edit_bool impermanence "Impermanence (true/false)" \
    options.impermanence.enabled
}

# _guided_add_persist — append one operator-typed absolute directory to
# persist.directories (a Persist Extension over the Curated Persist Defaults).
# rc 1 (no commit) on empty input.
_guided_add_persist() {
  local dir
  dir="$(guided_prompt persist_dir "Persist directory (absolute path)")"
  _GUIDED_STATE="$(edit_append_persist "$_GUIDED_STATE" "$dir")"
}

# =============================================================================
# OPTIONS + ENVIRONMENT (issue 05) — the FS-agnostic host knobs
# =============================================================================
# Each edit routes a value through the selection seam into the Config State, so
# the interactive menu and a replay file drive the same writes. Multi-select
# fields (kernel / desktop / gpu) store a JSON array, primary/first token first.

# _guided_collect_multi <key> <prompt> <opt...> — the multi-select picks with
# empty lines dropped, one per line (pick order preserved). The shared collector
# behind every multi field; the caller mapfiles it so an empty result (absent
# replay answer) is an empty array, never a phantom [""] token.
_guided_collect_multi() {
  guided_multi "$@" | grep -v '^[[:space:]]*$' || true
}

# _guided_multi_array <key> <prompt> <opt...> — collect a multi-select into a
# JSON string array (pick order preserved). rc 1 + no output when nothing was
# picked, so an absent replay answer no-ops the edit.
_guided_multi_array() {
  local -a picks=()
  mapfile -t picks < <(_guided_collect_multi "$@")
  ((${#picks[@]})) || return 1
  printf '%s\n' "${picks[@]}" | jq -R . | jq -s -c .
}

# _guided_edit_scalar <key> <prompt> <path> — a typed free-text value committed
# at <path> as a JSON string. rc 1 (no commit) on empty input.
_guided_edit_scalar() {
  local key="$1" prompt="$2" path="$3" v
  v="$(guided_prompt "$key" "$prompt")"
  _GUIDED_STATE="$(edit_set_scalar "$_GUIDED_STATE" "$path" "$v")"
}

# _guided_edit_kernel — Kernel Selection: a multi-select over the flavour tokens
# (first = Primary Kernel). All tokens are offered even on ZFS; the ZFS Module
# Guard is the install-time backstop for a flavour archzfs can't build (ADR 0024).
_guided_edit_kernel() {
  local arr
  arr="$(_guided_multi_array kernel "Kernels (first = primary)" \
    lts default hardened zen)" || return 1
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" options.kernel "$arr")"
}

# _guided_edit_bootloader — pick the bootloader (grub | systemd-boot).
_guided_edit_bootloader() {
  local v
  v="$(guided_select bootloader "Bootloader" systemd-boot grub)"
  [[ -n "$v" ]] || return 1
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" options.bootloader \
    "$(jq -n --arg x "$v" '$x')")"
}

# _guided_edit_swap / _guided_edit_ssh — the two FS-agnostic bool toggles.
_guided_edit_swap() {
  _guided_edit_bool swap "Swap (true/false)" options.swap
}
_guided_edit_ssh() {
  _guided_edit_bool ssh "SSH (true/false)" options.ssh.enabled
}

# Free-text Options: swap size, ESP size, and the age-key URL.
_guided_edit_swap_size() {
  _guided_edit_scalar swap_size "Swap size (e.g. 8G)" options.swap_size
}
_guided_edit_esp_size() {
  _guided_edit_scalar esp_size "ESP size (e.g. 2G)" options.esp_size
}
_guided_edit_age_key_url() {
  _guided_edit_scalar age_key_url "Age key URL" options.age_key_url
}

# _guided_edit_desktop — Environment desktop: a multi-select over kde / hyprland
# (one, both, or none → a server install). Stored as a JSON array.
_guided_edit_desktop() {
  local arr
  arr="$(_guided_multi_array desktop "Desktop" kde hyprland)" || return 1
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" environment.desktop "$arr")"
}

# _guided_edit_gpu — Environment gpu: auto, or a multi-select of vendors. auto is
# mutually exclusive — choosing it clears explicit vendors and stores the scalar
# "auto" (the accessor default shape); vendors store a JSON array (ADR: GPU
# Resolution).
_guided_edit_gpu() {
  local -a picks=()
  mapfile -t picks < <(_guided_collect_multi gpu "GPU (auto clears vendors)" \
    auto amd nvidia intel)
  _GUIDED_STATE="$(edit_set_gpu "$_GUIDED_STATE" ${picks[@]+"${picks[@]}"})"
}

# =============================================================================
# PACMAN + PACKAGES + HOST ▸ ADVANCED (issue 06 Pass B)
# =============================================================================
# The rarely-touched host knobs. Pacman/Advanced scalar+bool+multi fields reuse
# the issue-05 helpers; the list builders (packages.extra, system_programs,
# sysctl) append through the seam like _guided_add_persist.

# Mirror Countries (Pacman): a multi-select feeding reflector --country. The
# enumerated set is curated (reflector --list-countries needs network); a replay
# answer drives any value. Stored as a JSON array.
_guided_edit_mirror_countries() {
  local arr
  arr="$(_guided_multi_array mirror_countries "Mirror countries" \
    Germany Switzerland Sweden France Romania Austria Netherlands \
    "United Kingdom" "United States" Japan Australia)" || return 1
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" options.mirror_countries "$arr")"
}

# multilib (Pacman) + the two post_install extras (Advanced) — bool toggles.
_guided_edit_multilib() {
  _guided_edit_bool multilib "Multilib (true/false)" options.multilib
}
# Security & Backup Extras editors (ADR 0041). The firewall is a single-choice
# radiolist (firewalld | ufw | none) — picking one IS the mutual exclusion; the
# rest are bool toggles over the structured post_install object. Each commits a
# leaf under post_install.{security,backup}.*; the resolver maps the object to
# the installed program list.
_guided_edit_firewall() {
  local v; v="$(guided_select firewall "Firewall" firewalld ufw none)"
  case "$v" in
  firewalld | ufw | none) ;;
  *) return 1 ;;
  esac
  _GUIDED_STATE="$(cfgstate_set "$_GUIDED_STATE" \
    post_install.security.firewall "\"$v\"")"
}
_guided_edit_antivirus() {
  _guided_edit_bool antivirus "Antivirus / clamav (true/false)" \
    post_install.security.antivirus
}
_guided_edit_rootkit() {
  _guided_edit_bool rootkit "Rootkit scanner / rkhunter (true/false)" \
    post_install.security.rootkit
}
_guided_edit_apparmor() {
  _guided_edit_bool apparmor "AppArmor (true/false)" \
    post_install.security.apparmor
}
_guided_edit_zfs_snapshot() {
  _guided_edit_bool zfs_snapshot "ZFS auto-snapshot (true/false)" \
    post_install.backup.zfs_auto_snapshot
}
_guided_edit_borg() {
  _guided_edit_bool borg "Borg backup (true/false)" post_install.backup.borg
}

# _guided_add_package — append typed repo package name(s) (whitespace-split) to
# packages.extra. The emitter promotes any that resolve to a System Program at
# build time (emit_promote_programs); the rest stay plain repo packages. rc 1
# (no commit) on empty input.
_guided_add_package() {
  local raw; raw="$(guided_prompt package "Extra package(s)")"
  _GUIDED_STATE="$(edit_append_packages "$_GUIDED_STATE" "$raw")"
}

# _guided_program_names — the resolvable System Program names (programs/*/*/),
# one per line. The enumerable source for the system_programs multi-select.
_guided_program_names() {
  local d
  for d in "${OS_DIR}/programs"/*/*; do
    [[ -d "$d" ]] && basename "$d"
  done
}

# _guided_add_system_program — append host System Program name(s) chosen from
# the resolvable set (multi-select; replay = whitespace list) to system_programs.
# rc 1 (no commit) when nothing is picked.
_guided_add_system_program() {
  local -a names
  mapfile -t names < <(_guided_program_names)
  local -a picks=()
  mapfile -t picks < <(_guided_collect_multi system_program "System programs" \
    "${names[@]}")
  _GUIDED_STATE="$(edit_append_system_programs "$_GUIDED_STATE" \
    ${picks[@]+"${picks[@]}"})"
}

# _guided_add_sysctl — set/override one sysctl pair from a typed "key=value"
# (numeric values stored as numbers, matching Host Core's swappiness=10). The
# key may itself contain dots (vm.swappiness), so it is set as a literal object
# key, never a dotted path. rc 1 (no commit) on a malformed entry.
_guided_add_sysctl() {
  local raw; raw="$(guided_prompt sysctl "sysctl key=value")"
  [[ "$raw" == *=* ]] || return 1
  _GUIDED_STATE="$(edit_set_sysctl "$_GUIDED_STATE" "${raw%%=*}" "${raw#*=}")"
}

# =============================================================================
# USERS + PASSWORDS (issue 07)
# =============================================================================
# The host's user list is the ordered union of committed picks (users/*/) and
# ad-hoc creations, committed first, deduped — users[0] is the Primary User
# (positional, ADR 0036). Ad-hoc forms are held aside and materialized into
# users/<name>/profile.jsonc at Proceed; passwords (root + per-user) are held
# aside too and injected via the no-SOPS seam (guided-secrets.sh) — they never
# enter the Config State, so Save/Export never carry them.
_GUIDED_USERS_COMMITTED=()
_GUIDED_ADHOC_ORDER=()
declare -gA _GUIDED_ADHOC_FORM=()
declare -gA _GUIDED_USER_PW=()
_GUIDED_ROOT_PW=""

# _guided_users_reset — clear the per-session Users/password side state.
_guided_users_reset() {
  _GUIDED_USERS_COMMITTED=()
  _GUIDED_ADHOC_ORDER=()
  declare -gA _GUIDED_ADHOC_FORM=()
  declare -gA _GUIDED_USER_PW=()
  _GUIDED_ROOT_PW=""
}

# _guided_seed_primary_user — pre-select aquastias as the default committed
# Primary User so the launch state has a user (matching the seeded users[0]) and
# adding an ad-hoc user keeps aquastias first. The operator drops aquastias by
# re-picking the committed users without it. Run after _guided_users_reset.
_guided_seed_primary_user() { _GUIDED_USERS_COMMITTED=("aquastias"); }

# _guided_user_names — committed user names (users/*/ with a profile.jsonc),
# excluding the User Core layer. The enumerable source for the picker.
_guided_user_names() {
  local d n
  for d in "${OS_DIR}/users"/*/; do
    [[ -d "$d" ]] || continue
    n="$(basename "$d")"
    [[ "$n" == "core" ]] && continue
    [[ -f "${d}profile.jsonc" ]] && printf '%s\n' "$n"
  done
}

# _guided_sync_users — rebuild Config State .users from committed + ad-hoc
# (committed first, order-preserving dedup). Drops the key when no user is set.
_guided_sync_users() {
  local -a all=()
  ((${#_GUIDED_USERS_COMMITTED[@]})) \
    && all+=("${_GUIDED_USERS_COMMITTED[@]}")
  ((${#_GUIDED_ADHOC_ORDER[@]})) && all+=("${_GUIDED_ADHOC_ORDER[@]}")
  _GUIDED_STATE="$(edit_set_users "$_GUIDED_STATE" ${all[@]+"${all[@]}"})"
}

# _guided_pick_users — multi-select committed users into the user list. The
# committed selection replaces any prior committed picks; ad-hoc users survive.
_guided_pick_users() {
  local -a names; mapfile -t names < <(_guided_user_names)
  local -a picks=()
  mapfile -t picks < <(_guided_collect_multi users "Users" "${names[@]}")
  ((${#picks[@]})) || return 1
  _GUIDED_USERS_COMMITTED=("${picks[@]}")
  _guided_sync_users
}

# _guided_create_user — the ad-hoc create form: collect a User Profile's fields
# through the seam, author the delta (guided_user_profile prunes empties + drops
# the name), and register the user + its password aside. Password defaults to
# 12345 (the house default) when left blank. rc 1 (no user) on an empty name.
_guided_create_user() {
  local name shell sudo gn ge pw
  name="$(guided_prompt new_user_name "New user name")"
  [[ -n "$name" ]] || return 1
  shell="$(guided_select new_user_shell "Shell" /bin/bash /bin/zsh /bin/fish)"
  sudo="$(guided_select new_user_sudo "Sudo (→ wheel)" false true)"
  local -a groups_a programs_a keys_a
  mapfile -t groups_a < <(_guided_collect_multi new_user_groups "Groups" \
    wheel docker libvirt kvm)
  local -a prog_names; mapfile -t prog_names < <(_guided_program_names)
  mapfile -t programs_a < <(_guided_collect_multi new_user_programs "Programs" \
    "${prog_names[@]}")
  gn="$(guided_prompt new_user_git_name "Git name")"
  ge="$(guided_prompt new_user_git_email "Git email")"
  mapfile -t keys_a < <(_guided_collect_multi new_user_ssh_keys \
    "SSH authorized keys")
  pw="$(guided_prompt new_user_password "Password (default 12345)")"
  [[ -n "$pw" ]] || pw="12345"

  local form
  form="$(jq -n \
    --arg shell "$shell" \
    --argjson sudo "$([[ "$sudo" == "true" ]] && echo true || echo false)" \
    --argjson groups "$(_emit_json_array "${groups_a[@]}")" \
    --argjson programs "$(_emit_json_array "${programs_a[@]}")" \
    --arg gn "$gn" --arg ge "$ge" \
    --argjson keys "$(_emit_json_array "${keys_a[@]}")" \
    '{shell:$shell, sudo:$sudo, groups:$groups, programs:$programs,
      git: ({name:$gn, email:$ge} | with_entries(select(.value != ""))),
      ssh_authorized_keys:$keys}')"
  _GUIDED_ADHOC_FORM["$name"]="$(guided_user_profile "$form")"
  _GUIDED_ADHOC_ORDER+=("$name")
  _GUIDED_USER_PW["$name"]="$pw"
  _guided_sync_users
}

# _guided_materialize_users — write each ad-hoc User Profile delta to
# users/<name>/profile.jsonc so the back-end Runner can load it. At Proceed this
# is a transient write to the live clone; Save (issue 08) commits the same file.
_guided_materialize_users() {
  local name dir
  for name in "${_GUIDED_ADHOC_ORDER[@]+"${_GUIDED_ADHOC_ORDER[@]}"}"; do
    dir="${OS_DIR}/users/${name}"
    mkdir -p "$dir"
    printf '%s\n' "${_GUIDED_ADHOC_FORM[$name]}" > "${dir}/profile.jsonc"
  done
  # Persistent-path created users carry only a name in the Config State; give any
  # effective user lacking a committed profile a sensible default (bash + wheel
  # sudo). Committed/legacy-ad-hoc users already have one and are skipped.
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    dir="${OS_DIR}/users/${name}"
    [[ -f "${dir}/profile.jsonc" ]] && continue
    mkdir -p "$dir"
    guided_user_profile \
      '{"shell":"/bin/bash","sudo":true,"groups":["wheel"],"programs":["searxng"]}' \
      > "${dir}/profile.jsonc"
  done < <(jq -r '(.users // [])[]' <<<"$(_guided_effective)")
}

# _guided_collect_passwords — interactive post-menu credential entry (ADR 0042):
# prompt (hidden, read-twice, confirmed) for the root password and each effective
# user's password not already supplied, storing into the held-aside vars
# _guided_finalize_users reads (never the Config State, so Save/Export never
# carry them). INTERACTIVE-only — replay supplies these via keyed answers, so it
# returns early there. Because prompt_secret reads -s from /dev/tty, nothing is
# echoed: this is where the old guided_prompt plaintext-echo of passwords is
# fixed. Run on the Proceed path only (Save/Export never install).
_guided_collect_passwords() {
  ((_GUIDED_REPLAY)) && return 0
  local eff name pw=""
  local -a names
  eff="$(_guided_effective)"
  section "Credentials" >&2
  [[ -n "$_GUIDED_ROOT_PW" ]] || prompt_secret _GUIDED_ROOT_PW "Root password"
  mapfile -t names < <(jq -r '(.users // [])[]' <<<"$eff")
  for name in "${names[@]+"${names[@]}"}"; do
    [[ -n "${_GUIDED_USER_PW[$name]:-}" ]] && continue
    prompt_secret pw "Password for ${name}"
    _GUIDED_USER_PW["$name"]="$pw"
  done
}

# _guided_finalize_users — Proceed-time user side effects: materialize ad-hoc
# profiles and, when the install flow set GUIDED_SECRETS_MANIFEST, write the
# no-SOPS password manifest there for 03-install.sh to persist into install-state
# (the file the chroot/Runner resolve via .guided_passwords.*). Passwords thus
# reach the back-end without ever touching the Effective Config.
_guided_finalize_users() {
  _guided_materialize_users
  [[ -n "${GUIDED_SECRETS_MANIFEST:-}" ]] \
    && _guided_secrets_manifest >"$GUIDED_SECRETS_MANIFEST"
  return 0
}

# _guided_set_root_password — hold the root password aside (never the Config
# State, so Save/Export never carry it). rc 1 (unchanged) on empty input.
_guided_set_root_password() {
  local pw; pw="$(guided_prompt root_password "Root password")"
  [[ -n "$pw" ]] || return 1
  _GUIDED_ROOT_PW="$pw"
}

# _guided_secrets_manifest — the no-SOPS password manifest guided_write_passwords
# consumes: { root_password?, users?: { <name>: { password } } }. Built from the
# held-aside root + per-user passwords; empty {} when nothing is set. Pure: reads
# the side state, emits JSON.
_guided_secrets_manifest() {
  local manifest='{}' name
  [[ -n "$_GUIDED_ROOT_PW" ]] && manifest="$(jq --arg pw "$_GUIDED_ROOT_PW" \
    '.root_password = $pw' <<<"$manifest")"
  for name in "${!_GUIDED_USER_PW[@]}"; do
    manifest="$(jq --arg n "$name" --arg pw "${_GUIDED_USER_PW[$name]}" \
      '.users[$n] = {password: $pw}' <<<"$manifest")"
  done
  printf '%s\n' "$manifest"
}

# =============================================================================
# PERSISTENT-FZF FRONT-END (ADR 0042) — the interactive front-end
# =============================================================================
# The single-long-lived-fzf path: guided_build's only interactive route (the
# legacy one-fzf-per-pick menu loop was removed at the ADR-0042 cutover). The
# functions below are the live glue — UNVERIFIED by bats (they need fzf + a
# tty); the LOGIC they lean on (controller, setters, nav, translation) is
# unit-tested in tests/config/guided-*.bats.

# _guided_oneshot_edit <field> — the slice-01 bridge: load the Config State from
# $GUIDED_STATE_FILE into _GUIDED_STATE, run the EXISTING one-shot edit helper
# for <field> (interactive guided_prompt/guided_select), write the result back.
# Invoked by guided-fzf-entry.sh under fzf's execute() for the text + multi
# fields and the Disks layout/persist actions (slices 02/03 make these native).
_guided_oneshot_edit() {
  local field="$1"
  _GUIDED_STATE="$(<"$GUIDED_STATE_FILE")"
  case "$field" in
  system.hostname)          _guided_edit_hostname ;;
  system.locale)            _guided_edit_locale ;;
  system.timezone)          _guided_edit_timezone ;;
  system.keymap)            _guided_edit_keymap ;;
  options.swap_size)        _guided_edit_swap_size ;;
  options.esp_size)         _guided_edit_esp_size ;;
  options.age_key_url)      _guided_edit_age_key_url ;;
  sysctl)                   _guided_add_sysctl ;;
  packages.extra)           _guided_add_package ;;
  options.kernel)           _guided_edit_kernel ;;
  environment.desktop)      _guided_edit_desktop ;;
  environment.gpu)          _guided_edit_gpu ;;
  options.mirror_countries) _guided_edit_mirror_countries ;;
  system_programs)          _guided_add_system_program ;;
  users)                    _guided_pick_users ;;
  __layout__)               _guided_edit_layout ;;
  __persist__)              _guided_add_persist ;;
  *) : ;;
  esac
  printf '%s\n' "$_GUIDED_STATE" >"$GUIDED_STATE_FILE"
}

# guided_run_persistent — the ADR-0042 single-fzf front-end. Sets up the tmpfs
# state files (mktemp under ${TMPDIR:-/tmp}, cleaned on RETURN), launches ONE
# fzf whose enter/esc binds call lib/guided-fzf-entry.sh, then picks up the
# operator's edits + chosen terminal action. Returns 0 on a terminal action
# (sets _GUIDED_ACTION), 1 on abort. Single + multi disks resolve post-menu in
# _guided_resolve_assignment, so the menu carries no disk screen.
guided_run_persistent() {
  export GUIDED_STATE_FILE GUIDED_NAV_FILE GUIDED_BASELINE_FILE \
    GUIDED_RESULT_FILE GUIDED_HIST_FILE
  GUIDED_STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-state.XXXXXX.json")"
  GUIDED_NAV_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-nav.XXXXXX.json")"
  GUIDED_BASELINE_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-base.XXXXXX.json")"
  GUIDED_RESULT_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-result.XXXXXX")"
  GUIDED_HIST_FILE="$(mktemp "${TMPDIR:-/tmp}/guided-hist.XXXXXX.json")"
  # shellcheck disable=SC2064
  trap "rm -f '$GUIDED_STATE_FILE' '$GUIDED_NAV_FILE' '$GUIDED_BASELINE_FILE' '$GUIDED_RESULT_FILE' '$GUIDED_HIST_FILE'" RETURN

  printf '%s\n' "$_GUIDED_BASELINE" >"$GUIDED_BASELINE_FILE"
  printf '%s\n' "$_GUIDED_STATE"    >"$GUIDED_STATE_FILE"
  nav_new >"$GUIDED_NAV_FILE"
  : >"$GUIDED_RESULT_FILE"
  hist_new "$_GUIDED_STATE" >"$GUIDED_HIST_FILE"   # undo/redo seed

  # The header + prompt are updated per screen by the controller's `render`
  # directive (change-header/change-prompt), so they always say how to go back.
  # enter passes BOTH the selection {} and the typed query {q} (text fields read
  # {q} from fzf's own input line); esc maps to a back/abort transform; the
  # ^Z/^Y/^R keys undo/redo/reset over the snapshot stack.
  local entry="${OS_DIR}/lib/guided-fzf-entry.sh"
  # The preview pane starts hidden with a no-op body; the Disk-layout screen's
  # render swaps in the ASCII layout graph and shows it (change-preview[-window]).
  guided_ctl_list | fzf --reverse --prompt='guided> ' \
    --border=rounded --border-label=' Guided Installer ' \
    --border-label-pos=center \
    --header='Enter open   Esc quit   ·   ^Z undo  ^Y redo  ^R reset' \
    --header-border=bottom \
    --preview='echo' --preview-window=hidden \
    --bind "enter:transform(bash $entry dispatch enter {} {q})" \
    --bind "esc:transform(bash $entry dispatch back {})" \
    --bind "ctrl-z:transform(bash $entry key ctrl-z)" \
    --bind "ctrl-y:transform(bash $entry key ctrl-y)" \
    --bind "ctrl-r:transform(bash $entry key ctrl-r)" \
    >/dev/null || true

  _GUIDED_STATE="$(<"$GUIDED_STATE_FILE")"
  local action; action="$(<"$GUIDED_RESULT_FILE")"
  [[ -n "$action" ]] || return 1
  _GUIDED_ACTION="$action"
}

# _guided_guard_post_install — the terminal-action no-user guard (M5, ADR 0041).
# The Security & Backup Extras install via the Primary User's paru pass, so a
# non-empty selection on a userless host can never run. Reads the effective
# post_install object + the effective user count and defers to the pure guard;
# returns non-zero (with the actionable error) when extras are selected but no
# user exists. Run before every terminal action (Proceed / Save / Export).
_guided_guard_post_install() {
  local eff pi count
  eff="$(_guided_effective)"
  pi="$(jq -c '.post_install // {}' <<<"$eff")"
  count="$(jq '(.users // []) | length' <<<"$eff")"
  post_install_guard_users "$pi" "$count"
}

# guided_build — drive the guided menu and emit the device-baked Effective
# Config on stdout. Interactive: the re-entrant Host / Users split menu.
# Headless (--guided replay): a linear keyed collection through the SAME edit
# helpers. The typed INSTALL is the sole consent gate; non-zero (no output) if
# it is withheld.
# _guided_resolve_assignment — the picked disks → per-group assignment JSON for
# emit_effective, branching on the chosen mode. single bakes the one picked
# disk; multi collects Σ disk_count disks, slices them per group
# (picker_build_assignment), renders the per-group summary, and gates on a typed
# ACCEPT before the layout is accepted (issue 04). Emits the assignment on
# stdout; non-zero on any failure.
_guided_resolve_assignment() {
  local mode; mode="$(cfgstate_get "$(_guided_effective)" mode)"
  if [[ "$mode" == "multi" ]]; then
    local n; n="$(skeleton_total_disks "$_GUIDED_STATE")"
    local -a disks
    mapfile -t disks < <(guided_pick_disks disks "$n")
    ((${#disks[@]} == n)) \
      || { error "guided: layout needs ${n} disks, got ${#disks[@]}"; return 1; }
    local assignment
    assignment="$(picker_build_assignment "$_GUIDED_STATE" "${disks[@]}")" \
      || return 1
    section "Disk layout" >&2
    skeleton_assignment_summary "$_GUIDED_STATE" "$assignment" >&2
    local ok; ok="$(guided_prompt accept_layout "Type ACCEPT to use this layout")"
    [[ "$ok" == "ACCEPT" ]] \
      || { error "guided: disk layout not accepted"; return 1; }
    printf '%s\n' "$assignment"
  else
    # All disk resolution is post-menu (ADR 0042): the persistent front-end
    # carries no install-disk row, so resolve the single disk here (replay sets
    # _GUIDED_DISK via _guided_edit_disk in its sequence; interactive does not).
    [[ -n "$_GUIDED_DISK" ]] || _guided_edit_disk
    [[ -n "$_GUIDED_DISK" ]] || { error "guided: no disk selected"; return 1; }
    jq -n --arg d "$_GUIDED_DISK" '{mode: "single", disk: $d}'
  fi
}

guided_build() {
  local assignment effective confirm hostname mode
  _GUIDED_STATE="$(cfgstate_new)"
  _GUIDED_DISK=""
  _guided_set_identity
  _guided_users_reset
  _guided_seed_primary_user

  if ((_GUIDED_REPLAY)); then
    # Each edit reads its own seam key; an absent answer is a no-op (the edit
    # returns non-zero "no commit"). The replay file declares only the fields it
    # wants. install.sh drives guided_build under `set -e`, where a no-op edit's
    # non-zero return would abort the whole run — so errexit is suspended across
    # this best-effort sequence and restored after (the disk / assignment / emit
    # / consent steps below stay guarded). The caller's ERR trap is suspended
    # too — `set -E` inherits it here, and it fires on each no-op edit's non-zero
    # return even under set +e, spamming the log with bogus "aborted" lines.
    local _had_errexit=0; [[ $- == *e* ]] && _had_errexit=1
    local _err_trap; _err_trap="$(trap -p ERR)"
    set +e
    trap - ERR
    _guided_edit_hostname
    _guided_edit_locale
    _guided_edit_timezone
    _guided_edit_keymap
    _guided_edit_layout
    _guided_edit_filesystem
    _guided_edit_encryption
    _guided_edit_impermanence
    _guided_add_persist
    _guided_edit_kernel
    _guided_edit_bootloader
    _guided_edit_swap
    _guided_edit_swap_size
    _guided_edit_esp_size
    _guided_edit_ssh
    _guided_edit_age_key_url
    _guided_edit_desktop
    _guided_edit_gpu
    _guided_edit_mirror_countries
    _guided_edit_multilib
    _guided_add_package
    _guided_add_system_program
    _guided_add_sysctl
    _guided_edit_firewall
    _guided_edit_antivirus
    _guided_edit_rootkit
    _guided_edit_apparmor
    _guided_edit_zfs_snapshot
    _guided_edit_borg
    _guided_pick_users
    _guided_create_user
    _guided_set_root_password
    # The single path resolves its one disk here; multi collects N at accept.
    [[ "$(cfgstate_get "$(_guided_effective)" mode)" == "multi" ]] || _guided_edit_disk
    ((_had_errexit)) && set -e
    eval "${_err_trap:-:}"
  else
    guided_run_persistent || { error "guided: cancelled"; return 1; }
  fi

  # Terminal action (issue 08): Proceed (install now), Save (device-less profile),
  # or Export (device-baked config). Replay drives it via the `terminal` key;
  # interactively the menu loop set _GUIDED_ACTION. Save + Export return
  # _GUIDED_ACTION_DONE (64) so the caller does NOT run the back-end install.
  local action
  if ((_GUIDED_REPLAY)); then
    action="${_GUIDED_ANSWERS[terminal]-proceed}"
  else
    action="${_GUIDED_ACTION:-proceed}"
  fi
  [[ -n "$action" ]] || action="proceed"

  # No-user guard (M5): Proceed / Save / Export all abort when the Security &
  # Backup Extras resolve to programs but the host has no Primary User to run
  # the paru pass. Checked once here, ahead of every terminal action.
  _guided_guard_post_install || return 1

  hostname="$(cfgstate_get "$(_guided_effective)" system.hostname)"

  # Save is device-less — no disks, no install. Write the committed profile +
  # materialize ad-hoc User Profiles, then stop.
  if [[ "$action" == "save" ]]; then
    local name; name="$(guided_prompt save_name "Save as hosts/<name>")"
    # Refuse ANY collision before writing anything (Save never overwrites): an
    # ad-hoc user whose users/<n>/ already exists aborts before the host profile
    # is committed, so a failed Save leaves no half-written artifacts.
    local clash
    for clash in "${_GUIDED_ADHOC_ORDER[@]+"${_GUIDED_ADHOC_ORDER[@]}"}"; do
      [[ -e "${OS_DIR}/users/${clash}/profile.jsonc" ]] && {
        error "guided: users/${clash}/ already exists — choose a new user name."
        return 1
      }
    done
    guided_save_host_profile "$(_guided_effective)" "$name" || return 1
    _guided_materialize_users
    info "Saved hosts/${name}/profile.jsonc — install via --profile ${name}." >&2
    return "$_GUIDED_ACTION_DONE"
  fi

  # Proceed + Export both bake the picked disks onto the layout.
  assignment="$(_guided_resolve_assignment)" || return 1
  effective="$(emit_effective "$(_guided_effective)" "$assignment")" || return 1

  # Export writes the device-baked config to an operator path (default /root,
  # which is RAM on the live ISO), never under hosts/. No install.
  if [[ "$action" == "export" ]]; then
    local path; path="$(guided_prompt export_path \
      "Export path (default /root/${hostname:-host}.effective.jsonc)")"
    [[ -n "$path" ]] || path="/root/${hostname:-host}.effective.jsonc"
    warn "/root is RAM on the live ISO — point at a USB to keep the export." >&2
    guided_export_config "$effective" "$path" || return 1
    info "Exported ${path} — install via install.sh ${path}." >&2
    return "$_GUIDED_ACTION_DONE"
  fi

  # Interactive credential entry (ADR 0042): hidden + confirmed, at the commit
  # step, just before the review. No-op under replay (keyed answers already held).
  _guided_collect_passwords

  # Review + the single consent gate. Human-facing → stderr; stdout carries only
  # the Effective Config the caller captures.
  mode="$(cfgstate_get "$(_guided_effective)" mode)"
  section "Review" >&2
  printf '  Host:        %s\n' "${hostname:-(prompted at install)}" >&2
  if [[ "$mode" == "multi" ]]; then
    printf '  WILL ERASE:  the disks in the layout above\n' >&2
  else
    printf '  WILL ERASE:  %s\n' "$_GUIDED_DISK" >&2
  fi
  confirm="$(guided_prompt confirm "Type INSTALL to continue")"
  [[ "$confirm" == "INSTALL" ]] \
    || { error "guided: aborted — INSTALL not typed"; return 1; }

  # Past consent: materialize ad-hoc User Profiles + stage the no-SOPS password
  # manifest (issue 07). Passwords never enter $effective, only the side file.
  _guided_finalize_users

  printf '%s\n' "$effective"
}
