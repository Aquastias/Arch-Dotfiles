#!/usr/bin/env bats
# Gained Findings (ADR 0149): a finding the newest AUR commit has but the one
# before lacked is escalated one tier — the "clean package + one injected
# line" shape. Unchanged findings keep their tier; one commit = no compare.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

# Add <line> after the first line matching <ERE> in <dir>/PKGBUILD, commit.
_inject() {
  local pb="$1/PKGBUILD"
  L="$3" awk -v re="$2" \
    '{ print } !d && $0 ~ re { print ENVIRON["L"]; d = 1 }' \
    "$pb" > "$pb.new" && command mv "$pb.new" "$pb"
  git -C "$1" -c user.name=m -c user.email=m@aur commit -q -am inject
}

@test "gained: a suspicious line added in HEAD escalates to critical" {
  local d; d="$(aurvet_clone rust-benign)"
  _inject "$d" '^build[(]' '  npx some-tool --init'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL npx-run"* ]]
  [[ "$output" == *"gained"* ]]
}

@test "gained: an info line added in HEAD escalates to suspicious" {
  local d; d="$(aurvet_clone rust-benign)"
  _inject "$d" '^build[(]' '  go get example.com/x'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS lang-fetch"* ]]
}

@test "gained: a finding present in both commits keeps its tier" {
  local d; d="$(aurvet_clone chaos-rat)"
  aurvet_commit "$d" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SUSPICIOUS install-interp"* ]]
  [[ "$output" != *"CRITICAL"* ]]
}

@test "gained: an existing info line that only moved keeps its tier" {
  local d; d="$(aurvet_clone rust-benign)"
  _inject "$d" '^pkgrel=' '# a comment shifting every line below'
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lang-fetch"* ]]
}

@test "gained: a single-commit package is scanned without comparison" {
  aurvet_hook "$(aurvet_clone chaos-rat)"
  [[ "$output" == *"SUSPICIOUS install-interp"* ]]
  [[ "$output" != *"gained"* ]]
}

@test "gained: the previous commit is never executed" {
  export AUR_VET_TEST_MARKER="$T/executed"
  local d; d="$(aurvet_clone never-run)"
  aurvet_commit "$d" PKGBUILD 's/^pkgrel=1/pkgrel=2/'
  aurvet_hook "$d"
  [ ! -e "$AUR_VET_TEST_MARKER" ]
}

@test "gained: a version bump that rewrites a flagged line is not a gain" {
  # The flagged source URL carries the version; a bump changes its text but
  # not what fires. (basedpyright: source-owner, allowlisted, went critical.)
  local d; d="$(aurvet_case source "https://github.com/other/rc/v1.tgz" g)"
  sed -i 's#other/rc/v1#other/rc/v2#' "$d/PKGBUILD" "$d/.SRCINFO"
  git -C "$d" -c user.name=m -c user.email=m@aur commit -q -am bump
  printf 'rulecase\tsource-owner\treviewed\n' >> "$AUR_VET_STORE/allow.tsv"
  aurvet_hook "$d" rulecase
  [ "$status" -eq 0 ]
  [[ "$output" != *"gained"* ]]
}

@test "gained: a second copy of an existing finding is a gain" {
  local d; d="$(aurvet_clone rust-benign)"
  _inject "$d" '^build[(]' '  cargo fetch --locked'
  aurvet_hook "$d"
  [[ "$output" == *"SUSPICIOUS lang-fetch"* ]]
}

@test "gained: an unreadable previous commit aborts, never skips the check" {
  local d; d="$(aurvet_clone rust-benign)"
  aurvet_commit "$d" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  local blob; blob="$(git -C "$d" rev-parse HEAD~1:PKGBUILD)"
  command rm -f "$d/.git/objects/${blob:0:2}/${blob:2}"
  aurvet_hook "$d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"previous commit"* ]]
}
