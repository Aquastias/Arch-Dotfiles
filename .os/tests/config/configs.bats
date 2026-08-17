#!/usr/bin/env bats
# Tests for .os/lib/config/layers.sh — real Host Profile invariants +
# program resolution/validation. The loader/merge contract moved to the
# Profile Loader (tests/config/profile-loader.bats) with the legacy readers.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"
  # shellcheck source=../../lib/config/layers.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/layers.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── real Host Core carries the shared package base (ADR 0056) ───────────────
# Amends ADR 0007, whose "the lists are machine-specific" premise no longer
# holds. The end-to-end resolution of the committed profiles lives in
# tests/config/layered-profiles.bats; these are the file-shape invariants.

@test "real host core declares a packages object (ADR 0056)" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  jsonc_strip "$core" | jq -e '.packages.repo | type == "object"'
  jsonc_strip "$core" | jq -e '.packages.aur  | type == "object"'
}

# cups left Host Core (ADR 0079): it is now a toggle-derived System Program
# driven by options.printing.enabled and injected at Effective-Config assembly,
# so core declares no system programs — the Printing service category owns cups.
@test "real host core declares no system_programs (cups is toggle-derived)" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  jsonc_strip "$core" | jq -e '.system_programs == []'
}

# The confirmation that two layers fit this fleet: laptop is a strict subset
# of desktop, so everything it wants is core and it declares nothing.
@test "hosts/laptop carries no packages block at all" {
  local lap="$BATS_TEST_DIRNAME/../../hosts/laptop/profile.jsonc"
  jsonc_strip "$lap" | jq -e '.packages == null'
}

@test "desktop declares only a delta, not the full list" {
  local desk="$BATS_TEST_DIRNAME/../../hosts/desktop/profile.jsonc"
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  local n_desk n_core
  n_desk="$(jsonc_strip "$desk" \
    | jq '[.packages.repo, .packages.aur | to_entries[].value[]] | length')"
  n_core="$(jsonc_strip "$core" \
    | jq '[.packages.repo, .packages.aur | to_entries[].value[]] | length')"
  [ "$n_desk" -lt "$n_core" ]
}

# The three VM fixtures opt out of core's packages wholesale rather than
# maintaining an exclude list that would grow every time core does.
@test "the three VM fixtures declare packages.inherit false" {
  local h
  for h in arch-data arch-kde arch-secure; do
    jsonc_strip "$BATS_TEST_DIRNAME/../../hosts/vm/$h/profile.jsonc" \
      | jq -e '.packages.inherit == false'
  done
}

@test "users/core declares its programs; the test users exclude them" {
  local ucore="$BATS_TEST_DIRNAME/../../users/core/profile.jsonc"
  jsonc_strip "$ucore" | jq -e '.programs == ["docker","virt-manager"]'
  jsonc_strip "$ucore" | jq -e '.shell == "/bin/zsh"'
  local u
  for u in vm-test vm-data; do
    jsonc_strip "$BATS_TEST_DIRNAME/../../users/$u/profile.jsonc" \
      | jq -e '.programs_exclude == ["docker","virt-manager"]'
  done
}

@test "real desktop packages.repo/aur parse as Categorized Lists" {
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local f slot
  for f in "$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc" \
           "$BATS_TEST_DIRNAME/../../hosts/desktop/profile.jsonc"; do
    for slot in repo aur; do
      local j; j="$(jsonc_strip "$f" | jq -c ".packages.$slot")"
      run categorized_list_parse "$j" string "packages.$slot"
      [ "$status" -eq 0 ]
    done
  done
}

@test "desktop keeps system_programs [grub] with no grub/os-prober package" {
  local desk="$BATS_TEST_DIRNAME/../../hosts/desktop/profile.jsonc"
  jsonc_strip "$desk" | jq -e '.system_programs == ["grub"]'
  local pkgs
  pkgs="$(jsonc_strip "$desk" | jq -r '.packages.repo | to_entries[].value[]')"
  ! grep -qx "grub"      <<< "$pkgs"
  ! grep -qx "os-prober" <<< "$pkgs"
}

# ── program resolution ───────────────────────────────────────────────────────

write_program() {
  local cat="$1" name="$2" system="$3"
  mkdir -p "$TEST_DIR/programs/$cat/$name"
  printf '{"name":"%s","system":%s}\n' "$name" "$system" \
    > "$TEST_DIR/programs/$cat/$name/config.jsonc"
  printf '#!/bin/sh\n' > "$TEST_DIR/programs/$cat/$name/install.sh"
}

