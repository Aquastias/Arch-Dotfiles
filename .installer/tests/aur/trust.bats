#!/usr/bin/env bats
# Trust signals from the AUR RPC (ADR 0143), served from fixtures: a
# maintainer change is critical even on a bump-only diff; new or adopted
# packages are suspicious; an unreachable RPC aborts unattended.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

_days_ago() { echo $(($(date +%s) - $1 * 86400)); }

_bump() { # pinned electron-benign, then a clean version bump
  local d; d="$(aurvet_clone_pinned electron-benign)"
  local s1 s8; s1="$(printf '1%.0s' {1..64})"; s8="$(printf '8%.0s' {1..64})"
  sed -i "s/2\.3\.1/2.4.0/g; s/$s1/$s8/" "$d/.SRCINFO"
  aurvet_commit "$d" PKGBUILD "s/^pkgver=2.3.1/pkgver=2.4.0/; s/$s1/$s8/"
  printf '%s\n' "$d"
}

@test "trust: maintainer change aborts even a clean bump-only diff" {
  local d; d="$(_bump)"
  aurvet_rpc electron-benign Maintainer='"new-owner"'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL trust-maintainer-changed AUR:0"* ]]
  [[ "$output" == *"fixture-maintainer -> new-owner"* ]]
}

@test "trust: same maintainer on a bump-only diff passes" {
  local d; d="$(_bump)"
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
}

@test "trust: a package first submitted days ago is suspicious" {
  local d; d="$(aurvet_clone_pinned electron-benign)"
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
  local d; d="$(aurvet_clone_pinned electron-benign)"
  aurvet_rpc electron-benign Maintainer=null \
    OutOfDate="$(_days_ago 30)" NumVotes=1
  : > "$AUR_VET_STORE/vetted.tsv"; aurvet_pin "$d" electron-benign ""
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO trust-orphaned"* ]]
  [[ "$output" == *"INFO trust-out-of-date"* ]]
  [[ "$output" == *"INFO trust-low-votes"* ]]
}

@test "trust: a base the AUR doesn't know is suspicious" {
  local d; d="$(aurvet_clone_pinned electron-benign)"
  printf '{"resultcount":0,"results":[],"type":"multiinfo","version":5}\n' \
    > "$AUR_VET_RPC_FIXTURE_DIR/electron-benign.json"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-not-found"* ]]
}

@test "trust: RPC unreachable retries, then aborts unattended" {
  local d; d="$(aurvet_clone_pinned electron-benign)"
  AURVET_NO_RPC=1 aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RPC attempt 3/3 failed"* ]]
  [[ "$output" == *"AUR RPC unreachable"* ]]
}

@test "trust: RPC unreachable interactive can continue without signals" {
  local d; d="$(aurvet_clone_pinned electron-benign)"
  AURVET_NO_RPC=1 aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  [[ "$output" == *"without trust signals"* ]]
}

@test "trust: an accepted package records the RPC maintainer in its pin" {
  aurvet_rpc electron-benign Maintainer='"alice"' Submitter='"alice"'
  aurvet_hook_answer "$(aurvet_clone electron-benign)" y
  [ "$status" -eq 0 ]
  awk -F'\t' '$1 == "electron-benign" && $3 == "alice" { f = 1 }
    END { exit !f }' "$AUR_VET_STORE/vetted.tsv"
}

@test "trust: a pin without a recorded maintainer is suspicious (review fix)" {
  local d; d="$(aurvet_clone electron-benign)"
  aurvet_pin "$d" electron-benign ""
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-maintainer-unrecorded"* ]]
  aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
}
