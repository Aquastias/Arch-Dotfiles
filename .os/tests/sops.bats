#!/usr/bin/env bats
# Tests for programs/security/sops — SOPS runtime service

SOPS_SERVICE="$BATS_TEST_DIRNAME/../programs/security/sops/services/sops-runtime.service"
SOPS_SCRIPT="$BATS_TEST_DIRNAME/../programs/security/sops/scripts/sops-runtime.sh"

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
