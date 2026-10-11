#!/usr/bin/env bats
# On-the-fly AUR Vetting (ADR 0149): each build is decided from the clone as
# it is — no pins. Clean passes, critical aborts, suspicious asks n/y/a (a =
# allowlist that package + rule for good) and aborts unattended.

load ../lib/aur-vet

setup() { aur_vet_setup; }
teardown() { aur_vet_teardown; }

_allow_rows() { grep -vE '^[[:space:]]*(#|$)' "$AUR_VET_STORE/allow.tsv" \
  2>/dev/null || true; }

@test "verdict: a clean package passes unattended with no pin store" {
  command rm -f "$AUR_VET_STORE/vetted.tsv"
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [ ! -e "$AUR_VET_STORE/vetted.tsv" ]
}

@test "verdict: a clean package that changed passes with no review" {
  local clone_directory; clone_directory="$(aur_vet_clone electron-benign)"
  aur_vet_commit "$clone_directory" PKGBUILD 's/^pkgdesc=.*/pkgdesc="Changed description"/'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
}

@test "verdict: a critical finding aborts" {
  aur_vet_hook "$(aur_vet_clone atomic-arch)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"critical findings always abort"* ]]
}

@test "verdict: a suspicious finding aborts unattended and names the rule" {
  aur_vet_hook "$(aur_vet_clone chaos-rat)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"install-interp"* ]]
  [ -z "$(_allow_rows)" ]
}

@test "verdict: suspicious + answer n aborts and stores nothing" {
  aur_vet_hook_answer "$(aur_vet_clone chaos-rat)" n
  [ "$status" -eq 1 ]
  [ -z "$(_allow_rows)" ]
}

@test "verdict: suspicious + answer y builds once and stores nothing" {
  local clone_directory; clone_directory="$(aur_vet_clone chaos-rat)"
  aur_vet_hook_answer "$clone_directory" y
  [ "$status" -eq 0 ]
  [ -z "$(_allow_rows)" ]
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
}

@test "verdict: suspicious + answer a allowlists package + rule, no commit" {
  local clone_directory; clone_directory="$(aur_vet_clone chaos-rat)"
  aur_vet_hook_answer "$clone_directory" a
  [ "$status" -eq 0 ]
  run _allow_rows
  [[ "$output" == *$'chaos-rat\tinstall-interp\t'* ]]
  [[ "$output" == *$'chaos-rat\tsource-owner\t'* ]]
  [[ "$output" != *"$(git -C "$clone_directory" rev-parse HEAD)"* ]]
}

@test "verdict: an allowlisted rule still applies after the package changes" {
  local clone_directory; clone_directory="$(aur_vet_clone chaos-rat)"
  printf 'chaos-rat\t%s\treviewed\n' source-owner install-interp \
    >> "$AUR_VET_STORE/allow.tsv"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
  aur_vet_commit "$clone_directory" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
}

@test "verdict: an allowlist row for another package does not apply" {
  printf 'other\t%s\treviewed\n' source-owner install-interp \
    >> "$AUR_VET_STORE/allow.tsv"
  aur_vet_hook "$(aur_vet_clone chaos-rat)"
  [ "$status" -eq 1 ]
}

@test "verdict: there is no bypass flag or environment toggle" {
  local clone_directory; clone_directory="$(aur_vet_clone chaos-rat)"
  run bash -c 'cd "$1" && "$2" --no-vet' _ "$clone_directory" "$AUR_VET_SRC/aur-vet"
  [ "$status" -eq 2 ]
  AUR_VET=off AUR_VET_OFF=1 AUR_VET_SKIP=1 aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
}

@test "verdict: the repo allowlist has no commit column" {
  run awk -F'\t' '!/^#/ && NF && $2 ~ /^[0-9a-f]{40}$/' \
    "$AUR_VET_SRC/allow.tsv"
  [ -z "$output" ]
}
