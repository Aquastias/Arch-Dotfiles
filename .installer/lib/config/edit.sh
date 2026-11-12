#!/usr/bin/env bash
# =============================================================================
# lib/config/edit.sh — Guided Installer pure edit setters (ADR 0042)
# =============================================================================
# The SET half of every guided editor, extracted into pure functions shared by
# two callers: the replay helpers in lib/guided/shell.sh (which GET a value
# through the selection seam, then SET it) and the persistent-fzf controller
# (which GETs a value from fzf, then SETs it). Centralizing the bespoke jq here
# means the path/value writes have one tested implementation — the controller
# never re-derives them.
#
# Each setter takes a Config State (the sparse override map) plus a raw value
# and prints the new state on stdout. A no-op input (empty / nothing to add)
# prints the state UNCHANGED and returns rc 1, so a caller can `new="$(edit_…)"
# || return 1` to skip a commit. Pure: JSON in/out, no TTY.
#
# Used by: lib/guided/controller.sh, lib/guided/shell.sh.
# =============================================================================
# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

# shellcheck source=./config-state.sh
declare -F config_state_set >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/config-state.sh"

# shellcheck source=../common.sh
declare -F json_string_array >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../common.sh"

# edit_set_scalar <state> <path> <str> — a string scalar at a dotted path.
# rc 1 (unchanged) on empty input.
edit_set_scalar() {
  local state="$1" path="$2" value="$3"
  [[ -n "$value" ]] || { printf '%s' "$state"; return 1; }
  # The value as a JSON string.
  config_state_set "$state" "$path" "$(jq -n --arg x "$value" '$x')"
}

# edit_set_bool <state> <path> <true|false> — a JSON bool at a dotted path.
# rc 1 (unchanged) when the value is neither literal.
edit_set_bool() {
  local state="$1" path="$2" value="$3"
  [[ "$value" == "true" || "$value" == "false" ]] \
    || { printf '%s' "$state"; return 1; }
  config_state_set "$state" "$path" "$value"
}

