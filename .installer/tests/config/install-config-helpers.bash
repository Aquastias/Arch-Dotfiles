# install-config-helpers.bash — shared setup for the install-config-*.bats parts
# Tests for .installer/lib/config/install-config.sh — schema-driven Install Config
# reader.
#
# Structure (ADR 0015):
#   1. Parameterised loop over _INSTALL_CONFIG_SCHEMA — default-on-absent
#      and value-on-present per row.
#   2. Bool null-distinction — literal null falls back to default; explicit
#      false stays false.
#   3. Array union/null behaviour — string|array union, null, absent.
#   4. Four specials — gpu, packages_groups, storage_group_ashift, plus the
#      array-with-no-default behaviour.

setup() {
  TEST_DIR="$(mktemp -d)"
  export CONFIG_FILE="$TEST_DIR/install.jsonc"

  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_config() { printf '%s\n' "$1" > "$CONFIG_FILE"; }

# Write a config that sets <jq_path> to <value> in an empty object.
# value must be a JSON literal (quoted strings, raw bools, raw arrays).
set_path_config() {
  local jq_path="$1" value="$2"
  echo '{}' | jq --argjson v "$value" "$jq_path = \$v" > "$CONFIG_FILE"
}

