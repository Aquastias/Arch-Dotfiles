# controller-helpers.bash — shared setup for the controller-*.bats parts
# Tests for .installer/lib/guided/controller.sh — the persistent-fzf controller
# (ADR
# 0042). The controller is driven entirely through its state files (no fzf, no
# tty), so behaviour is asserted through the public interface: the rendered list
# for a screen, and the (directive + file mutation) of an enter/back. Every
# field commits natively in fzf now (no edit-oneshot hand-off).

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  # Hermetic hosts/ root: no installable profiles here, so the top-screen
  # Profiles row (ADR 0055) stays hidden unless a test wires its own tree.
  export INSTALLER_DIR="$TEST_DIR"

  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/navigation.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided/controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  printf '%s\n' '{}' > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_navigation() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }
# The baseline seeds every menu default (seed.sh); the apply-time normalise drops
# an override that lands back on that default, so ● (override-only) never lights
# for an unchanged value. Regression for the "select zfs → marked modified" bug.

_seed_baseline() {
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  config_state_seed_defaults "$(config_state_new)" > "$GUIDED_BASELINE_FILE"
}

adhoc_editor_setup() {          # an ad-hoc user 'dave' with a userforms file
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/core"; printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
}
# The two pickers have opposite requirements and used to share one unfiltered
# list. Assert *which options are offered*, not only the [x]/[ ] marking —
# marking-only assertions are exactly what let the bad option sets through.

# Two programs of each kind under a hermetic INSTALLER_DIR.
mixed_programs_setup() {
  export INSTALLER_DIR="$TEST_DIR"
  local spec cat name knd
  for spec in "bootloader/grub/host" "printing/cups/host" \
              "virtualization/docker/user" "security/borg/user"; do
    IFS=/ read -r cat name knd <<<"$spec"
    mkdir -p "$INSTALLER_DIR/programs/$cat/$name"
    printf '{"name":"%s","kind":"%s"}\n' "$name" "$knd" \
      > "$INSTALLER_DIR/programs/$cat/$name/config.jsonc"
    printf '#!/bin/sh\n' > "$INSTALLER_DIR/programs/$cat/$name/install.sh"
  done
}

secret_setup() {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  export GUIDED_PWBUF_FILE="$TEST_DIR/pwbuf"; : > "$GUIDED_PWBUF_FILE"
  export GUIDED_PWPENDING_FILE="$TEST_DIR/pwpending"; : > "$GUIDED_PWPENDING_FILE"
}

