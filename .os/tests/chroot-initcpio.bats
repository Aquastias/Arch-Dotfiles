#!/usr/bin/env bats
# Tests for _initcpio_hooks_line() in lib/chroot/initcpio.sh.
# Pure function: takes modconf hook name + impermanence-enabled flag, emits
# the HOOKS=(...) line for /etc/mkinitcpio.conf.

setup() {
  TEST_DIR="$(mktemp -d)"
  export STATE="$TEST_DIR/install-state.json"
  cat > "$STATE" <<'JSON'
{"hostname":"h","timezone":"UTC","locale":"en_US.UTF-8","keymap":"us",
 "kernel":"lts", "kernels": ["lts"],"bootloader":"systemd-boot","rpool":"rpool","swap":true,
 "esp_count":1,"extras":{"backup":false,"security":false},
 "impermanence":{"enabled":false,"dataset":"rpool/persist","mount":"/persist"},
 "persist":{"directories":[],"files":[]}}
JSON
  # Source initcpio.sh in lib-only mode so its side-effect block doesn't run.
  INITCPIO_LIB_ONLY=1 source \
    "$BATS_TEST_DIRNAME/../lib/chroot/initcpio.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── disabled: HOOKS line unchanged ───────────────────────────────────────────

@test "impermanence disabled: HOOKS ends with 'zfs filesystems'" {
  run _initcpio_hooks_line kmod false
  [ "$status" -eq 0 ]
  [ "$output" = \
    "HOOKS=(base udev autodetect kmod block keyboard zfs filesystems)" ]
}

# ── enabled: zfs-rollback inserted between zfs and filesystems ───────────────

@test "impermanence enabled: zfs-rollback between zfs and filesystems" {
  run _initcpio_hooks_line kmod true
  [ "$status" -eq 0 ]
  [ "$output" = \
"HOOKS=(base udev autodetect kmod block keyboard zfs zfs-rollback filesystems)"\
  ]
}

@test "impermanence enabled with modconf (older mkinitcpio)" {
  run _initcpio_hooks_line modconf true
  [ "$status" -eq 0 ]
  [[ "$output" == *"modconf block keyboard zfs zfs-rollback filesystems"* ]]
}
