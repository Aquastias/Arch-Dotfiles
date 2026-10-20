#!/usr/bin/env bats
# Tests for the install plan summary (lib/config/lifecycle.sh).

setup() {
  export CONFIG_FILE="$BATS_TEST_TMPDIR/install.jsonc"
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  # shellcheck source=../../lib/config/lifecycle.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/lifecycle.sh"
}

@test "the Security & Backup Extras line is comma-joined" {
  # The separators alternated "," and " " ("ufw,clamav rkhunter").
  echo '{"post_install": {"security": {"firewall": "ufw", "antivirus": true,
         "rootkit": true}}}' >"$CONFIG_FILE"
  run _lifecycle_print_extras
  [[ "$output" == *"install:"*"ufw, clamav, rkhunter"* ]]
}
