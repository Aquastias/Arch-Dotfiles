#!/usr/bin/env bats
# rules.tsv v1 catalogue (ADR 0143): every rule fires on its positive cases
# and stays silent on its negative ones (fixtures/aur/rule-cases.tsv), and
# the incident fixtures abort while the benign ones pass.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

_cases() { grep -v '^#' "$AUR_VET_FIXTURES/rule-cases.tsv"; }

@test "rules: every case matches its expected polarity" {
  local id pol place text dir base fails="" i=0
  while IFS=$'\t' read -r id pol place text; do
    i=$((i + 1))
    base=rulecase; [[ "$place" == pkgbase ]] && base="${text%@*}"
    dir="$(aurvet_case "$place" "$text" "c$i")"
    aurvet_hook "$dir" "$base"
    if [[ "$pol" == + && "$output" != *" $id "* ]] \
       || [[ "$pol" == - && "$output" == *" $id "* ]]; then
      fails+=$'\n'"  ${id} ${pol} ${place}: ${text}"$'\n'"${output}"
    fi
  done < <(_cases)
  [[ -z "$fails" ]] || { echo "failing cases:${fails}"; return 1; }
}

# trust-scope rules need the RPC: trust.bats covers them.
@test "rules: every catalogue rule has a positive and a negative case" {
  local id missing=""
  while read -r id; do
    _cases | grep -q "^${id}"$'\t+\t' || missing+=" ${id}(+)"
    _cases | grep -q "^${id}"$'\t-\t' || missing+=" ${id}(-)"
  done < <(awk -F'\t' '/^[a-z]/ && NF > 1 && $3 != "trust" {
             print $1 }' \
             "$AUR_VET_DATA/rules.tsv")
  [[ -z "$missing" ]] || { echo "missing:${missing}"; return 1; }
}

@test "rules: the clean rulecase base passes with no findings" {
  local d; d="$(aurvet_case build true base)"; aurvet_pin "$d" rulecase
  aurvet_hook "$d" rulecase
  [ "$status" -eq 0 ]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* \
     && "$output" != *INFO* ]]
}

@test "rules: Chaos RAT fixture (attacker patch repo + scriptlet) aborts" {
  aurvet_hook "$(aurvet_clone chaos-rat)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SUSPICIOUS source-owner .SRCINFO:10"* ]]
  [[ "$output" == *"SUSPICIOUS install-interp chaos-rat.install:2"* ]]
}

@test "rules: chrome-reupload fixture (interpreter fetch in launcher) aborts" {
  aurvet_hook "$(aurvet_clone chrome-reupload)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRITICAL script-fetch chrome-reupload.sh:3"* ]]
}

@test "rules: benign rust fixture passes with info only" {
  aurvet_hook "$(aurvet_clone_pinned rust-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lang-fetch PKGBUILD:16"* ]]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* ]]
}

@test "rules: benign electron fixture passes with info only" {
  aurvet_hook "$(aurvet_clone_pinned electron-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lockfile-install PKGBUILD:15"* ]]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* ]]
}
