#!/usr/bin/env bats
# Tests: binding the Install Config Reader to an Effective Config held as JSON
# (install_config_use_json) instead of the CONFIG_FILE file — so a module that
# holds JSON (Package Resolver, Feature Audit gate) reads through the same
# accessors, paths and defaults. Shared setup in install-config-helpers.bash.

load install-config-helpers

@test "bind: an accessor reads the bound JSON, not CONFIG_FILE" {
  write_config '{"options":{"bootloader":"grub"}}'
  install_config_use_json '{"options":{"bootloader":"limine"}}'
  run install_config_bootloader
  [ "$status" -eq 0 ]
  [ "$output" = "limine" ]
}

@test "bind: an absent field takes its schema default" {
  install_config_use_json '{}'
  [ "$(install_config_bootloader)" = "systemd-boot" ]
  [ "$(install_config_filesystem)" = "zfs" ]
}

@test "bind: an explicit false bool stays false" {
  install_config_use_json '{"options":{"impermanence":{"enabled":false}}}'
  [ "$(install_config_impermanence_enabled)" = "false" ]
}

@test "bind: derived predicates read the bound JSON" {
  write_config '{}'
  install_config_use_json '{"filesystem":"ext4",
    "storage_groups":[{"name":"bulk","filesystem":"zfs"}],
    "data_pools":[{"name":"t","filesystem":"xfs","encryption":true}]}'
  [ "$(install_config_any_zfs)" = "true" ]
  [ "$(install_config_any_nonzfs_luks)" = "true" ]
  [ "$(install_config_uses_filesystem xfs)" = "true" ]
}

@test "bind: a bind inside a subshell does not leak to the caller" {
  write_config '{"options":{"bootloader":"grub"}}'
  [ "$( (install_config_use_json '{}'; install_config_bootloader) )" \
    = "systemd-boot" ]
  [ "$(install_config_bootloader)" = "grub" ]
}

@test "bind: an empty bind reads CONFIG_FILE again" {
  write_config '{"options":{"bootloader":"grub"}}'
  install_config_use_json '{"options":{"bootloader":"limine"}}'
  install_config_use_json ""
  [ "$(install_config_bootloader)" = "grub" ]
}
