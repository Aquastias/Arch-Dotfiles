#!/usr/bin/env bats
# Gained Findings (ADR 0149): a finding the newest AUR commit has but the one
# before lacked is escalated one tier — the "clean package + one injected
# line" shape. Unchanged findings keep their tier; one commit = no compare.

load ../lib/aur-vet

setup() { aur_vet_setup; }
teardown() { aur_vet_teardown; }

# Add <line> after the first line matching <ERE> in <dir>/PKGBUILD, commit.
_inject() {
  local pkgbuild="$1/PKGBUILD"
  L="$3" awk -v re="$2" \
    '{ print } !d && $0 ~ re { print ENVIRON["L"]; d = 1 }' \
    "$pkgbuild" > "$pkgbuild.new" && command mv "$pkgbuild.new" "$pkgbuild"
  git -C "$1" -c user.name=m -c user.email=m@aur commit -q -am inject
}

@test "gained: a suspicious line added in HEAD escalates to critical" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  _inject "$clone_directory" '^build[(]' '  npx some-tool --init'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL npx-run"* ]]
  [[ "$output" == *"gained"* ]]
}

@test "gained: an info line added in HEAD escalates to suspicious" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  _inject "$clone_directory" '^build[(]' '  go get example.com/x'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS lang-fetch"* ]]
}

@test "gained: a finding present in both commits keeps its tier" {
  local clone_directory; clone_directory="$(aur_vet_clone chaos-rat)"
  aur_vet_commit "$clone_directory" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS install-interp"* ]]
  [[ "$output" != *"CRITICAL"* ]]
}

@test "gained: an existing info line that only moved keeps its tier" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  _inject "$clone_directory" '^pkgrel=' '# a comment shifting every line below'
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lang-fetch"* ]]
}

@test "gained: a single-commit package is scanned without comparison" {
  aur_vet_hook "$(aur_vet_clone chaos-rat)"
  [[ "$output" == *"SUSPICIOUS install-interp"* ]]
  [[ "$output" != *"gained"* ]]
}

@test "gained: the previous commit is never executed" {
  export AUR_VET_TEST_MARKER="$T/executed"
  local clone_directory; clone_directory="$(aur_vet_clone never-run)"
  aur_vet_commit "$clone_directory" PKGBUILD 's/^pkgrel=1/pkgrel=2/'
  aur_vet_hook "$clone_directory"
  [ ! -e "$AUR_VET_TEST_MARKER" ]
}

@test "gained: a version bump that rewrites a flagged line is not a gain" {
  # The flagged source URL carries the version; a bump changes its text but
  # not what fires. (basedpyright: source-owner, allowlisted, went critical.)
  local clone_directory; clone_directory="$(aur_vet_case source "https://github.com/other/rc/v1.tgz" g)"
  sed -i 's#other/rc/v1#other/rc/v2#' "$clone_directory/PKGBUILD" "$clone_directory/.SRCINFO"
  git -C "$clone_directory" -c user.name=m -c user.email=m@aur commit -q -am bump
  printf 'rulecase\tsource-owner\treviewed\n' >> "$AUR_VET_STORE/allow.tsv"
  aur_vet_hook "$clone_directory" rulecase
  [ "$status" -eq 0 ]
  [[ "$output" != *"gained"* ]]
}

@test "gained: a second copy of an existing finding is a gain" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  _inject "$clone_directory" '^build[(]' '  cargo fetch --locked'
  aur_vet_hook "$clone_directory"
  [[ "$output" == *"SUSPICIOUS lang-fetch"* ]]
}

@test "gained: an unreadable previous commit aborts, never skips the check" {
  local clone_directory; clone_directory="$(aur_vet_clone rust-benign)"
  aur_vet_commit "$clone_directory" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  local blob; blob="$(git -C "$clone_directory" rev-parse HEAD~1:PKGBUILD)"
  command rm -f "$clone_directory/.git/objects/${blob:0:2}/${blob:2}"
  aur_vet_hook "$clone_directory"
  [ "$status" -eq 2 ]
  [[ "$output" == *"previous commit"* ]]
}
