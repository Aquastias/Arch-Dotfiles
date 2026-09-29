#!/usr/bin/env bats
# Untrusted inputs never steer the vetter (ADR 0149 review): the AUR RPC
# answer, the clone's .SRCINFO and its file names are data, never code.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

@test "hardening: a non-numeric RPC time is an error, never arithmetic" {
  local marker="$T/pwned"
  aurvet_rpc electron-benign FirstSubmitted="\"a[\$(touch $marker)]\""
  aurvet_hook "$(aurvet_clone electron-benign)"
  [ "$status" -eq 2 ]
  [ ! -e "$marker" ]
  [[ "$output" == *"malformed"* ]]
}

@test "hardening: a hostile .SRCINFO pkgname never reaches the RPC URL" {
  local d; d="$(aurvet_clone electron-benign)"
  sed -i 's/^pkgname = .*/pkgname = x{a,b}\&arg[]=evil#/' "$d/.SRCINFO"
  git -C "$d" -c user.name=m -c user.email=m@aur commit -q -am name
  mkdir -p "$T/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s/curl.args"\nexit 7\n' "$T" \
    > "$T/bin/curl"
  chmod +x "$T/bin/curl"
  unset AUR_VET_RPC_FIXTURE_DIR
  export PATH="$T/bin:$PATH"
  AURVET_NO_RPC=1 aurvet_hook "$d"
  [ -s "$T/curl.args" ]
  [ "$status" -ne 0 ]
  [ -z "$(grep evil "$T/curl.args")" ]   # the hostile name never went out
  grep -qE -- '^-[a-zA-Z]*g' "$T/curl.args"   # and no curl URL globbing
}

@test "hardening: a backslash in a file name reaches the engine intact" {
  local d; d="$(aurvet_case srcinfo 'source = fix\t.patch' h1)"
  printf '%s\n' '--- a' > "$d/fix\\t.patch"
  git -C "$d" add -A
  git -C "$d" -c user.name=m -c user.email=m@aur commit -q -m src
  aurvet_hook "$d" rulecase
  [[ "$output" != *"missing-ref"* ]]
}
