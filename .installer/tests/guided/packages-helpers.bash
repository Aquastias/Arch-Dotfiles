# packages-helpers.bash — shared setup for the packages-*.bats parts
# The guided Packages screen + read-only derived section (ADR 0058).
#
# packages.repo/aur had no menu representation at all: seeding a profile
# carried its whole package payload into Config State where the operator could
# neither see nor deselect it. The screen mirrors the Categorized List shape
# the JSONC already uses — slot → category → package toggles — with three-state
# provenance reusing the existing override dot.

setup() {
  TEST_DIR="$(mktemp -d)"
  export GUIDED_STATE_FILE="$TEST_DIR/state.json"
  export GUIDED_NAV_FILE="$TEST_DIR/nav.json"
  export GUIDED_BASELINE_FILE="$TEST_DIR/base.json"
  export INSTALLER_DIR="$TEST_DIR"

  mkdir -p "$INSTALLER_DIR/hosts/core" "$INSTALLER_DIR/users/core"
  cat > "$INSTALLER_DIR/hosts/core/profile.jsonc" <<'JSON'
{"users":[],"host_programs":["cups"],
 "packages":{"repo":{"shell":["htop","fzf"],"media":["vlc"]},
             "aur":{"misc":["brave-bin"]}}}
JSON
  printf '{"shell":"/bin/zsh"}\n' > "$INSTALLER_DIR/users/core/profile.jsonc"

  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/navigation.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/edit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/config-state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/guided/controller.sh"

  printf '%s\n' '{}' > "$GUIDED_STATE_FILE"
  config_state_seed_defaults "$(config_state_new)" > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"screen":"top"}' > "$GUIDED_NAV_FILE"
}
teardown() { rm -rf "$TEST_DIR"; }

set_navigation() { printf '%s\n' "$1" > "$GUIDED_NAV_FILE"; }
state()   { cat "$GUIDED_STATE_FILE"; }
# grub is Menu-Owned (Bootloader), clamav Menu-Owned (Security), docker a
# free-standing user program, ripgrep a raw package name.
guard_registry() {
  mkdir -p "$INSTALLER_DIR/programs/bootloader/grub" \
           "$INSTALLER_DIR/programs/security/clamav" \
           "$INSTALLER_DIR/programs/virtualization/docker"
  printf '{"name":"grub","kind":"host"}\n' \
    > "$INSTALLER_DIR/programs/bootloader/grub/config.jsonc"
  printf '{"name":"clamav","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/security/clamav/config.jsonc"
  printf '{"name":"docker","kind":"user"}\n' \
    > "$INSTALLER_DIR/programs/virtualization/docker/config.jsonc"
  program_registry_build
}

