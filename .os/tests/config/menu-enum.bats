#!/usr/bin/env bats
# Tests for .os/lib/config/menu.sh — menu_enum_options, the single source of
# truth for enumerable-field option sets. Both the interactive controller
# (_ctl_*) and the replay editors (_guided_edit_*) read it, so the two guided
# front-ends can never drift on what a field offers. Pure: no TTY.

setup() {
  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/menu.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
}

@test "menu_enum_options: kernel flavours" {
  run menu_enum_options options.kernel
  [ "$status" -eq 0 ]
  [ "$output" == "$(printf '%s\n' lts default hardened zen)" ]
}

@test "menu_enum_options: bootloader" {
  run menu_enum_options options.bootloader
  [ "$output" == "$(printf '%s\n' systemd-boot grub)" ]
}

@test "menu_enum_options: desktop" {
  run menu_enum_options environment.desktop
  [ "$output" == "$(printf '%s\n' kde)" ]
}

@test "menu_enum_options: gpu vendors (auto first)" {
  run menu_enum_options environment.gpu
  [ "$output" == "$(printf '%s\n' auto amd nvidia intel)" ]
}

@test "menu_enum_options: firewall (mutually-exclusive radiolist)" {
  run menu_enum_options post_install.security.firewall
  [ "$output" == "$(printf '%s\n' firewalld ufw none)" ]
}

@test "menu_enum_options: mirror countries keep multi-word entries intact" {
  run menu_enum_options options.mirror_countries
  [ "$status" -eq 0 ]
  # multi-word countries must survive as single lines, not split on space.
  echo "$output" | grep -qx "United Kingdom"
  echo "$output" | grep -qx "United States"
  [ "$(echo "$output" | head -1)" == "Germany" ]
}

@test "menu_enum_options: unknown / free-text field emits nothing" {
  run menu_enum_options system.hostname
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Drift guard: the centralised sets must not be re-listed literally in either
# guided front-end. If a hardcoded copy reappears, this fails — the whole point
# of the single authority (the interactive/replay drift bug it closes).
@test "drift guard: kernel flavour list appears only in menu.sh" {
  local lib="$BATS_TEST_DIRNAME/../../lib"
  run grep -rn 'hardened zen' "$lib/guided.sh" "$lib/guided-controller.sh"
  [ "$status" -ne 0 ]
}

@test "drift guard: gpu vendor list appears only in menu.sh" {
  local lib="$BATS_TEST_DIRNAME/../../lib"
  run grep -rn 'amd nvidia intel' "$lib/guided.sh" "$lib/guided-controller.sh"
  [ "$status" -ne 0 ]
}
