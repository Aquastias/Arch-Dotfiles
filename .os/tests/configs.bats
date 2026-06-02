#!/usr/bin/env bats
# Tests for .os/lib/configs.sh — host/user config loader/merger.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"
  # shellcheck source=../lib/configs.sh
  source "$BATS_TEST_DIRNAME/../lib/configs.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

# ── core + empty specific ─────────────────────────────────────────────────────

@test "host: core + empty specific returns core fields unchanged" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice"], "system_programs": ["firewalld"]}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
}

# ── real Host Core conforms to ADR 0007 (no Host Package List in core) ────────

@test "real host core declares no packages object (ADR 0007)" {
  local core="$BATS_TEST_DIRNAME/../hosts/core/config.jsonc"
  jsonc_strip "$core" | jq -e '.packages == null'
}

@test "real host core system_programs is exactly [cups]" {
  local core="$BATS_TEST_DIRNAME/../hosts/core/config.jsonc"
  jsonc_strip "$core" | jq -e '.system_programs == ["cups"]'
}

@test "host: core without packages object preserves host packages on merge" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": [], "system_programs": ["cups"], "sysctl": {"vm.swappiness": 10}}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" \
    '{"users": ["alice"], "packages": {"repo": {"shell": ["zsh"]}}}'

  run load_host_config desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system_programs == ["cups"]'
  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.packages.repo.shell == ["zsh"]'
}

# ── real Host Configs are deduped vs Base/adapters/User Programs (issue 04) ───
# Every package an essentials script, a Bootloader/DE Adapter, the paru
# bootstrap, or a User Program already installs must NOT be re-declared in a
# Host Config. These guards read the real desktop/laptop configs.

DESKTOP_CFG="$BATS_TEST_DIRNAME/../hosts/desktop/config.jsonc"
LAPTOP_CFG="$BATS_TEST_DIRNAME/../hosts/laptop/config.jsonc"

_repo_pkgs() { jsonc_strip "$1" | jq -r '.packages.repo | to_entries[].value[]'; }
_repo_cats() { jsonc_strip "$1" | jq -r '.packages.repo | keys[]'; }
_aur_pkgs()  { jsonc_strip "$1" | jq -r '.packages.aur  | to_entries[].value[]'; }

# Packages owned elsewhere — none may appear in any Host Config packages.repo.
_assert_no_duplicates() {
  local pkgs; pkgs="$(_repo_pkgs "$1")"
  local p
  for p in base base-devel amd-ucode efibootmgr linux-firmware man-db \
           dosfstools networkmanager jq vim git cronie grub os-prober \
           timeshift kimageformats5 extra-cmake-modules apparmor clamav \
           rkhunter unhide xorg-xinit hyprland wl-clipboard grim slurp \
           nwg-look wofi dunst xdg-desktop-portal-hyprland \
           xdg-desktop-portal-gtk; do
    if grep -qx "$p" <<< "$pkgs"; then
      echo "leftover duplicate package: $p"
      return 1
    fi
  done
}

@test "desktop repo declares no Base/adapter/User-Program duplicates" {
  _assert_no_duplicates "$DESKTOP_CFG"
}

@test "laptop repo declares no Base/adapter/User-Program duplicates" {
  _assert_no_duplicates "$LAPTOP_CFG"
}

@test "desktop repo adds parallel; keeps xdg-utils + qt-wayland + papirus" {
  local pkgs; pkgs="$(_repo_pkgs "$DESKTOP_CFG")"
  grep -qx "parallel"           <<< "$pkgs"
  grep -qx "xdg-utils"          <<< "$pkgs"
  grep -qx "qt5-wayland"        <<< "$pkgs"
  grep -qx "qt6-wayland"        <<< "$pkgs"
  grep -qx "papirus-icon-theme" <<< "$pkgs"
}

@test "laptop repo adds parallel; keeps xdg-utils + qt5-wayland" {
  local pkgs; pkgs="$(_repo_pkgs "$LAPTOP_CFG")"
  grep -qx "parallel"    <<< "$pkgs"
  grep -qx "xdg-utils"   <<< "$pkgs"
  grep -qx "qt5-wayland" <<< "$pkgs"
}

@test "desktop+laptop repo group residual generals under 'desktop' category" {
  local f
  for f in "$DESKTOP_CFG" "$LAPTOP_CFG"; do
    local cats; cats="$(_repo_cats "$f")"
    grep -qx "desktop"    <<< "$cats"
    ! grep -qx "qt-and-kde" <<< "$cats"
    ! grep -qx "hyprland"   <<< "$cats"
  done
}

@test "desktop+laptop repo declares no sops/age (ADR 0025 owns them)" {
  local f
  for f in "$DESKTOP_CFG" "$LAPTOP_CFG"; do
    local pkgs; pkgs="$(_repo_pkgs "$f")"
    ! grep -qx "sops" <<< "$pkgs"
    ! grep -qx "age"  <<< "$pkgs"
  done
}

