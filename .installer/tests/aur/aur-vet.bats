#!/usr/bin/env bats
# aur-vet hook mode (ADR 0143): black-box over a fixture AUR clone — exit code
# and findings on stderr are the whole contract.

load ../lib/aur-vet

setup() { aur_vet_setup; }
teardown() { aur_vet_teardown; }

@test "hook: Atomic Arch named npm install aborts with a critical finding" {
  aur_vet_hook "$(aur_vet_clone atomic-arch)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRITICAL named-pkg-install PKGBUILD:15"* ]]
}

@test "hook: download piped into a shell aborts" {
  aur_vet_hook "$(aur_vet_clone curl-sh)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRITICAL pipe-to-shell PKGBUILD:"* ]]
}

@test "hook: benign electron (npm ci / bare npm install) passes" {
  aur_vet_hook "$(aur_vet_clone electron-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* ]]
}

@test "hook: the PKGBUILD is never executed during vetting" {
  export AUR_VET_TEST_MARKER="$T/executed"
  aur_vet_hook "$(aur_vet_clone never-run)"
  [ ! -e "$AUR_VET_TEST_MARKER" ]
}

@test "hook: a directory that is not a git clone is an environment error" {
  mkdir -p "$T/plain"
  aur_vet_hook "$T/plain" plain
  [ "$status" -eq 2 ]
}

@test "hook: named bun install in a .install scriptlet aborts" {
  aur_vet_hook "$(aur_vet_clone atomic-arch-install)"
  [ "$status" -ne 0 ]
  local want="CRITICAL named-pkg-install atomic-arch-install.install:2"
  [[ "$output" == *"$want"* ]]
}

@test "hook: a rule added to the data file fires with no code change" {
  printf 'make-call\tcritical\tbuild\t^[[:space:]]*make$\tmake called\n' \
    >> "$AUR_VET_DATA/rules.tsv"
  aur_vet_hook "$(aur_vet_clone electron-benign)"
  [ "$status" -eq 0 ]
  aur_vet_hook "$(aur_vet_clone curl-sh)"
  [[ "$output" == *"CRITICAL make-call PKGBUILD:15 make called"* ]]
}

@test "hook: a rule may continue across lines with a trailing backslash" {
  printf 'split\tcritical\tbuild\t^[[:space:]]*ma\\\n\tke$\tsplit rule\n' \
    >> "$AUR_VET_DATA/rules.tsv"
  aur_vet_hook "$(aur_vet_clone curl-sh)"
  [[ "$output" == *"CRITICAL split PKGBUILD:15 split rule"* ]]
}

@test "hook: verdict line names package, commit and tally" {
  aur_vet_hook "$(aur_vet_clone curl-sh)"
  local verdict_regex="^aur-vet: curl-sh @[0-9a-f]{12}: ABORT \\(1 critical"
  [[ "${lines[-1]}" =~ $re ]]
}
