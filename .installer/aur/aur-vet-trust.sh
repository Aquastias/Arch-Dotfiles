#!/usr/bin/env bash
# =============================================================================
# aur-vet-trust.sh — aur-vet's trust signals from the AUR RPC (ADR 0143)
# =============================================================================
# Sourced by aur-vet (it provides say, die, data_directory and
# library_directory). Server-side fields only: git author/committer is
# attacker-set (ADR 0149).
# =============================================================================

RPC_URL="https://aur.archlinux.org/rpc/v5/info"
# An AUR package name (aurweb): lowercase alnum and @._+-, nothing else.
AUR_NAME='[a-z0-9@._+-]+'
TRUST_WINDOW=$((14 * 86400))

# query_name <name> — <name> for a URL query: each + written as %2B (a bare
# + reads as a space).
query_name() {
  local name="$1" encoded="" index character
  for ((index = 0; index < ${#name}; index++)); do
    character="${name:index:1}"
    if [[ "$character" == + ]]; then encoded+=%2B
    else encoded+="$character"; fi
  done
  printf '%s\n' "$encoded"
}

# One RPC `info` answer for <pkgbase> (queried by <pkgname>), valid JSON or
# failure. Tests serve <pkgbase>.json from AUR_VET_RPC_FIXTURE_DIR instead.
rpc_fetch() {
  local output query
  if [[ -n "${AUR_VET_RPC_FIXTURE_DIR:-}" ]]; then
    output="$(cat "$AUR_VET_RPC_FIXTURE_DIR/$1.json" 2>/dev/null)" || return 1
  else
    query="$(query_name "$2")"
    output="$(curl -gfsS --max-time 20 "${RPC_URL}?arg%5B%5D=${query}")" \
      || return 1
  fi
  # Is it JSON with a results array?
  printf '%s\n' "$output" \
    | jq -e '.results | type == "array"' >/dev/null 2>&1 || return 1
  printf '%s\n' "$output"
}

# Run <command...> with the RPC retry policy (ADR 0052 pattern):
# AUR_VET_RETRY_DELAYS is the CSV of per-gap seconds. Prints the output of
# the first success; non-zero when every attempt failed.
rpc_retry() {
  local -a delays
  IFS=, read -ra delays < <(printf '%s\n' "${AUR_VET_RETRY_DELAYS:-3,10}")
  local tries=$((${#delays[@]} + 1)) attempt output
  for ((attempt = 1; attempt <= tries; attempt++)); do
    if output="$("$@")"; then
      printf '%s\n' "$output"
      return 0
    fi
    say "RPC attempt ${attempt}/${tries} failed"
    ((attempt < tries)) && sleep "${delays[attempt - 1]:-0}"
  done
  return 1
}

rpc_info() { rpc_retry rpc_fetch "$@"; }

# The RPC answer for the clone at <directory> <pkgbase> (queried by its first
# pkgname), or failure when unreachable.
rpc_for() {
  local name="" line
  if [[ -r "$1/.SRCINFO" ]]; then
    # The first "pkgname = <name>" line.
    while IFS= read -r line; do
      if [[ "$line" == "pkgname = "* ]]; then
        name="${line:10}"
        break
      fi
    done < "$1/.SRCINFO"
  fi
  # .SRCINFO is attacker text: only an AUR-shaped name may reach the URL.
  [[ "$name" =~ ^$AUR_NAME$ ]] || name="$2"
  rpc_info "$2" "$name"
}

# last_modified <json> <pkgbase> — the package's LastModified epoch from an
# RPC answer ("" when it has none).
last_modified() {
  # shellcheck disable=SC2016  # $b is jq's
  local program='[.results[] | select(.PackageBase == $b)][0]'
  program+='.LastModified // empty'
  # The package's LastModified.
  printf '%s\n' "$1" | jq -r --arg b "$2" "$program"
}

# Trust findings (scan TSV shape, file "AUR") from the RPC <json> for
# <pkgbase>.
trust() {
  local json="$1" base="$2" rule_id rule_severity rule_description result
  local -A severity_of=() description_of=()
  local rules engine
  rules="$(data_directory)/rules.tsv"
  engine="$(library_directory)/scan.awk"
  # The trust rules of rules.tsv: id, severity, description.
  while IFS=$'\t' read -r rule_id rule_severity rule_description; do
    severity_of[$rule_id]="$rule_severity"
    description_of[$rule_id]="$rule_description"
  done < <(awk -v rules="$rules" -v list_trust=1 -f "$engine" </dev/null)

  # shellcheck disable=SC2016  # $b is jq's
  local pick='[.results[] | select(.PackageBase == $b)][0] // empty'
  # The package's own result object.
  result="$(printf '%s\n' "$json" | jq -c --arg b "$base" "$pick")"
  if [[ -z "$result" ]]; then
    trust_row trust-not-found
    return 0
  fi
  local maintainer submitter first last out_of_date votes now fields
  fields='[.Maintainer // "", .Submitter // "", .FirstSubmitted // 0,'
  fields+=' .LastModified // 0, .OutOfDate // "", .NumVotes // 0]'
  fields+=' | map(tostring) | join("\u001f")'
  # The six fields on one line, \037-separated.
  IFS=$'\x1f' read -r maintainer submitter first last out_of_date votes \
    < <(printf '%s\n' "$result" | jq -r "$fields")
  # Numbers only: these reach shell arithmetic, and the RPC is untrusted.
  [[ "$first" =~ ^[0-9]+$ && "$last" =~ ^[0-9]+$ && "$votes" =~ ^[0-9]+$ ]] \
    || die "${base}: AUR RPC answer malformed"
  now="${AUR_VET_NOW:-$(date +%s)}"
  if [[ -n "$maintainer" && -n "$submitter" \
        && "$maintainer" != "$submitter" ]] \
     && ((now - last < TRUST_WINDOW)); then
    trust_row trust-adopted "${submitter} -> ${maintainer}"
  fi
  ((now - first < TRUST_WINDOW)) && trust_row trust-new
  [[ -z "$maintainer" ]] && trust_row trust-orphaned
  [[ -n "$out_of_date" ]] && trust_row trust-out-of-date
  ((votes < 3)) && trust_row trust-low-votes "${votes}"
  return 0
}

# trust_row <rule> [detail] — one trust finding, when rules.tsv has <rule>
# (reads trust's severity_of / description_of).
trust_row() {
  [[ -n "${severity_of[$1]:-}" ]] && printf '%s\tAUR\t0\t%s%s\n' \
    "${severity_of[$1]}"$'\t'"$1" "${description_of[$1]}" "${2:+ [$2]}"
  return 0
}
