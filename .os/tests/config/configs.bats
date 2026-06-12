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

# ── real Host Core conforms to ADR 0007 (no Host Package List in core) ────────

@test "real host core declares no packages object (ADR 0007)" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  jsonc_strip "$core" | jq -e '.packages == null'
}

@test "real host core system_programs is exactly [cups]" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  jsonc_strip "$core" | jq -e '.system_programs == ["cups"]'
}

# ── real Host Profiles are deduped vs Base/adapters/User Programs (issue 04) ──
# Every package an essentials script, a Bootloader/DE Adapter, the paru
# bootstrap, or a User Program already installs must NOT be re-declared in a
# Host Profile. These guards read the real desktop/laptop profiles.

DESKTOP_CFG="$BATS_TEST_DIRNAME/../../hosts/desktop/profile.jsonc"
LAPTOP_CFG="$BATS_TEST_DIRNAME/../../hosts/laptop/profile.jsonc"

_repo_pkgs() { jsonc_strip "$1" | jq -r '.packages.repo | to_entries[].value[]'; }
_repo_cats() { jsonc_strip "$1" | jq -r '.packages.repo | keys[]'; }
_aur_pkgs()  { jsonc_strip "$1" | jq -r '.packages.aur  | to_entries[].value[]'; }

# Packages owned elsewhere — none may appear in any Host Profile packages.repo.
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
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local f
  for f in "$DESKTOP_CFG" "$LAPTOP_CFG"; do
    local repo; repo="$(jsonc_strip "$f" | jq -c '.packages.repo')"
    run categorized_list_parse "$repo" string packages.repo
    [ "$status" -eq 0 ]
  done
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
