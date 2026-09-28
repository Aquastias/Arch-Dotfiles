#!/usr/bin/env bats
# Trust signals from the AUR RPC (ADR 0143/0149), served from fixtures: new
# or adopted packages are suspicious; an unreachable RPC aborts unattended.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

_days_ago() { echo $(($(date +%s) - $1 * 86400)); }

@test "trust: a package first submitted days ago is suspicious" {
  local d; d="$(aurvet_clone electron-benign)"
  aurvet_rpc electron-benign FirstSubmitted="$(_days_ago 3)"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-new AUR:0"* ]]
}

@test "trust: a recently changed-hands (adopted) package is suspicious" {
  aurvet_rpc electron-benign Maintainer='"adopter"' \
    Submitter='"original"' LastModified="$(_days_ago 2)"
  aurvet_hook "$(aurvet_clone electron-benign)"
  [[ "$output" == *"SUSPICIOUS trust-adopted AUR:0"* ]]
}

@test "trust: orphaned, out-of-date and low-vote packages are info only" {
  local d; d="$(aurvet_clone electron-benign)"
  aurvet_rpc electron-benign Maintainer=null \
    OutOfDate="$(_days_ago 30)" NumVotes=1
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO trust-orphaned"* ]]
  [[ "$output" == *"INFO trust-out-of-date"* ]]
  [[ "$output" == *"INFO trust-low-votes"* ]]
}

@test "trust: a base the AUR doesn't know is suspicious" {
  local d; d="$(aurvet_clone electron-benign)"
  printf '{"resultcount":0,"results":[],"type":"multiinfo","version":5}\n' \
    > "$AUR_VET_RPC_FIXTURE_DIR/electron-benign.json"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-not-found"* ]]
}

@test "trust: RPC unreachable retries, then aborts unattended" {
  local d; d="$(aurvet_clone electron-benign)"
  AURVET_NO_RPC=1 aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RPC attempt 3/3 failed"* ]]
  [[ "$output" == *"AUR RPC unreachable"* ]]
}

@test "trust: RPC unreachable interactive can continue without signals" {
  local d; d="$(aurvet_clone electron-benign)"
  AURVET_NO_RPC=1 aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  [[ "$output" == *"without trust signals"* ]]
}

@test "indicators: a backdated commit can't dodge the window (LastModified)" {
  # 123pan-bin is on the Atomic Arch list; the commit claims 2026-09 but the
  # AUR (server-side) says it was modified inside the campaign window.
  local d; d="$(aurvet_case pkgbase '123pan-bin@2026-09-01T12:00:00' bd)"
  aurvet_rpc 123pan-bin LastModified="$(date -d 2026-06-11 +%s)"
  aurvet_hook "$d" 123pan-bin
  [[ "$output" == *"CRITICAL indicator-pkgbase "* ]]
}

@test "indicators: any in-window commit in history stays critical" {
  local d; d="$(aurvet_case pkgbase '123pan-bin@2026-06-11T12:00:00' hist)"
  GIT_COMMITTER_DATE=2026-09-01T12:00:00 aurvet_commit "$d" PKGBUILD \
    's/^pkgrel=1$/pkgrel=2/'
  aurvet_hook "$d" 123pan-bin
  [[ "$output" == *"CRITICAL indicator-pkgbase "* ]]
}
