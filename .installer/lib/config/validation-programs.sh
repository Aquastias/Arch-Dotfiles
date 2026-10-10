#!/usr/bin/env bash
# =============================================================================
# lib/config/validation-programs.sh — program contract validation
# =============================================================================
# The program side of the validation seam: every referenced program exists
# with the right kind, user references reconcile (ADR 0036), `requires` are
# installed first (ADR 0065) and no two `conflicts` rivals reach one machine
# (ADR 0115).
#
# Used by: lib/config/validation.sh (sources it;
# validation_check_install_context runs _validation_preflight_programs).
# =============================================================================

# =============================================================================
# PROGRAM PREFLIGHT
# =============================================================================
# Validates all program contracts for <profile> and its users.
# Requires INSTALLER_DIR set and program_registry_build already called.
# Returns immediately (no-op) if no core profiles are present — profiles will
# be skipped at runtime and there is nothing to validate.
# Exits via error() on any validation failure or corrupt core profile.

_validation_preflight_programs() {
  local profile="$1"
  [[ -f "${INSTALLER_DIR}/hosts/core/profile.jsonc" ]] || return 0
  [[ -f "${INSTALLER_DIR}/users/core/profile.jsonc" ]] || return 0

  local host_json rc=0
  host_json="$(profile_loader_load "$profile" 2>/dev/null)" || rc=$?
  case "$rc" in
  1) return 0 ;;
  2) error "validation: cannot load host core profile." ;;
  3) error "validation: host profile '${profile}' is reserved." ;;
  esac

  local -a host_programs users
  mapfile -t host_programs < <(printf '%s' "$host_json" \
    | jq -r '.host_programs[]?')
  mapfile -t users < <(printf '%s' "$host_json" | jq -r '.users[]?')

  local user
  for user in "${users[@]}"; do
    [[ -d "${INSTALLER_DIR}/users/${user}" ]] ||
      error "Host config references user '${user}' but" \
            "${INSTALLER_DIR}/users/${user}/ does not exist."
  done

  local any_fail=0
  if ((${#host_programs[@]} > 0)); then
    program_registry_validate_all "host" "${host_programs[@]}" || any_fail=1
  fi

  # Host-program JSON array for the requires-order check (ADR 0065), built
  # once — it is the same for every user. Drops the empty-list sentinel.
  local host_programs_json
  host_programs_json="$(printf '%s\n' \
    "${host_programs[@]+"${host_programs[@]}"}" \
    | jq -R . | jq -sc 'map(select(length > 0))')"

  for user in "${users[@]}"; do
    _validation_check_user_programs "$user" "$host_programs_json" \
      "${host_programs[@]+"${host_programs[@]}"}" || any_fail=1
  done

  ((any_fail == 0)) || \
    error "Program contracts failed. Fix the errors above and re-run."
}

# _validation_check_user_programs <user> <host-programs-json> <host-program…>
# — rc 1 (reasons on stderr) when <user>'s profile cannot load or one of its
# programs fails reconciliation, ordering or conflicts.
_validation_check_user_programs() {
  local user="$1" host_programs_json="$2"
  shift 2
  local user_json load_rc=0 failed=0
  user_json="$(profile_loader_load_user "$user" 2>/dev/null)" || load_rc=$?
  case "$load_rc" in
  0 | 1) ;;
  *) echo "validation: cannot load user profile '${user}'" >&2
     return 1 ;;
  esac

  # Reconcile each user program reference (ADR 0036): system:false installs at
  # user level; a host-installed Host Program is a no-op; a Host Program no
  # host installs aborts (reconcile prints the actionable why).
  local -a user_programs
  local program
  mapfile -t user_programs < <(printf '%s' "$user_json" | jq -r '.programs[]?')
  for program in "${user_programs[@]}"; do
    program_registry_reconcile_user_program "$program" "$@" >/dev/null \
      || failed=1
  done

  # Dependency ordering (ADR 0065): each program's `requires` must be
  # installed first — a Host Program or an earlier entry in this list. Mutual
  # exclusion (ADR 0115): no program's `conflicts` may name another program
  # that also reaches this machine (Host Program or user's own).
  local programs_json
  programs_json="$(printf '%s' "$user_json" | jq -c '.programs // []')"
  _validation_check_requires_order "$user" "$host_programs_json" \
    "$programs_json" || failed=1
  _validation_check_conflicts "$user" "$host_programs_json" \
    "$programs_json" || failed=1
  return "$failed"
}

# =============================================================================
# PROGRAM DEPENDENCY ORDERING (ADR 0065)
# =============================================================================
# A Program may declare `requires: [...]` — Programs whose install-time setup
# must be in place before it runs. The Runner installs in declared order, so the
# dependency must appear earlier. Enforced here, before any side effect, so a
# mis-ordered list aborts up front with an actionable message (the bug that let
# a guided selection put searxng before podman).

# _validation_index_of <needle> <hay...> — 0-based index of the first <hay>
# equal to <needle>, or empty when absent. Pure.
_validation_index_of() {
  local needle="$1"; shift
  local i=0 x
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
}

