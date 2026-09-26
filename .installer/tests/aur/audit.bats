#!/usr/bin/env bats
# aur-vet audit (ADR 0143): on an installer-created VM, check installed
# foreign packages against the Indicators and look for campaign npm/bun
# artefacts and on-disk IOC paths. Runs over a fake root; pacman is faked.

load ../lib/aur-vet

setup() {
  aurvet_setup
  export AUR_VET_AUDIT_ROOT="$T/root"
  mkdir -p "$AUR_VET_AUDIT_ROOT/home/alice" "$AUR_VET_AUDIT_ROOT/root" "$T/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "${FOREIGN:-paru yay-bin}" \
    > "$T/bin/pacman"
  chmod +x "$T/bin/pacman"
  export PATH="$T/bin:$PATH"
}
teardown() { aurvet_teardown; }

_foreign() {
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$*" > "$T/bin/pacman"
}
_audit() { run "$AUR_VET_SRC/aur-vet" audit; }

@test "audit: a clean system passes" {
  _audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"audit: clean"* ]]
}

@test "audit: an installed foreign package on a campaign list fails" {
  _foreign paru firefox-patch-bin
  _audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"firefox-patch-bin"*"chaos-rat"* ]]
}

@test "audit: a campaign npm package in a user's bun cache fails" {
  mkdir -p "$AUR_VET_AUDIT_ROOT/home/alice/.bun/install/cache/js-digest@1.0.0"
  _audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"js-digest"* ]]
}

@test "audit: a campaign npm package in the npm cache index fails" {
  local idx="$AUR_VET_AUDIT_ROOT/root/.npm/_cacache/index-v5/ab/cd"
  mkdir -p "$idx"
  printf '{"key":"make-fetch-happen:request-cache:%s"}\n' \
    "https://registry.npmjs.org/atomic-lockfile/-/atomic-lockfile-1.4.2.tgz" \
    > "$idx/entry"
  _audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"atomic-lockfile"* ]]
}

@test "audit: a global node_modules install fails" {
  mkdir -p "$AUR_VET_AUDIT_ROOT/usr/lib/node_modules/lockfile-js"
  _audit
  [ "$status" -eq 1 ]
}

@test "audit: an IOC path under a home (~/.local/bin/sudo) fails" {
  mkdir -p "$AUR_VET_AUDIT_ROOT/home/alice/.local/bin"
  : > "$AUR_VET_AUDIT_ROOT/home/alice/.local/bin/sudo"
  _audit
  [ "$status" -eq 1 ]
  [[ "$output" == *"/home/alice/.local/bin/sudo"* ]]
}

@test "audit: an absolute IOC path fails" {
  mkdir -p "$AUR_VET_AUDIT_ROOT/usr/local/share"
  : > "$AUR_VET_AUDIT_ROOT/usr/local/share/systemd-initd"
  _audit
  [ "$status" -eq 1 ]
}
