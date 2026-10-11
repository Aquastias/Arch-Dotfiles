#!/usr/bin/env bats
# rules.tsv v1 catalogue (ADR 0143): every rule fires on its positive cases
# and stays silent on its negative ones (fixtures/aur/rule-cases.tsv), and
# the incident fixtures abort while the benign ones pass.

load ../lib/aur-vet

setup() { aur_vet_setup; }
teardown() { aur_vet_teardown; }

_cases() { grep -v '^#' "$AUR_VET_FIXTURES/rule-cases.tsv"; }

@test "rules: every case matches its expected polarity" {
  local id pol place text case_directory base fails="" i=0
  while IFS=$'\t' read -r id pol place text; do
    i=$((i + 1))
    base=rulecase; [[ "$place" == pkgbase ]] && base="${text%@*}"
    case_directory="$(aur_vet_case "$place" "$text" "c$i")"
    aur_vet_hook "$case_directory" "$base"
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
  local clone_directory; clone_directory="$(aur_vet_case build true base)"
  aur_vet_hook "$clone_directory" rulecase
  [ "$status" -eq 0 ]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* \
     && "$output" != *INFO* ]]
}

@test "rules: Chaos RAT fixture (attacker patch repo + scriptlet) aborts" {
  aur_vet_hook "$(aur_vet_clone chaos-rat)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SUSPICIOUS source-owner .SRCINFO:10"* ]]
  [[ "$output" == *"SUSPICIOUS install-interp chaos-rat.install:2"* ]]
}

@test "rules: chrome-reupload fixture (interpreter fetch in launcher) aborts" {
  aur_vet_hook "$(aur_vet_clone chrome-reupload)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"CRITICAL script-fetch chrome-reupload.sh:3"* ]]
}

@test "rules: benign rust fixture passes with info only" {
  aur_vet_hook "$(aur_vet_clone rust-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lang-fetch PKGBUILD:16"* ]]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* ]]
}

@test "rules: benign electron fixture passes with info only" {
  aur_vet_hook "$(aur_vet_clone electron-benign)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INFO lockfile-install PKGBUILD:15"* ]]
  [[ "$output" != *CRITICAL* && "$output" != *SUSPICIOUS* ]]
}

# weak-checksums reads whole arrays and counts only real digests.
@test "rules: a multi-line MD5 array is weak-checksums" {
  local clone_directory; clone_directory="$(aur_vet_case sums md5 w1)"
  sed -i "s/^md5sums=('\\(2*\\)')$/md5sums=(\\n  '\\1'\\n)/" "$clone_directory/PKGBUILD"
  grep -q "^md5sums=($" "$clone_directory/PKGBUILD"
  git -C "$clone_directory" -c user.name=m -c user.email=m@aur commit -q -am ml
  aur_vet_hook "$clone_directory" rulecase
  [[ "$output" == *" weak-checksums "* ]]
}

@test "rules: a real MD5 beside a SKIP-only sha256 is weak-checksums" {
  local clone_directory; clone_directory="$(aur_vet_case sums md5 w2)"
  printf "sha256sums=('SKIP')\n" >> "$clone_directory/PKGBUILD"
  git -C "$clone_directory" -c user.name=m -c user.email=m@aur commit -q -am skip
  aur_vet_hook "$clone_directory" rulecase
  [[ "$output" == *" weak-checksums "* ]]
}