# _validation_program_requires <prog> — the program's declared `requires` list,
# one per line (empty when none or the program has no config). Pure over
# INSTALLER_DIR.
_validation_program_requires() {
  local relative_path config_file
  relative_path="$(program_registry_resolve "$1" 2>/dev/null)" || return 0
  config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
  [[ -f "$config_file" ]] || return 0
  jsonc_strip "$config_file" | jq -r '.requires[]?' 2>/dev/null
}

# _validation_check_requires_order <user> <host-programs-json> <programs-json> —
# enforce every user program's `requires` for one user. A required program is
# satisfied when it is a Host Program (installed before all user programs) or
# appears EARLIER in this user's own list. Prints an actionable line per
# violation and returns 1 if any; 0 when clean. Pure over INSTALLER_DIR + the
# two JSON array args (host_programs, the user's programs).
_validation_check_requires_order() {
  local user="$1" host_programs_json="$2" programs_json="$3" fail=0
  local -a programs host_programs
  mapfile -t programs  < <(printf '%s' "$programs_json"  | jq -r '.[]?')
  mapfile -t host_programs < <(printf '%s' "$host_programs_json" | jq -r '.[]?')
  local i program required
  for i in "${!programs[@]}"; do
    program="${programs[$i]}"
    while IFS= read -r required; do
      [[ -n "$required" ]] || continue
      _validation_requirement_met "$user" "$program" "$required" "$i" \
        || fail=1
    done < <(_validation_program_requires "$program")
  done
  return "$fail"
}

# _validation_requirement_met <user> <program> <required> <position> — rc 1
# (reason on stderr) unless <required> is a Host Program or listed before
# <position>. Reads the caller's programs / host_programs (dynamic scope).
_validation_requirement_met() {
  local user="$1" program="$2" required="$3" position="$4" required_index
  # A Host Program is installed before every user program.
  [[ -n "$(_validation_index_of "$required" \
    "${host_programs[@]+"${host_programs[@]}"}")" ]] && return 0
  required_index="$(_validation_index_of "$required" "${programs[@]}")"
  if [[ -z "$required_index" ]]; then
    echo "User '${user}': program '${program}' requires '${required}'," \
         "which is not declared in ${user}'s programs." \
         "Add '${required}' before '${program}'." >&2
    return 1
  fi
  ((required_index < position)) && return 0
  echo "User '${user}': program '${program}' requires '${required}'" \
       "installed first, but '${required}' is listed after it." \
       "Move '${required}' before '${program}'." >&2
  return 1
}

# =============================================================================
# PROGRAM MUTUAL EXCLUSION (ADR 0115)
# =============================================================================
# A Program may declare `conflicts: [...]` — other Programs it cannot coexist
# with (e.g. firewalld vs ufw). The relation is symmetric: one side declaring is
# enough. Enforced here, before any side effect, over the combined set that
# reaches a user's machine (Host Programs + the user's own programs), so a
# selection with both a firewall and its rival aborts up front instead of one
# installing + enabling and the other detonating mid-run.

# _validation_program_conflicts <prog> — the program's declared `conflicts`
# list, one per line (empty when none or the program has no config). Pure over
# INSTALLER_DIR.
_validation_program_conflicts() {
  local relative_path config_file
  relative_path="$(program_registry_resolve "$1" 2>/dev/null)" || return 0
  config_file="${INSTALLER_DIR}/programs/${relative_path}/config.jsonc"
  [[ -f "$config_file" ]] || return 0
  jsonc_strip "$config_file" | jq -r '.conflicts[]?' 2>/dev/null
}

# _validation_check_conflicts <user> <host-programs-json> <programs-json> —
# enforce every program's `conflicts` for one user. The present set is the union
# of Host Programs and the user's programs. For each present program, a declared
# conflict that is also present is a violation. Symmetric declarations and the
# two directions of one pair are de-duplicated to a single unordered-pair
# message. Prints an actionable line per distinct violating pair and returns 1
# if any; 0 when clean. Pure over INSTALLER_DIR + the two JSON array args.
_validation_check_conflicts() {
  local user="$1" host_programs_json="$2" programs_json="$3" fail=0
  local -a present
  mapfile -t present < <(
    { printf '%s' "$host_programs_json" | jq -r '.[]?'
      printf '%s' "$programs_json" | jq -r '.[]?'; } | sort -u)
  local program rival seen=""
  for program in "${present[@]}"; do
    [[ -n "$program" ]] || continue
    while IFS= read -r rival; do
      [[ -n "$rival" ]] || continue
      # Present on this machine? Otherwise the conflict is inert.
      [[ -n "$(_validation_index_of "$rival" "${present[@]}")" ]] || continue
      # Canonical unordered-pair key so A→B and B→A report once.
      local key
      key="${rival}|${program}"
      [[ "$program" < "$rival" ]] && key="${program}|${rival}"
      [[ " $seen " == *" $key "* ]] && continue
      seen="$seen $key"
      echo "User '${user}': programs '${program}' and '${rival}' conflict" \
           "and cannot both be installed. Remove one." >&2
      fail=1
    done < <(_validation_program_conflicts "$program")
  done
  return "$fail"
}