# edit_set_array <state> <path> <val...> — a JSON string array at a dotted path
# (pick order preserved). rc 1 (unchanged) when nothing is passed.
edit_set_array() {
  local state="$1" path="$2"; shift 2
  (($#)) || { printf '%s' "$state"; return 1; }
  config_state_set "$state" "$path" "$(json_string_array "$@")"
}

# edit_set_gpu <state> <val...> — environment.gpu: `auto` is mutually exclusive
# (clears vendors, stores the scalar "auto"); otherwise the vendor list as an
# array. rc 1 (unchanged) when nothing is passed.
edit_set_gpu() {
  local state="$1"; shift
  (($#)) || { printf '%s' "$state"; return 1; }
  local vendor
  for vendor in "$@"; do
    [[ "$vendor" == "auto" ]] \
      && { config_state_set "$state" environment.gpu '"auto"'; return 0; }
  done
  config_state_set "$state" environment.gpu "$(json_string_array "$@")"
}

# edit_set_sysctl <state> <key> <value> — set/override one sysctl pair. The key
# is a LITERAL object key (a dotted `vm.swappiness` is NOT a nested path), and a
# numeric value is stored as a number. rc 1 (unchanged) on an empty key.
edit_set_sysctl() {
  local state="$1" key="$2" value="$3"
  [[ -n "$key" ]] || { printf '%s' "$state"; return 1; }
  # The state with sysctl[key] set (a number when the value is one).
  printf '%s\n' "$state" | jq --arg k "$key" --arg v "$value" \
    '.sysctl[$k] = ($v | (tonumber? // .))'
}

# edit_append_packages <state> <raw> — whitespace-split package name(s) appended
# to the `extra` category of packages.repo. rc 1 (unchanged) on empty input.
# The former top-level packages.extra was packages.repo without a category, so
# the row now writes into the one repo slot and stays canonical for Save/Export.
edit_append_packages() {
  local state="$1" raw="$2" slot="${3:-repo}" append
  [[ -n "$raw" ]] || { printf '%s' "$state"; return 1; }
  append='.packages[$slot].extra = ((.packages[$slot].extra // [])'
  append+=' + ($s | split(" ") | map(select(length > 0))))'
  # The state with the space-separated names added to the slot's extra list.
  printf '%s\n' "$state" | jq --arg s "$raw" --arg slot "$slot" "$append"
}

# edit_append_host_programs <state> <name...> — dedup-append host System
# Program name(s) to host_programs. rc 1 (unchanged) when nothing is passed.
edit_append_host_programs() {
  local state="$1"; shift
  (($#)) || { printf '%s' "$state"; return 1; }
  local append='.host_programs = ((.host_programs // []) + $add | unique)'
  # The state with the names added to host_programs (sorted, each once).
  printf '%s\n' "$state" \
    | jq --argjson add "$(json_string_array "$@")" "$append"
}

# edit_append_persist <state> <dir> — append one absolute directory to
# persist.directories. rc 1 (unchanged) on empty input.
edit_append_persist() {
  local state="$1" directory="$2"
  [[ -n "$directory" ]] || { printf '%s' "$state"; return 1; }
  local append='.persist.directories = ((.persist.directories // []) + [$p])'
  # The state with the directory added to persist.directories.
  printf '%s\n' "$state" | jq --arg p "$directory" "$append"
}

# edit_remove_persist <state> <dir> — drop one directory from
# persist.directories (ADR 0066). rc 1 (unchanged) on empty input or a dir not
# in the list; removing the last entry leaves an empty list.
edit_remove_persist() {
  local state="$1" directory="$2"
  [[ -n "$directory" ]] || { printf '%s' "$state"; return 1; }
  local find='(.persist.directories // []) | index($p)'
  local remove='.persist.directories = ((.persist.directories // []) - [$p])'
  # Is the directory in the list?
  printf '%s\n' "$state" | jq -e --arg p "$directory" "$find" >/dev/null \
    || { printf '%s' "$state"; return 1; }
  # The state without it.
  printf '%s\n' "$state" | jq --arg p "$directory" "$remove"
}

# edit_apply_skeleton <state> <skeleton-json> — drop any previous pool-skeleton
# keys, then merge the new skeleton in (switching layouts never leaves a stale
# group behind).
edit_apply_skeleton() {
  local state="$1" skeleton="$2"
  local apply='del(.os_pool, .storage_groups, .data_pools) * $sk'
  # The state with the new skeleton in place of the old one.
  printf '%s\n' "$state" | jq --argjson sk "$skeleton" "$apply"
}

# edit_add_sysctl_pair <state> <key=value> — parse a "key=value" entry and set
# the pair via edit_set_sysctl. rc 1 (unchanged) on a malformed entry (no `=`).
edit_add_sysctl_pair() {
  local state="$1" raw="$2" key value
  [[ "$raw" == *=* ]] || { printf '%s' "$state"; return 1; }
  # The key before the first `=`, the value after it.
  key="$(printf '%s\n' "$raw" | cut -d= -f1)"
  value="$(printf '%s\n' "$raw" | cut -d= -f2-)"
  edit_set_sysctl "$state" "$key" "$value"
}

# edit_add_mirror_server <state> <url> — dedup-append a custom mirror Server=
# URL to options.mirror_servers (ADR 0072). rc 1 (unchanged) on empty input.
edit_add_mirror_server() {
  local state="$1" url="$2" servers
  [[ -n "$url" ]] || { printf '%s' "$state"; return 1; }
  local add='if any($a[]; . == $v) then $a else $a + [$v] end'
  # The current servers, then them with the URL added (once).
  servers="$(printf '%s\n' "$state" | jq -c '.options.mirror_servers // []')"
  servers="$(jq -cn --argjson a "$servers" --arg v "$url" "$add")"
  config_state_set "$state" options.mirror_servers "$servers"
}

# edit_add_custom_repository <state> <"name url [sign_check] [sign_option]"> —
# an archinstall-style custom repo appended dedup by name (ADR 0072); sign_check
# / sign_option default to Required / TrustedOnly. rc 1 on fewer than 2 tokens.
edit_add_custom_repository() {
  local state="$1" raw="$2" repositories
  local -a fields
  read -ra fields < <(printf '%s\n' "$raw")
  [[ ${#fields[@]} -ge 2 ]] || { printf '%s' "$state"; return 1; }
  local add='if any($a[]; .name == $n) then $a'
  add+=' else $a + [{name:$n, url:$u, sign_check:$c, sign_option:$o}] end'
  # The current repositories, then them with this one added (by name, once).
  repositories="$(printf '%s\n' "$state" \
    | jq -c '.options.custom_repositories // []')"
  repositories="$(jq -cn --argjson a "$repositories" \
    --arg n "${fields[0]}" --arg u "${fields[1]}" \
    --arg c "${fields[2]:-Required}" --arg o "${fields[3]:-TrustedOnly}" \
    "$add")"
  config_state_set "$state" options.custom_repositories "$repositories"
}

# edit_set_users <state> <name...> — set .users to the order-preserving dedup of
# the names (users[0] = Primary User). With NO names the key is unset (a host
# may carry no user). Always rc 0 — clearing is a real edit, not a no-op.
edit_set_users() {
  local state="$1" name kept
  shift
  if (($# == 0)); then
    config_state_unset "$state" users
    return 0
  fi
  local -a users=()
  for name in "$@"; do
    for kept in "${users[@]}"; do
      [[ "$kept" == "$name" ]] && continue 2
    done
    users+=("$name")
  done
  config_state_set "$state" users "$(json_string_array "${users[@]}")"
}

# edit_user_name_problem <name> — rc 0 for a login useradd accepts and the
# installer can own; else rc 1 and the reason on stdout. Checked when the name
# is typed, not at useradd after the disks are wiped.
edit_user_name_problem() {
  local name="$1"
  if [[ ! "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    printf '%s\n' "'${name}': use 1-32 of a-z 0-9 _ -, starting with a" \
      "letter or _"
    return 1
  fi
  case "$name" in
  root | core | greeter | sddm | nobody | bin | daemon | mail | ftp | http \
    | dbus | systemd-*)
    printf '%s\n' "'${name}' is a reserved system account"
    return 1 ;;
  esac
  return 0
}
