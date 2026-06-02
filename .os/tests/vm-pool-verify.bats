#!/usr/bin/env bats
# Tests for .os/lib/vm-pool-verify.sh — booted-VM pool/mount verifier.
#
# Strategy: the verifier queries the live system through `zpool` / `zfs`, which
# the tests stub as bash functions to simulate a healthy or faulty system. No
# real pools are touched. Assertions read the return code + stderr messages.

setup() {
  # shellcheck source=../lib/vm-pool-verify.sh
  source "$BATS_TEST_DIRNAME/../lib/vm-pool-verify.sh"
}

# Healthy-system stubs: every pool imported; every <pool>/data dataset mounted
# at /data/<pool>. Individual tests redefine these to inject a single fault.
_healthy_stubs() {
  zpool() { return 0; }                      # any queried pool is imported
  zfs() {                                     # zfs get -H -o value <prop> <ds>
    local ds="${*: -1}" prop="${*: -2:1}"
    case "$prop" in
    mounted)    echo yes ;;
    mountpoint) echo "/data/${ds%/data}" ;;  # tank0/data → /data/tank0
    esac
  }
}

@test "vm_pool_verify: passes when all pools imported and datasets mounted" {
  _healthy_stubs
  VM_VERIFY_POOLS=(rpool tank0 tank1)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0 tank1/data:/data/tank1)
  run vm_pool_verify
  [ "$status" -eq 0 ]
}

@test "vm_pool_verify: fails loudly when an expected pool is not imported" {
  _healthy_stubs
  zpool() { [[ "${*: -1}" != tank1 ]]; }   # tank1 failed to import
  VM_VERIFY_POOLS=(rpool tank0 tank1)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0)
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING POOL: tank1"* ]]
}

@test "vm_pool_verify: fails loudly when a data dataset is not mounted" {
  _healthy_stubs
  zfs() {                                    # tank1/data imported but unmounted
    local ds="${*: -1}" prop="${*: -2:1}"
    case "$prop" in
    mounted)    [[ "$ds" == tank1/data ]] && echo no || echo yes ;;
    mountpoint) echo "/data/${ds%/data}" ;;
    esac
  }
  VM_VERIFY_POOLS=(tank0 tank1)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0 tank1/data:/data/tank1)
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT MOUNTED: tank1/data at /data/tank1"* ]]
}

@test "vm_pool_verify: fails when a dataset is mounted at the wrong path" {
  _healthy_stubs
  zfs() {                                    # tank0/data mounted at /mnt/wrong
    local ds="${*: -1}" prop="${*: -2:1}"
    case "$prop" in
    mounted)    echo yes ;;
    mountpoint) [[ "$ds" == tank0/data ]] && echo /mnt/wrong \
                  || echo "/data/${ds%/data}" ;;
    esac
  }
  VM_VERIFY_POOLS=(tank0)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0)
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT MOUNTED: tank0/data at /data/tank0"* ]]
}
