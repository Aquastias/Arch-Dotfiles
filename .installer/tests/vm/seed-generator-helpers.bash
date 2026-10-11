# seed-generator-helpers.bash — shared setup for the seed-generator-*.bats parts
# Tests for .installer/lib/seed-generator.sh — cloud-init NoCloud seed-ISO
# builder.
#
# Strategy:
#   - Substitution + runcmd-shape tests inspect the rendered user-data text
#     directly via the _seed_generator_render_user_data seam, so they do not
#     require cloud-localds.
#   - The missing-cloud-localds test stubs PATH so cloud-localds is not
#     resolvable, then asserts vm_seed_generator_build exits non-zero with a
#     clear message.

setup() {
  TEST_DIR="$(mktemp -d)"
  OUT_DIR="$TEST_DIR/out"
  mkdir -p "$OUT_DIR"

  REPO_URL="https://github.com/example/dotfiles.git"
  HOSTNAME_FIXTURE="vm-test-host"

  # shellcheck source=../../vm/lib/seed-generator.sh
  source "$BATS_TEST_DIRNAME/../../vm/lib/seed-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

