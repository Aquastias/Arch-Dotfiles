#!/usr/bin/env bats
# Tests for .os/lib/seed-generator.sh — cloud-init NoCloud seed-ISO builder.
#
# Strategy:
#   - Substitution + runcmd-shape tests inspect the rendered user-data text
#     directly via the _seed_generator_render_user_data seam, so they do not
#     require cloud-localds.
#   - The missing-cloud-localds test stubs PATH so cloud-localds is not
#     resolvable, then asserts seed_generator_build exits non-zero with a
#     clear message.

setup() {
  TEST_DIR="$(mktemp -d)"
  OUT_DIR="$TEST_DIR/out"
  mkdir -p "$OUT_DIR"

  REPO_URL="https://github.com/example/dotfiles.git"
  HOSTNAME_FIXTURE="vm-test-host"

  # shellcheck source=../lib/seed-generator.sh
  source "$BATS_TEST_DIRNAME/../lib/seed-generator.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── substitution: REPO_URL and HOSTNAME appear literally in user-data ────────

@test "user-data: contains literal REPO_URL with no placeholder remaining" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "$REPO_URL" ]]
  [[ ! "$output" =~ \$\{?REPO_URL\}? ]]
}

@test "user-data: contains literal HOSTNAME with no placeholder remaining" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "\"$HOSTNAME_FIXTURE\"" ]]
  [[ ! "$output" =~ \$\{?HOSTNAME\}? ]]
}

# ── runcmd shape: cloud-config header, ttyS0 redirect, sentinel, poweroff ────

@test "user-data: starts with #cloud-config header" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  first_line="$(printf '%s\n' "$output" | head -1)"
  [ "$first_line" = "#cloud-config" ]
}

@test "user-data: redirects to /dev/ttyS0 in runcmd" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "exec > /dev/ttyS0 2>&1" ]]
}

@test "user-data: runs install.sh --unattended" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "./install.sh --unattended" ]]
}

@test "user-data: emits the sentinel line in the documented format" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "===INSTALLER-EXIT-%d===" ]]
  [[ "$output" =~ "> /dev/ttyS0" ]]
}

@test "user-data: ends the runcmd with sync + poweroff" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sync" ]]
  [[ "$output" =~ "poweroff -f" ]]
}

@test "user-data: clones the repo into /root/dotfiles" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "git clone $REPO_URL /root/dotfiles" ]]
  [[ "$output" =~ "rm -rf /root/dotfiles" ]]
}

@test "user-data: patches install.jsonc hostname before running install" {
  run _seed_generator_render_user_data "$REPO_URL" "$HOSTNAME_FIXTURE"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "sed -i" ]]
  [[ "$output" =~ "install.jsonc" ]]
}

# ── missing cloud-localds is a clear failure (no install attempt) ────────────

@test "missing cloud-localds: returns non-zero with a clear message" {
  PATH="/this/does/not/exist" run seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "cloud-localds not found" ]]
}

# ── empty inputs are rejected ────────────────────────────────────────────────

@test "empty repo URL: returns non-zero" {
  run seed_generator_build "" "$HOSTNAME_FIXTURE" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "REPO_URL is empty" ]]
}

@test "empty hostname: returns non-zero" {
  run seed_generator_build "$REPO_URL" "" "$OUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "HOSTNAME is empty" ]]
}

@test "missing output dir: returns non-zero" {
  run seed_generator_build "$REPO_URL" "$HOSTNAME_FIXTURE" "$TEST_DIR/nope"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "output directory does not exist" ]]
}
