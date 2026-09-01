#!/usr/bin/env bats
# Tests for vm/lib/flow-persistent.sh — the SSH-debug affordance on persistent
# VMs: the rendered in-VM installer script enables sshd + authorizes the harness
# key, and the harness key is generated on demand.

setup() {
  FLOW="$BATS_TEST_DIRNAME/../../vm/lib/flow-persistent.sh"
  CACHE_DIR="$(mktemp -d)"
  export CACHE_DIR
  # shellcheck disable=SC1090
  source "$FLOW"
}

teardown() { rm -rf "$CACHE_DIR"; }

@test "render: enables sshd in the effective config" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"],"options":{}}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAAKEY test' aquastias
  [ "$status" -eq 0 ]
  [[ "$output" == *'.options.ssh.enabled = true'* ]]
}

@test "render: sets dotfiles_repo so the curated config gets stowed" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"],"options":{}}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAAKEY test' aquastias
  [ "$status" -eq 0 ]
  [[ "$output" == *'.dotfiles_repo = $r'* ]]
  [[ "$output" == *'--arg r '\''https://example/repo.git'\'''* ]]
}

@test "render: authorizes the harness pubkey for the primary user" {
  INSTALL_CONFIG_CONTENT='{"users":["bob"],"options":{}}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAAKEY test' bob
  [ "$status" -eq 0 ]
  [[ "$output" == *'users/bob/profile.jsonc'* ]]
  [[ "$output" == *'ssh-ed25519 AAAAKEY test'* ]]
  [[ "$output" == *'ssh_authorized_keys'* ]]
}

@test "render: still clones the repo and runs the unattended installer" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [[ "$output" == *'git clone https://example/repo.git /root/dotfiles'* ]]
  [[ "$output" == *'./install.sh --unattended install.jsonc'* ]]
  # jq is needed in the live ISO to patch the config before install.sh runs.
  [[ "$output" == *'--needed git jq'* ]]
}

@test "harness key: generated on demand when absent" {
  command -v ssh-keygen >/dev/null || skip "ssh-keygen not available"
  run _harness_ensure_key
  [ "$status" -eq 0 ]
  [ -f "$CACHE_DIR/harness_ed25519" ]
  [ -f "$CACHE_DIR/harness_ed25519.pub" ]
  grep -q '^ssh-ed25519 ' "$CACHE_DIR/harness_ed25519.pub"
}

@test "harness key: idempotent — never overwrites an existing key" {
  command -v ssh-keygen >/dev/null || skip "ssh-keygen not available"
  _harness_ensure_key
  cp "$CACHE_DIR/harness_ed25519.pub" "$CACHE_DIR/first.pub"
  _harness_ensure_key
  diff "$CACHE_DIR/harness_ed25519.pub" "$CACHE_DIR/first.pub"
}
