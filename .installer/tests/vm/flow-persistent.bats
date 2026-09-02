#!/usr/bin/env bats
# Tests for vm/lib/flow-persistent.sh — the SSH-debug affordance on persistent
# VMs: the boot seed authorizes the harness key on the live ISO + sets up a root
# autologin getty on ttyS0 (ADR 0099), the rendered in-VM installer script
# enables sshd for the INSTALLED guest, and the harness key is generated on
# demand.

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

@test "render: does NOT set dotfiles_repo (installer never stows — ADR 0095)" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"],"options":{}}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAAKEY test' aquastias
  [ "$status" -eq 0 ]
  [[ "$output" != *'.dotfiles_repo ='* ]]
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

@test "render: captures a log to a retrievable file" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAALIVE k' aquastias
  [ "$status" -eq 0 ]
  # Install output captured to a retrievable file (never streamed to serial).
  [[ "$output" == *'tee /root/install.log'* ]]
}

@test "render: no longer authorizes the live-ISO key (the seed does — ADR 0099)" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAALIVE k' aquastias
  [ "$status" -eq 0 ]
  # The live-ISO /root authorize moved out of the payload into the boot seed, so
  # a failure before this payload runs still leaves the live ISO reachable.
  [[ "$output" != *'/root/.ssh/authorized_keys'* ]]
}

@test "seed: authorizes the harness key on the live ISO, no install runcmd" {
  run _flow_render_seed_user_data 'ssh-ed25519 AAAASEED k'
  [ "$status" -eq 0 ]
  [[ "$output" == *'#cloud-config'* ]]
  [[ "$output" == *'/root/.ssh/authorized_keys'* ]]
  [[ "$output" == *'ssh-ed25519 AAAASEED k'* ]]
  # sshd is ensured so SSH works even if the typed payload never runs.
  [[ "$output" == *'sshd'* ]]
  # NO install runcmd: the installer is typed via curl|bash, not seeded.
  [[ "$output" != *'install.sh'* ]]
  [[ "$output" != *'git clone'* ]]
}

@test "seed: sets up a root autologin getty on ttyS0" {
  run _flow_render_seed_user_data 'ssh-ed25519 AAAASEED k'
  [ "$status" -eq 0 ]
  [[ "$output" == *'serial-getty@ttyS0'* ]]
  [[ "$output" == *'--autologin root'* ]]
  [[ "$output" == *'ttyS0'* ]]
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
