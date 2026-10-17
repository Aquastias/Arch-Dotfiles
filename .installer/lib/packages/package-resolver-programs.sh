#!/usr/bin/env bash
# =============================================================================
# lib/packages/package-resolver-programs.sh — Package Resolver program sets
# =============================================================================
# The Host Programs and each declared user's User Programs (ADR 0157), so the
# report covers the whole install and not only the package slots.
#
# Used by: lib/packages/package-resolver.sh (sources it; uses its
# _package_resolver_emit / _package_resolver_jq / _package_resolver_services).
# =============================================================================

# shellcheck source=../config/profile-loader.sh
declare -F profile_loader_load_user >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/profile-loader.sh"

# _package_resolver_programs_host <config> — the authored and base Host
# Programs. The toggle-derived ones are skipped: their own source (printing,
# mirrors, bluetooth, power) already reports them.
_package_resolver_programs_host() {
  local config="$1" program derived="" line
  while IFS= read -r line; do
    derived+="${line##*$'\t'}"$'\n'
  done < <(_package_resolver_services "$config")
  while IFS= read -r program; do
    [[ -n "$program" ]] || continue
    [[ $'\n'"$derived" == *$'\n'"$program"$'\n'* ]] && continue
    _package_resolver_emit host-programs host "$program"
  done < <(_package_resolver_jq "$config" '(.host_programs // [])[]')
}

# _package_resolver_programs_user <config> — each declared user's User
# Programs, resolved over User Core; the layer column names the user. A user
# with no User Profile resolves to User Core alone.
_package_resolver_programs_user() {
  local config="$1" user user_json program
  while IFS= read -r user; do
    [[ -n "$user" ]] || continue
    user_json="$(profile_loader_load_user "$user" 2>/dev/null)" || true
    [[ -n "$user_json" ]] || continue
    while IFS= read -r program; do
      _package_resolver_emit user-programs "$user" "$program"
    done < <(_package_resolver_jq "$user_json" '(.programs // [])[]')
  done < <(_package_resolver_jq "$config" '(.users // [])[]
    | if type == "object" then .name else . end')
}
