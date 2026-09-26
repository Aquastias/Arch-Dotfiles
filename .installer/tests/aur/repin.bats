#!/usr/bin/env bats
# aur-vet repin (ADR 0143): the only way to accept a maintainer change — a
# deliberate, interactive, typed confirmation outside the hook. And
# aur-vet doctor: warns when a paru.conf would drop the vetting hook.

load ../lib/aur-vet

setup() {
  aurvet_setup
  export AUR_VET_GIT_BASE="$T/remote"
  aurvet_remote electron-benign
  R="$AUR_VET_GIT_BASE/electron-benign.git"
  aurvet_pin "$R" electron-benign
  OLD="$(git -C "$R" rev-parse HEAD)"
  # The new maintainer's first commit.
  aurvet_commit "$R" PKGBUILD 's/^  npm run build$/  npm run build\n  make/'
  NEW="$(git -C "$R" rev-parse HEAD)"
  aurvet_rpc electron-benign Maintainer='"new-owner"'
}
teardown() { aurvet_teardown; }

_repin() { # <answer> [pkgbase]
  run bash -c 'printf "%s\n" "$1" | AUR_VET_INTERACTIVE=1 "$2" repin "$3"' \
    _ "$1" "$AUR_VET_SRC/aur-vet" "${2:-electron-benign}"
}
_pin() { awk -F'\t' -v b="$1" '$1 == b { print $2 "\t" $3 }' \
  "$AUR_VET_STORE/vetted.tsv"; }

@test "hook: a maintainer change stays critical and names the repin command" {
  aurvet_hook "$R" electron-benign
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL trust-maintainer-changed"* ]]
  [[ "$output" == *"sudo aur-vet repin electron-benign"* ]]
}

@test "repin: shows the transition and the diff, accepts the typed name" {
  _repin new-owner
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixture-maintainer -> new-owner"* ]]
  [[ "$output" == *"+  make"* ]]
  [ "$(_pin electron-benign)" = "$NEW"$'\tnew-owner' ]
  aurvet_hook "$R" electron-benign
  [ "$status" -eq 0 ]
}

@test "repin: the typed name is compared case-insensitively" {
  _repin NEW-Owner
  [ "$status" -eq 0 ]
}

@test "repin: a wrong name aborts and keeps the old pin" {
  _repin y
  [ "$status" -eq 1 ]
  [ "$(_pin electron-benign)" = "$OLD"$'\tfixture-maintainer' ]
}

@test "repin: a name outside the AUR charset asks for the commit prefix" {
  aurvet_rpc electron-benign Maintainer='"名前"'
  _repin "${NEW:0:8}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first 8 characters of ${NEW:0:12}"* ]]
}

@test "repin: refuses when unattended" {
  run env AUR_VET_UNATTENDED=1 "$AUR_VET_SRC/aur-vet" repin electron-benign
  [ "$status" -eq 2 ]
}

@test "repin: refuses a package with no Vetted Commit" {
  : > "$AUR_VET_STORE/vetted.tsv"
  _repin new-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"no Vetted Commit"* ]]
}

@test "repin: any other critical finding still refuses" {
  aurvet_commit "$R" PKGBUILD 's/^  make$/  npm install atomic-lockfile/'
  _repin new-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL named-pkg-install"* ]]
}

@test "repin: an unreachable RPC refuses (no maintainer to record)" {
  command rm -f "$AUR_VET_RPC_FIXTURE_DIR/electron-benign.json"
  _repin new-owner
  [ "$status" -eq 1 ]
  [[ "$output" == *"AUR RPC unreachable"* ]]
}

# ── doctor ──────────────────────────────────────────────────────────────────

_doctor() {
  run env HOME="$T/home" AUR_VET_ETC_PARU_CONF="$T/etc-paru.conf" \
    "$AUR_VET_SRC/aur-vet" doctor
}

@test "doctor: silent when only a hooked /etc/paru.conf exists" {
  mkdir -p "$T/home"
  printf '[options]\nPreBuildCommand = /usr/local/bin/aur-vet\n' \
    > "$T/etc-paru.conf"
  _doctor
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doctor: warns about a user paru.conf without the hook" {
  mkdir -p "$T/home/.config/paru"
  printf '[options]\nBottomUp\n' > "$T/home/.config/paru/paru.conf"
  printf '[options]\nPreBuildCommand = /usr/local/bin/aur-vet\n' \
    > "$T/etc-paru.conf"
  _doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *".config/paru/paru.conf"*"without the AUR Vetting hook"* ]]
}

@test "doctor: warns about \$PARU_CONF and an unhooked /etc/paru.conf" {
  mkdir -p "$T/home"
  printf '[options]\n' > "$T/custom.conf"
  printf '[options]\n' > "$T/etc-paru.conf"
  run env HOME="$T/home" AUR_VET_ETC_PARU_CONF="$T/etc-paru.conf" \
    PARU_CONF="$T/custom.conf" "$AUR_VET_SRC/aur-vet" doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"custom.conf"* && "$output" == *"etc-paru.conf"* ]]
}