@test "resolve_program: returns category/name when found" {
  write_program "security" "ufw" "false"

  run resolve_program ufw
  [ "$status" -eq 0 ]
  [ "$output" = "security/ufw" ]
}

@test "resolve_program: returns 1 when not found" {
  run resolve_program nope
  [ "$status" -eq 1 ]
}

# ── program kind is authoritative (R22) ──────────────────────────────────────
# The registry carries the system flag so a menu render never re-parses every
# program's config.jsonc, and one lookup answers "what kind is this name?".

@test "registry: carries each program's system flag alongside its category" {
  write_program "bootloader" "grub" "true"
  write_program "virtualization" "docker" "false"

  configs_build_registry
  [ "${_CONFIGS_REGISTRY[grub]}" = "bootloader/grub" ]
  [ "${_CONFIGS_KIND[grub]}" = "system" ]
  [ "${_CONFIGS_REGISTRY[docker]}" = "virtualization/docker" ]
  [ "${_CONFIGS_KIND[docker]}" = "user" ]
}

@test "program_kind: system for the real system programs" {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  configs_build_registry
  for p in grub cups sops; do
    [ "$(program_kind "$p")" = "system" ]
  done
}

@test "program_kind: user for the real user programs" {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  configs_build_registry
  for p in docker podman borg firewalld; do
    [ "$(program_kind "$p")" = "user" ]
  done
}

@test "program_kind: none for a name with no program directory" {
  configs_build_registry
  [ "$(program_kind nope)" = "none" ]
}

@test "program_kind: resolves without a prebuilt registry" {
  write_program "bootloader" "grub" "true"
  write_program "virtualization" "docker" "false"
  [ "$(program_kind grub)" = "system" ]
  [ "$(program_kind docker)" = "user" ]
  [ "$(program_kind nope)" = "none" ]
}

@test "registry: built once, not rebuilt per lookup" {
  write_program "bootloader" "grub" "true"
  configs_build_registry
  # A program appearing after the build is not picked up by a lookup, proving
  # the lookup reads the index rather than re-scanning the tree.
  write_program "virtualization" "docker" "false"
  [ "$(program_kind docker)" = "none" ]
}

@test "program_names_of_kind: partitions the real program set by flag" {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  configs_build_registry
  run program_names_of_kind system
  # cups (printing), bluetooth, power-profiles-daemon + tuned (power) are the
  # toggle-derived System Programs added by ADR 0079/0080; grub + sops authored.
  [ "$output" = "$(printf \
    'bluetooth\ncups\ngrub\npower-profiles-daemon\nsops\ntuned')" ]

  run program_names_of_kind user
  echo "$output" | grep -qx docker
  echo "$output" | grep -qx firewalld
  ! echo "$output" | grep -qx cups
  ! echo "$output" | grep -qx grub
  ! echo "$output" | grep -qx sops
}

# ── exclusivity: a name is either a Program or a package, never both ─────────
# Replaces the promotion rule, which ran only in the guided emit path and so
# made the same file install differently per front-end.

@test "exclusivity: a repo entry naming a system Program aborts" {
  write_program "bootloader" "grub" "true"
  configs_build_registry
  run validate_package_program_exclusivity \
    '{"packages":{"repo":{"boot":["grub"]}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"grub"* ]]
}

@test "exclusivity: a repo entry naming a user Program aborts" {
  write_program "virtualization" "docker" "false"
  configs_build_registry
  run validate_package_program_exclusivity \
    '{"packages":{"repo":{"dev":["docker"]}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"docker"* ]]
}

@test "exclusivity: an aur entry naming a Program aborts too" {
  write_program "communication" "teamspeak3" "false"
  configs_build_registry
  run validate_package_program_exclusivity \
    '{"packages":{"aur":{"misc":["teamspeak3"]}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"teamspeak3"* ]]
}

@test "exclusivity: the message names the path and the correct slot" {
  write_program "bootloader" "grub" "true"
  write_program "virtualization" "docker" "false"
  configs_build_registry

  run validate_package_program_exclusivity \
    '{"packages":{"repo":{"boot":["grub"]}}}' "hosts/desktop/profile.jsonc"
  [[ "$output" == *"hosts/desktop/profile.jsonc"* ]]
  [[ "$output" == *"packages.repo.boot"* ]]
  [[ "$output" == *"system_programs"* ]]

  run validate_package_program_exclusivity \
    '{"packages":{"repo":{"dev":["docker"]}}}' "hosts/desktop/profile.jsonc"
  [[ "$output" == *"packages.repo.dev"* ]]
  [[ "$output" == *"user profile"* ]]
}

