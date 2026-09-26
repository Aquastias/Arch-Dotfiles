#!/usr/bin/env bats
# aur-vet seed (ADR 0143): collect every declared AUR package (host
# packages.aur, DE adapter aur lists, User Program AUR installs, AUR fonts),
# resolve AUR dependencies recursively via the RPC, and bulk-review them into
# pins. Local git remotes + RPC fixtures: never the network.

load ../lib/aur-vet

setup() {
  aurvet_setup
  # A fake installer tree; jsonc.sh is the real one, never a stale copy.
  export AUR_VET_GIT_BASE="$T/remote" AUR_VET_REPO="$T/repo"
  cp -r "$AUR_VET_FIXTURES/seed-repo" "$AUR_VET_REPO"
  cp "$AUR_VET_SRC/../lib/jsonc.sh" "$AUR_VET_SRC/../lib/aur-helper.sh" \
    "$AUR_VET_REPO/lib/"
  local b
  for b in electron-benign rust-benign chaos-rat curl-sh rulecase benign-dep; do
    aurvet_remote "$b"
  done
  aurvet_rpc electron-benign Depends='["npm", "benign-dep>=1.0"]'
  aurvet_rpc benign-dep
  aurvet_rpc rust-benign MakeDepends='["cargo"]'
  aurvet_rpc chaos-rat
  aurvet_rpc curl-sh
  aurvet_rpc rulecase
  local h; for h in paru paru-bin yay-bin; do aurvet_rpc "$h"; done
}
teardown() { aurvet_teardown; }

_seed() { run bash -c 'printf "$1" | AUR_VET_INTERACTIVE=1 "$2" seed "${@:3}"' \
  _ "$1" "$AUR_VET_SRC/aur-vet" "${@:2}"; }
_pinned() { awk -F'\t' -v b="$1" '$1 == b { f = 1 } END { exit !f }' \
  "$AUR_VET_STORE/vetted.tsv"; }

@test "seed --list: collects every declaration source, repo packages out" {
  run "$AUR_VET_SRC/aur-vet" seed --list
  [ "$status" -eq 0 ]
  local want
  for want in electron-benign rust-benign chaos-rat curl-sh rulecase \
              benign-dep; do
    grep -qx "$want" <<<"$output" || { echo "missing $want"; return 1; }
  done
  ! grep -qx -e ripgrep -e kitty -e npm -e cargo -e noto-fonts -e off-pkg \
    <<<"$output"
}

@test "seed --list: AUR dependencies resolve recursively and dedupe" {
  run "$AUR_VET_SRC/aur-vet" seed --list electron-benign electron-benign
  [ "$status" -eq 0 ]
  [ "$(grep -cx benign-dep <<<"$output")" -eq 1 ]
  [ "$(grep -cx electron-benign <<<"$output")" -eq 1 ]
}

@test "seed: bulk review pins every accepted base" {
  _seed 'y\ny\n' electron-benign
  [ "$status" -eq 0 ]
  _pinned electron-benign
  _pinned benign-dep
}

@test "seed: rejected packages are listed at the end, not pinned" {
  _seed 'n\ny\n' electron-benign
  [ "$status" -ne 0 ]
  [[ "${lines[-1]}" == *"rejected: "*"benign-dep"* \
     || "${lines[-1]}" == *"rejected: "*"electron-benign"* ]]
  local n=0
  _pinned electron-benign && n=$((n + 1))
  _pinned benign-dep && n=$((n + 1))
  [ "$n" -eq 1 ]
}

@test "seed: resumable — already-pinned bases are skipped" {
  _seed 'y\ny\n' electron-benign
  _seed '' electron-benign
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped 2 (already pinned)"* ]]
}

@test "seed --list: the AUR Helper bootstrap ladder is always reviewed" {
  run "$AUR_VET_SRC/aur-vet" seed --list
  [ "$status" -eq 0 ]
  local h
  for h in paru paru-bin yay-bin; do
    grep -qx "$h" <<<"$output" || { echo "missing $h"; return 1; }
  done
}
