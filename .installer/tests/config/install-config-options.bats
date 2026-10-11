#!/usr/bin/env bats
# Tests: option accessors (split from install-config.bats;
# shared setup in install-config-helpers.bash)

load install-config-helpers


# ── options.encryption_method (ADR 0040): default derived from filesystem ────

@test "encryption_method: defaults to native for zfs" {
  write_config '{}'                      # filesystem defaults to zfs
  run install_config_encryption_method
  [ "$status" -eq 0 ]
  [ "$output" = "native" ]
}

@test "encryption_method: defaults to luks for a non-zfs filesystem" {
  write_config '{"filesystem":"btrfs"}'
  run install_config_encryption_method
  [ "$status" -eq 0 ]
  [ "$output" = "luks" ]
}

@test "encryption_method: an explicit method overrides the derived default" {
  write_config '{"filesystem":"zfs","options":{"encryption_method":"luks"}}'
  run install_config_encryption_method
  [ "$status" -eq 0 ]
  [ "$output" = "luks" ]
}


# ── install_config_get: unknown name errors ─────────────────────────────────

@test "install_config_get: unknown name exits non-zero" {
  write_config '{}'
  run install_config_get bogus_field
  [ "$status" -ne 0 ]
}


# ── Pacman Options (ADR 0074): defaults on absence, value when set ───────────

@test "pacman options: defaults when the options.pacman.* keys are absent" {
  write_config '{}'
  [ "$(install_config_pacman_ilovecandy)" = "true" ]
  [ "$(install_config_pacman_color)" = "true" ]
  [ "$(install_config_pacman_verbose_pkg_lists)" = "true" ]
  [ "$(install_config_pacman_disable_download_timeout)" = "false" ]
  [ "$(install_config_pacman_no_progress_bar)" = "false" ]
  [ "$(install_config_pacman_parallel_downloads)" = "5" ]
}

@test "pacman options: an explicit false stays false, a set number is read" {
  write_config '{"options":{"pacman":{"ilovecandy":false,"parallel_downloads":10}}}'
  [ "$(install_config_pacman_ilovecandy)" = "false" ]
  [ "$(install_config_pacman_parallel_downloads)" = "10" ]
}

@test "apparmor_enabled: follows the resolved Security Extras selection" {
  write_config '{"post_install":{"security":{"apparmor":true}}}'
  [ "$(install_config_apparmor_enabled)" = "true" ]
  write_config '{"post_install":{"security":{"apparmor":false}}}'
  [ "$(install_config_apparmor_enabled)" = "false" ]
  write_config '{}'
  [ "$(install_config_apparmor_enabled)" = "false" ]
  # a legacy bool security block is off, never a jq error
  write_config '{"post_install":{"security":true}}'
  [ "$(install_config_apparmor_enabled)" = "false" ]
}