@test "exclusivity: a plain package matching no program passes" {
  write_program "bootloader" "grub" "true"
  configs_build_registry
  local c='{"packages":{"repo":{"shell":["htop","fzf"]},
             "aur":{"misc":["brave-bin"]}}}'
  run validate_package_program_exclusivity "$c"
  [ "$status" -eq 0 ]
}

@test "exclusivity: an empty or absent package list passes" {
  configs_build_registry
  run validate_package_program_exclusivity '{}'
  [ "$status" -eq 0 ]
  run validate_package_program_exclusivity '{"packages":{}}'
  [ "$status" -eq 0 ]
  run validate_package_program_exclusivity '{"packages":{"repo":{"a":[]}}}'
  [ "$status" -eq 0 ]
}

@test "exclusivity: every violation is reported, not just the first" {
  write_program "bootloader" "grub" "true"
  write_program "virtualization" "docker" "false"
  configs_build_registry
  run validate_package_program_exclusivity \
    '{"packages":{"repo":{"boot":["grub"],"dev":["docker"]}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"grub"* ]]
  [[ "$output" == *"docker"* ]]
}

# The committed profiles must satisfy it — this is what caught docker,
# virt-manager and teamspeak3 being declared as raw packages AND as Programs.
@test "exclusivity: the real desktop and laptop profiles are clean" {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  configs_build_registry
  local h
  for h in desktop laptop core; do
    run validate_package_program_exclusivity \
      "$(jsonc_strip "$OS_DIR/hosts/$h/profile.jsonc")" "hosts/$h"
    [ "$status" -eq 0 ]
  done
}

# ── program validation ───────────────────────────────────────────────────────

@test "validate_program: accepts system program from host config" {
  write_program "bootloader" "grub" "true"

  run validate_program true grub
  [ "$status" -eq 0 ]
}

@test "validate_program: accepts user program from user config" {
  write_program "security" "firewalld" "false"

  run validate_program false firewalld
  [ "$status" -eq 0 ]
}

@test "validate_program: rejects user program from host config" {
  write_program "security" "firewalld" "false"

  run validate_program true firewalld
  [ "$status" -eq 1 ]
  [[ "$output" =~ "system=false" ]]
}

@test "validate_program: rejects system program from user config" {
  write_program "bootloader" "grub" "true"

  run validate_program false grub
  [ "$status" -eq 1 ]
  [[ "$output" =~ "system=true" ]]
}

@test "validate_program: missing program reports not-found" {
  run validate_program false nope
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]]
}

@test "validate_program: program missing install.sh is rejected" {
  mkdir -p "$TEST_DIR/programs/security/half"
  printf '{"name":"half","system":false}\n' \
    > "$TEST_DIR/programs/security/half/config.jsonc"

  run validate_program false half
  [ "$status" -eq 1 ]
  [[ "$output" =~ "missing install.sh" ]]
}

@test "validate_programs: all-pass returns 0" {
  write_program "security" "ufw" "false"
  write_program "security" "clamav" "false"

  run validate_programs false ufw clamav
  [ "$status" -eq 0 ]
}

@test "validate_programs: any-fail returns 1 but reports each failure" {
  write_program "security" "ufw" "false"

  run validate_programs false ufw nope
  [ "$status" -eq 1 ]
  [[ "$output" =~ "not found" ]]
}

# ── reconcile_user_program (issue 06) ────────────────────────────────────────
# Softens the old always-abort rule for a user's program reference:
#   system:false              → "user" (install at user level / shadow)
#   system:true, host installs → "noop" (already installed system-wide)
#   system:true, no host       → abort (a user can't trigger a root install)
#   unknown                    → abort
# The system flag stays host-owned (program specs unchanged).

@test "reconcile_user_program: a system:false program installs at user level" {
  write_program "editors" "neovim" "false"
  run reconcile_user_program neovim grub
  [ "$status" -eq 0 ]
  [ "$output" = "user" ]
}

@test "reconcile_user_program: a system program the host installs is a no-op" {
  write_program "bootloader" "grub" "true"
  run reconcile_user_program grub grub firewalld
  [ "$status" -eq 0 ]
  [ "$output" = "noop" ]
}

@test "reconcile_user_program: a system program no host installs aborts" {
  write_program "bootloader" "grub" "true"
  run reconcile_user_program grub firewalld
  [ "$status" -ne 0 ]
  [[ "$output" == *"grub"* ]]
  [[ "$output" == *"no host"* ]]
}

@test "reconcile_user_program: an unknown program aborts" {
  run reconcile_user_program nope grub
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
