#!/usr/bin/env bats
# Trust signals from the AUR RPC (ADR 0143/0149), served from fixtures: new
# or adopted packages are suspicious; an unreachable RPC aborts unattended.

load ../lib/aur-vet

setup() { aur_vet_setup; }
teardown() { aur_vet_teardown; }

_days_ago() { echo $(($(date +%s) - $1 * 86400)); }

@test "trust: a package first submitted days ago is suspicious" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  aur_vet_rpc electron-benign FirstSubmitted="$(_days_ago 3)"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-new AUR:0"* ]]
}

@test "trust: a recently changed-hands (adopted) package is suspicious" {
  aur_vet_rpc electron-benign Maintainer='"adopter"' \
    Submitter='"original"' LastModified="$(_days_ago 2)"
  aur_vet_hook "$(aur_vet_clone electron-benign)"
  [[ "$output" == *"SUSPICIOUS trust-adopted AUR:0"* ]]
}

@test "trust: orphaned, out-of-date and low-vote packages are info only" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  aur_vet_rpc electron-benign Maintainer=null \
    OutOfDate="$(_days_ago 30)" NumVotes=1
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO trust-orphaned"* ]]
  [[ "$output" == *"INFO trust-out-of-date"* ]]
  [[ "$output" == *"INFO trust-low-votes"* ]]
}

@test "trust: a base the AUR doesn't know is suspicious" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  printf '{"resultcount":0,"results":[],"type":"multiinfo","version":5}\n' \
    > "$AUR_VET_RPC_FIXTURE_DIR/electron-benign.json"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-not-found"* ]]
}

@test "trust: RPC unreachable retries, then aborts unattended" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  AURVET_NO_RPC=1 aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RPC attempt 3/3 failed"* ]]
  [[ "$output" == *"AUR RPC unreachable"* ]]
}

@test "trust: RPC unreachable interactive can continue without signals" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  AURVET_NO_RPC=1 aur_vet_hook_answer "$clone_directory" y
  [ "$status" -eq 0 ]
  [[ "$output" == *"without trust signals"* ]]
}

@test "indicators: a backdated commit can't dodge the window (LastModified)" {
  # 123pan-bin is on the Atomic Arch list; the commit claims 2026-09 but the
  # AUR (server-side) says it was modified inside the campaign window.
  local clone_directory; clone_directory="$(aur_vet_case pkgbase '123pan-bin@2026-09-01T12:00:00' bd)"
  aur_vet_rpc 123pan-bin LastModified="$(date -d 2026-06-11 +%s)"
  aur_vet_hook "$clone_directory" 123pan-bin
  [[ "$output" == *"CRITICAL indicator-pkgbase "* ]]
}

@test "indicators: any in-window commit in history stays critical" {
  local clone_directory; clone_directory="$(aur_vet_case pkgbase '123pan-bin@2026-06-11T12:00:00' hist)"
  GIT_COMMITTER_DATE=2026-09-01T12:00:00 aur_vet_commit "$clone_directory" PKGBUILD \
    's/^pkgrel=1$/pkgrel=2/'
  aur_vet_hook "$clone_directory" 123pan-bin
  [[ "$output" == *"CRITICAL indicator-pkgbase "* ]]
}

# ── probable adoption (ADR 0149): AUR server fields, never git authors ──────

@test "adoption: recent adoption alone is suspicious" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  aur_vet_rpc electron-benign Maintainer='"adopter"' Submitter='"original"' \
    LastModified="$(_days_ago 2)"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS trust-adopted"* ]]
  [[ "$output" != *"CRITICAL"* ]]
}

@test "adoption: recent adoption + a gained finding is critical" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  aur_vet_commit "$clone_directory" PKGBUILD 's/^build() {$/build() {\n  npx x/'
  aur_vet_rpc rust-benign Maintainer='"adopter"' Submitter='"original"' \
    LastModified="$(_days_ago 2)"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL trust-adopted"* ]]
}

@test "adoption: an adoption older than 14 days is no finding" {
  aur_vet_rpc electron-benign Maintainer='"adopter"' Submitter='"original"' \
    LastModified="$(_days_ago 30)"
  aur_vet_hook "$(aur_vet_clone electron-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" != *"trust-adopted"* ]]
}

@test "adoption: spoofed git authors never count as a maintainer change" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign trusted-old-maintainer)"
  git -C "$clone_directory" -c user.name=evil -c user.email=evil@aur commit -q \
    --allow-empty -m "looks routine"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
  [[ "$output" != *"trust-"*"evil"* ]]
}
