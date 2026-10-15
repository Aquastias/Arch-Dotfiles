#!/usr/bin/env bats
# Tests: the Install Config schema as the one owner of install defaults
# (install_config_default / install_config_default_object) — what an absent
# field means at install time. The guided menu and seed take their defaults
# from here; Guided Launch Presets (identity, desktop, Security & Backup
# Extras) are not install defaults and stay in the seed. Shared setup in
# install-config-helpers.bash.

load install-config-helpers

@test "default: a scalar field's install default" {
  run install_config_default bootloader
  [ "$status" -eq 0 ]
  [ "$output" = "systemd-boot" ]
}

@test "default: an array field's default lists every element in order" {
  run install_config_default mirror_countries
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' Germany Switzerland Sweden France Romania)" ]
}

@test "default: an absent array field reads as its default" {
  write_config '{}'
  [ "$(install_config_mirror_countries)" \
    = "$(printf '%s\n' Germany Switzerland Sweden France Romania)" ]
  [ "$(install_config_gpu)" = "auto" ]
  [ "$(install_config_locales)" = "en_US.UTF-8" ]
  [ "$(install_config_keymaps)" = "us" ]
  [ "$(install_config_kernels)" = "lts" ]
  [ "$(install_config_optional_repos)" = "multilib" ]
}

@test "default_object: named defaults as typed JSON at their paths" {
  run install_config_default_object pacman_parallel_downloads pacman_color \
    mirror_countries bootloader
  [ "$status" -eq 0 ]
  jq -e '. == {"options":{"pacman":{"parallel_downloads":5,"color":true},
    "mirror_countries":["Germany","Switzerland","Sweden","France","Romania"],
    "bootloader":"systemd-boot"}}' <<<"$output"
}

@test "default_object: a field with no install default is left out" {
  run install_config_default_object hostname filesystem
  [ "$status" -eq 0 ]
  jq -e '. == {"filesystem":"zfs"}' <<<"$output"
}

@test "schema_names: every schema row's name, one per line" {
  run install_config_schema_names
  [ "$status" -eq 0 ]
  grep -qx bootloader <<<"$output"
  grep -qx mirror_countries <<<"$output"
  [ "$(awk 'END { print NR }' <<<"$output")" \
    -eq "${#_INSTALL_CONFIG_SCHEMA[@]}" ]
}
