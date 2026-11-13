#!/usr/bin/env bash
# =============================================================================
# tools/aur-trust.sh — review and trust a newly adopted AUR package
# =============================================================================
# Usage: aur-trust.sh <pkgbase>
#
# aur-vet aborts unattended installs on `trust-adopted`: the package changed
# hands under 14 days ago (ADR 0149). This is the reviewed fast path instead
# of waiting the window out. It shows the takeover from the AUR RPC (server
# side: git authors are self-reported), clones the package (never sourcing
# its PKGBUILD), prints the commits and diff since the newest author took
# over and whether sources, checksums or install scripts changed, then asks.
# Only an explicit "y" appends the row to the repo allowlist
# (.installer/aur/allow.tsv); commit and push it to reach installs.
#
# Overrides (tests): AUR_TRUST_GIT_URL (clone base), AUR_TRUST_ALLOW (the
# allowlist), AUR_VET_RPC_FIXTURE_DIR (RPC answers as <pkgbase>.json).
# Exit: 0 trusted or already trusted · 1 declined or nothing to trust ·
# 2 usage/environment error.
# =============================================================================

# The jq programs held in single-quoted variables use jq's $names.
# shellcheck disable=SC2016

set -euo pipefail

script_path="${BASH_SOURCE[0]}"
[[ "$script_path" == */* ]] || script_path="./$script_path"
SCRIPT_DIR="$(cd "${script_path%/*}" && pwd)"
INSTALLER_DIR="$(dirname "$SCRIPT_DIR")"

AUR_URL="${AUR_TRUST_GIT_URL:-https://aur.archlinux.org}"
ALLOW="${AUR_TRUST_ALLOW:-${INSTALLER_DIR}/aur/allow.tsv}"
TRUST_WINDOW=$((14 * 86400))   # aur-vet's trust-adopted window

main() {
  local base="${1:-}"
  aur_trust_check_name "$base"
  if aur_trust_is_allowed "$base"; then
    aur_trust_say "${base}: already trusted in ${ALLOW}"
    return 0
  fi
  local maintainer submitter modified
  aur_trust_read_takeover "$base"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  git clone -q "${AUR_URL}/${base}.git" "$WORK/$base" \
    || aur_trust_die "${base}: clone from ${AUR_URL} failed"
  local boundary head note
  boundary="$(aur_trust_boundary "$WORK/$base")"
  head="$(git -C "$WORK/$base" rev-parse --short HEAD)"
  aur_trust_show_history "$WORK/$base" "$boundary"
  note="${head} $(aur_trust_show_changes "$WORK/$base" "$boundary")"
  aur_trust_confirm "$base" "$note"
}

aur_trust_say() { printf 'aur-trust: %s\n' "$*" >&2; }
aur_trust_die() { aur_trust_say "$*"; exit 2; }

# aur_trust_clean — stdin with control characters made visible: the RPC
# answer and the package repo are attacker text, and must not drive the
# terminal.
aur_trust_clean() { awk -f "$SCRIPT_DIR/aur-trust-clean.awk"; }

# aur_trust_check_name <pkgbase> — exit 2 unless an AUR-shaped name.
aur_trust_check_name() {
  [[ "$1" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]] \
    || aur_trust_die "usage: aur-trust.sh <pkgbase>"
}

# aur_trust_is_allowed <pkgbase> — a trust-adopted row already exists.
aur_trust_is_allowed() {
  local base kind
  [[ -f "$ALLOW" ]] || return 1
  while IFS=$'\t' read -r base kind _; do
    [[ "$base" == "$1" && "$kind" == trust-adopted ]] && return 0
  done < "$ALLOW"
  return 1
}

# aur_trust_rpc <pkgbase> — the AUR RPC `info` answer.
aur_trust_rpc() {
  if [[ -n "${AUR_VET_RPC_FIXTURE_DIR:-}" ]]; then
    cat "$AUR_VET_RPC_FIXTURE_DIR/$1.json"
  else
    local encoded
    # The name with each "+" URL-encoded.
    encoded="$(jq -r -n --arg b "$1" '$b | gsub("\\+"; "%2B")')"
    curl -gfsS --max-time 20 \
      "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=${encoded}"
  fi
}

# aur_trust_read_takeover <pkgbase> — fill maintainer/submitter/modified (the
# caller's locals) from the RPC; exit 1 when the package did not change hands.
aur_trust_read_takeover() {
  local json fields now
  local takeover='[.results[] | select(.PackageBase == $b)][0] // empty'
  takeover+=' | [.Maintainer // "", .Submitter // "", .LastModified // 0]'
  takeover+=' | map(tostring) | join("\u001f")'
  json="$(aur_trust_rpc "$1")" || aur_trust_die "$1: AUR RPC unreachable"
  # The package's maintainer, submitter and last-modified time, \x1f-joined.
  fields="$(printf '%s\n' "$json" | jq -r --arg b "$1" "$takeover")" \
    || aur_trust_die "$1: AUR RPC answer malformed"
  [[ -n "$fields" ]] || aur_trust_die "$1: not on the AUR"
  IFS=$'\x1f' read -r maintainer submitter modified \
    < <(printf '%s\n' "$fields")
  # Names reach the allowlist note: AUR account names only.
  [[ "$maintainer" =~ ^[A-Za-z0-9._-]*$ && "$submitter" =~ ^[A-Za-z0-9._-]*$
     && "$modified" =~ ^[0-9]+$ ]] \
    || aur_trust_die "$1: AUR RPC answer malformed"
  if [[ -z "$maintainer" || "$maintainer" == "$submitter" ]]; then
    aur_trust_say "$1: not adopted (maintainer ${maintainer:-none}," \
      "submitter ${submitter}) — nothing to trust"
    exit 1
  fi
  now="$(date +%s)"
  aur_trust_say "$1: ${submitter} -> ${maintainer}, last modified" \
    "$(date -u -d "@${modified}" +%F)"
  ((now - modified < TRUST_WINDOW)) \
    || aur_trust_say "$1: older than aur-vet's 14-day window (not flagged)"
}

# aur_trust_boundary <clone> — the last commit before the newest author took
# over (the empty tree when one author wrote it all). Authors are
# self-reported: this only scopes the review, the RPC decides the takeover.
aur_trust_boundary() {
  local newest boundary="" hash author
  newest="$(git -C "$1" log -n 1 --format=%an)"
  # The newest commit by someone else.
  while IFS=$'\x1f' read -r hash author; do
    if [[ "$author" != "$newest" ]]; then boundary="$hash"; break; fi
  done < <(git -C "$1" log --format='%H%x1f%an')
  [[ -n "$boundary" ]] || boundary="$(git hash-object -t tree /dev/null)"
  printf '%s\n' "$boundary"
}

# aur_trust_show_history <clone> <boundary> — recent commits, then the diff
# since the boundary.
aur_trust_show_history() {
  aur_trust_say "recent commits (authors self-reported):"
  git -C "$1" log -n 12 --date=short --format='  %h %ad %an: %s' \
    | aur_trust_clean >&2
  aur_trust_say "changes since the newest author took over:"
  git -C "$1" --no-pager diff --no-color "$2" HEAD | aur_trust_clean >&2
}

# aur_trust_srcinfo_sources <clone> <rev> — the .SRCINFO lines that decide
# what is built and run: sources, checksums, install and changelog scripts.
aur_trust_srcinfo_sources() {
  # The revision's build-deciding .SRCINFO lines, sorted.
  git -C "$1" show "$2:.SRCINFO" 2>/dev/null \
    | awk -f "$SCRIPT_DIR/aur-trust-srcinfo.awk" | sort
}

# aur_trust_show_changes <clone> <boundary> — print the verdict on sources,
# checksums and install scripts (and any added file) to stderr; the default
# allowlist note to stdout.
aur_trust_show_changes() {
  local changes added
  # The changed lines (diff's < and > lines) between the two revisions.
  changes="$(diff <(aur_trust_srcinfo_sources "$1" "$2") \
    <(aur_trust_srcinfo_sources "$1" HEAD) | grep -E '^[<>]')" || true
  # The files added since the boundary, the build files aside.
  added="$(git -C "$1" diff --name-only --diff-filter=A "$2" HEAD \
    | grep -vxE 'PKGBUILD|\.SRCINFO|\.gitignore')" || true
  [[ -z "$added" ]] \
    || aur_trust_say "ADDED files: $(printf '%s\n' "$added" | aur_trust_clean)"
  if [[ -z "$changes" ]]; then
    aur_trust_say "sources, checksums, install: unchanged"
    echo "sources+sums unchanged"
  else
    aur_trust_say "sources, checksums, install: CHANGED"
    printf '%s\n' "$changes" | aur_trust_clean >&2
    echo "SOURCES CHANGED, reviewed"
  fi
}

# aur_trust_confirm <pkgbase> <default-note> — ask; on "y" append the row.
aur_trust_confirm() {
  local answer note
  printf 'aur-trust: trust %s (adopted from %s) for %s? [y/N] ' \
    "$maintainer" "$submitter" "$1" >&2
  read -r answer || answer=""
  if [[ "$answer" != y && "$answer" != Y ]]; then
    aur_trust_say "$1: not trusted"
    exit 1
  fi
  printf 'aur-trust: note [%s]: ' "$2" >&2
  read -r note || note=""
  # The note with tabs made spaces (the allowlist is tab-separated).
  note="$(printf '%s' "$note" | tr '\t' ' ')"
  printf '%s\ttrust-adopted\treviewed %s (%s adopted from %s; %s)\n' \
    "$1" "$(date -u +%F)" "$maintainer" "$submitter" "${note:-$2}" \
    >> "$ALLOW"
  aur_trust_say "$1: trusted in ${ALLOW} — commit and push to reach installs"
}

main "$@"