@test "desktop+laptop aur drops bootstrapped paru and clamav companion" {
  local f
  for f in "$DESKTOP_CFG" "$LAPTOP_CFG"; do
    local aur; aur="$(_aur_pkgs "$f")"
    ! grep -qx "paru"                  <<< "$aur"
    ! grep -qx "clamav-unofficial-sigs" <<< "$aur"
  done
}

@test "desktop keeps system_programs [grub] with no grub/os-prober package" {
  jsonc_strip "$DESKTOP_CFG" | jq -e '.system_programs == ["grub"]'
  local pkgs; pkgs="$(_repo_pkgs "$DESKTOP_CFG")"
  ! grep -qx "grub"      <<< "$pkgs"
  ! grep -qx "os-prober" <<< "$pkgs"
}

@test "real desktop+laptop packages.repo parse as Categorized Lists" {
  source "$BATS_TEST_DIRNAME/../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../lib/categorized-list.sh"
  local f
  for f in "$DESKTOP_CFG" "$LAPTOP_CFG"; do
    local repo; repo="$(jsonc_strip "$f" | jq -c '.packages.repo')"
    run categorized_list_parse "$repo" string packages.repo
    [ "$status" -eq 0 ]
  done
}

# ── empty core + specific ─────────────────────────────────────────────────────

@test "host: empty core + specific returns specific fields unchanged" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" \
    '{"users": ["bob"], "system_programs": ["docker"]}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["bob"]'
  echo "$output" | jq -e '.system_programs == ["docker"]'
}

# ── list concatenation with dedupe ────────────────────────────────────────────

@test "host: list fields concatenate with dedupe (order preserved)" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice", "shared"], "system_programs": ["firewalld"]}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" \
    '{"users": ["shared", "bob"], "system_programs": ["docker"]}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice", "shared", "bob"]'
  echo "$output" | jq -e '.system_programs == ["firewalld", "docker"]'
}

# ── scalar override ───────────────────────────────────────────────────────────

@test "user: scalar fields are overridden by specific" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/bash", "sudo": false}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"shell": "/bin/zsh", "sudo": true}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.sudo == true'
}

# ── missing field preservation ────────────────────────────────────────────────

@test "user: field present only in core is preserved" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/zsh", "groups": ["wheel"]}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"programs": ["teamspeak3"]}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.groups == ["wheel"]'
  echo "$output" | jq -e '.programs == ["teamspeak3"]'
}

@test "user: field present only in specific is preserved" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/bash"}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"git": {"name": "Alex", "email": "alex@example.com"}}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '.git.name == "Alex"'
  echo "$output" | jq -e '.git.email == "alex@example.com"'
}

# ── missing core file is hard error ───────────────────────────────────────────

@test "host: missing core file is a hard error (exit 2)" {
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{"users": ["alice"]}'

  run load_host_config desktop
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing hosts core config" ]]
}

@test "user: missing core file is a hard error (exit 2)" {
  write_config "$TEST_DIR/users/alex/config.jsonc" '{"shell": "/bin/zsh"}'

  run load_user_config alex
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing users core config" ]]
}

# ── missing specific config is graceful (exit 1, core only) ──────────────────

@test "host: missing specific config returns core with exit 1" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" \
    '{"users": ["alice"], "system_programs": ["firewalld"]}'

  run load_host_config desktop
  [ "$status" -eq 1 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
}

@test "user: missing specific config returns core with exit 1" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"shell": "/bin/zsh", "groups": ["wheel"]}'

  run load_user_config alex
  [ "$status" -eq 1 ]

  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.groups == ["wheel"]'
}

# ── reserved name ─────────────────────────────────────────────────────────────

@test "host: 'core' as hostname is rejected (exit 3)" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{"users": ["alice"]}'

  run load_host_config core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "user: 'core' as username is rejected (exit 3)" {
  write_config "$TEST_DIR/users/core/config.jsonc" '{"shell": "/bin/bash"}'

  run load_user_config core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

# ── deep object merging (bonus, supports git.name + git.email composition) ────

@test "user: object fields are deep-merged" {
  write_config "$TEST_DIR/users/core/config.jsonc" \
    '{"git": {"name": "Default User"}}'
  write_config "$TEST_DIR/users/alex/config.jsonc" \
    '{"git": {"email": "alex@example.com"}}'

  run load_user_config alex
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.git.name == "Default User"'
  echo "$output" | jq -e '.git.email == "alex@example.com"'
}

# ── JSONC comments are stripped ───────────────────────────────────────────────

@test "host: JSONC // comments are stripped before parsing" {
  write_config "$TEST_DIR/hosts/core/config.jsonc" '{
  // comment on its own line
  "users": ["alice"], // trailing comment
  "system_programs": ["firewalld"]
}'
  write_config "$TEST_DIR/hosts/desktop/config.jsonc" '{}'

  run load_host_config desktop
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.system_programs == ["firewalld"]'
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
