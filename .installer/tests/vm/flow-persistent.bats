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
  [[ "$output" == *'tee -a /root/install.log'* ]]
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

@test "render: emits an exit sentinel (serial + marker file) on any outcome" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [ "$status" -eq 0 ]
  # The captured rc drives the sentinel the host greps for (===INSTALLER-EXIT-N).
  [[ "$output" == *'PIPESTATUS'* ]]
  [[ "$output" == *'===INSTALLER-EXIT-%d==='* ]]
  [[ "$output" == *'> /dev/ttyS0'* ]]
  [[ "$output" == *'/root/.install-exit'* ]]
}

@test "render: only powers off on a clean install (holds up on failure)" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [ "$status" -eq 0 ]
  # poweroff is guarded by rc==0, so a failed install leaves the live ISO up.
  [[ "$output" == *'if [ "$rc" -eq 0 ]'* ]]
  [[ "$output" == *'poweroff'* ]]
}

@test "render: routes the installed kernel to serial on a clean install" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [ "$status" -eq 0 ]
  # console=ttyS0 patched onto the installed loader entries so a broken boot of
  # this debug VM is never silent (ADR 0099); only on a clean install (rc==0).
  [[ "$output" == *'console=ttyS0,115200'* ]]
  [[ "$output" == *'loader/entries'* ]]
}

@test "_report_failure_access: prints live-ISO ssh, serial, log, and cleanup" {
  VM_NAME="failvm"
  _vm_ip_now() { echo "192.168.122.99"; }
  run _report_failure_access
  [ "$status" -eq 0 ]
  # SSH to the live ISO as root (the seed authorized the harness key there).
  [[ "$output" == *'root@192.168.122.99'* ]]
  # The zero-network serial fallback and where the log lives.
  [[ "$output" == *'virsh console failvm'* ]]
  [[ "$output" == *'/root/install.log'* ]]
  # A failed VM is never auto-destroyed — cleanup is a printed one-liner.
  [[ "$output" == *'virsh destroy failvm'* ]]
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

@test "render: holds for a host log pull before poweroff when asked" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  VM_HOLD_FOR_LOG_PULL=1 run _render_installer_script https://example/repo.git \
    'k' aquastias
  [ "$status" -eq 0 ]
  [[ "$output" == *'/root/.log-pulled'* ]]
  # the hold sits before poweroff
  local hold pow
  hold="$(grep -n 'log-pulled' <<<"$output" | head -1 | cut -d: -f1)"
  pow="$(grep -n '^  poweroff' <<<"$output" | cut -d: -f1)"
  [ "$hold" -lt "$pow" ]
}

@test "render: no log-pull hold by default" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [[ "$output" != *'log-pulled'* ]]
}

@test "render: an early payload death still emits an exit sentinel" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  # an EXIT trap reports a failure before install.sh even ran (bad clone,
  # pacman error), so the host never waits out the full install timeout
  [[ "$output" == *"INSTALLER-EXIT-"*"trap _early_exit EXIT"* ]]
  [[ "$output" == *'rm -f /root/.install-exit'* ]]
}

@test "render: exports a serial console cmdline for every loader" {
  # efistub/limine/refind boots went dark on serial, so the Console Answerer
  # never saw the unlock prompt (Audit Run 20260929). The installer appends
  # INSTALL_EXTRA_CMDLINE to every adapter's DEFAULT_OPTS.
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"],"options":{}}'
  run _render_installer_script https://example/repo.git \
    'ssh-ed25519 AAAAKEY test' aquastias
  [ "$status" -eq 0 ]
  [[ "$output" == *"export INSTALL_EXTRA_CMDLINE='console=ttyS0,115200'"* ]]
}

# tuned 20261008: the live ISO named SATA disks out of port order (sdb was
# the 20G disk), so a "/dev/sda","/dev/sdb" mirror landed on the wrong disk
@test "pin_disks: maps /dev/sdX to the port's by-id path when present" {
  local d="$BATS_TEST_TMPDIR" b
  b="$d/by-id/ata-QEMU_HARDDISK_vmdisk"
  mkdir -p "$d/by-id"
  touch "${b}0" "${b}1"
  echo '{"os_pool":{"disks":["/dev/sda","/dev/sdb"]},"x":["/dev/sdc"]}' \
    > "$d/c.json"
  eval "$(_flow_pin_disks_fn)"
  pin_disks "$d/c.json" "$d/by-id"
  run jq -r '[.os_pool.disks[], .x[]] | join(" ")' "$d/c.json"
  [ "$output" = "${b}0 ${b}1 /dev/sdc" ]
}

@test "render: pins disks before the installer runs" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [[ "$output" == *'pin_disks install.jsonc'* ]]
}

# ufw 20261008: the preamble (pacman/git) died before install.sh, leaving
# no log to pull; its output now lands in the log, its fetches are retried
@test "render: the preamble is logged and its fetches retried" {
  INSTALL_CONFIG_CONTENT='{"users":["aquastias"]}'
  run _render_installer_script https://example/repo.git 'k' aquastias
  [[ "$output" == *'> >(tee -a /root/install.log) 2>&1'* ]]
  [[ "$output" == *'_try pacman -Sy --noconfirm --needed git jq'* ]]
  [[ "$output" == *'_try _clone'* ]]
  [[ "$output" == *'tee -a /root/install.log'* ]]
}
