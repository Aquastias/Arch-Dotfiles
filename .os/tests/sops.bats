#!/usr/bin/env bats
# Tests for programs/security/sops — SOPS runtime service

SOPS_SERVICE="$BATS_TEST_DIRNAME/../programs/security/sops/services"
SOPS_SERVICE="$SOPS_SERVICE/sops-runtime.service"
SOPS_SCRIPT="$BATS_TEST_DIRNAME/../programs/security/sops/scripts"
SOPS_SCRIPT="$SOPS_SCRIPT/sops-runtime.sh"
SOPS_ENABLE="$BATS_TEST_DIRNAME/../programs/security/sops/scripts"
SOPS_ENABLE="$SOPS_ENABLE/enable-runtime.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  chmod +x "$SOPS_SCRIPT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── systemd unit ──────────────────────────────────────────────────────────────

@test "sops-runtime.service passes systemd-analyze verify" {
  # Patch ExecStart to the in-repo script path so systemd-analyze can resolve it
  local tmp_unit="$TEST_DIR/sops-runtime.service"
  sed "s|/usr/local/lib/sops/sops-runtime.sh|${SOPS_SCRIPT}|" \
    "$SOPS_SERVICE" > "$tmp_unit"
  run systemd-analyze verify "$tmp_unit"
  [ "$status" -eq 0 ]
}

# ── enablement (impermanence-safe vendor symlink) ─────────────────────────────

@test "sops_enable_runtime enables via /usr/lib vendor wants-symlink" {
  source "$SOPS_ENABLE"
  sops_enable_runtime "$TEST_DIR"
  local link
  link="$TEST_DIR/usr/lib/systemd/system/sysinit.target.wants/sops-runtime.service"
  [ -L "$link" ]
  [ "$(readlink "$link")" = "../sops-runtime.service" ]
}

@test "sops_enable_runtime does NOT enable under /etc (rolled back by @blank)" {
  source "$SOPS_ENABLE"
  sops_enable_runtime "$TEST_DIR"
  # An /etc symlink would be lost to the impermanence rollback + bind, so the
  # unit must NOT be enabled there.
  [ ! -e "$TEST_DIR/etc/systemd/system/sysinit.target.wants/sops-runtime.service" ]
}

@test "sops_enable_runtime is idempotent" {
  source "$SOPS_ENABLE"
  sops_enable_runtime "$TEST_DIR"
  run sops_enable_runtime "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ -L "$TEST_DIR/usr/lib/systemd/system/sysinit.target.wants/sops-runtime.service" ]
}

# ── ssh-to-age ────────────────────────────────────────────────────────────────

@test "ssh-to-age derives valid age public key from fixture ed25519 host key" {
  if ! command -v ssh-to-age &>/dev/null; then
    skip "ssh-to-age not installed"
  fi
  ssh-keygen -t ed25519 -f "$TEST_DIR/ssh_host_ed25519_key" -N "" -q 2>/dev/null
  run ssh-to-age < "$TEST_DIR/ssh_host_ed25519_key.pub"
  [ "$status" -eq 0 ]
  [[ "$output" == age1* ]]
}
