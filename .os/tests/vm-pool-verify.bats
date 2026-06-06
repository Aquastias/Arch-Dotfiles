#!/usr/bin/env bats
# Tests for .os/lib/vm-pool-verify.sh — booted-VM pool/mount verifier.
#
# Strategy: the verifier queries the live system through `zpool` / `zfs`, which
# the tests stub as bash functions to simulate a healthy or faulty system. No
# real pools are touched. Assertions read the return code + stderr messages.

setup() {
  # shellcheck source=vm/lib/vm-pool-verify.sh
  source "$BATS_TEST_DIRNAME/vm/lib/vm-pool-verify.sh"
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

@test "vm_pool_vdevs_stable: passes when every leaf vdev is a by-id path" {
  zpool() {                                  # `zpool status -P <pool>`
    cat <<'OUT'
  pool: tank0
 state: ONLINE
	NAME                                  STATE
	tank0                                 ONLINE
	  /dev/disk/by-id/ata-DISK_B-part1    ONLINE
OUT
  }
  VM_VERIFY_POOLS=(tank0)
  run vm_pool_vdevs_stable
  [ "$status" -eq 0 ]
}

@test "vm_pool_vdevs_stable: fails loudly on a bare /dev/sdX leaf vdev" {
  zpool() {                                  # the multi-disk reorder bug
    cat <<'OUT'
  pool: tank0
	NAME          STATE
	tank0         ONLINE
	  /dev/sdb1   ONLINE
OUT
  }
  VM_VERIFY_POOLS=(tank0)
  run vm_pool_vdevs_stable
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNSTABLE VDEV"* ]]
  [[ "$output" == *"/dev/sdb1"* ]]
}

@test "vm_pool_verify: by-id check off by default (legacy single-disk path)" {
  _healthy_stubs                             # zpool stub returns 0, no paths
  VM_VERIFY_POOLS=(rpool)
  VM_VERIFY_MOUNTS=()
  run vm_pool_verify
  [ "$status" -eq 0 ]
}

@test "vm_pool_verify: VM_VERIFY_BYID=true folds the unstable-vdev failure in" {
  zpool() {
    case "$1" in
    list) return 0 ;;                        # pool imported
    status) printf '\t  /dev/sdb1   ONLINE\n' ;;
    esac
  }
  zfs() { echo yes; }                        # mounted check is satisfied
  VM_VERIFY_BYID=true
  VM_VERIFY_POOLS=(tank0)
  VM_VERIFY_MOUNTS=()
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"UNSTABLE VDEV"* ]]
}

@test "vm_pool_verify: passes when a mount is owned and writable by its user" {
  _healthy_stubs
  stat() { echo alice; }                       # `stat -c %U <mp>` → owner
  su() { return 0; }                            # `su - alice -c 'test -w <mp>'`
  VM_VERIFY_POOLS=(tank0)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0)
  VM_VERIFY_OWNED=(/data/tank0:alice)
  run vm_pool_verify
  [ "$status" -eq 0 ]
}

@test "vm_pool_verify: fails loudly when a mount is owned by the wrong user" {
  _healthy_stubs
  stat() { echo root; }                         # left root-owned
  su() { return 0; }
  VM_VERIFY_POOLS=(tank0)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0)
  VM_VERIFY_OWNED=(/data/tank0:alice)
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT OWNED: /data/tank0"* ]]
}

@test "vm_pool_verify: fails loudly when the owner cannot write the mount" {
  _healthy_stubs
  stat() { echo alice; }                        # owned, but...
  su() { return 1; }                            # test -w fails
  VM_VERIFY_POOLS=(tank0)
  VM_VERIFY_MOUNTS=(tank0/data:/data/tank0)
  VM_VERIFY_OWNED=(/data/tank0:alice)
  run vm_pool_verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT WRITABLE: /data/tank0"* ]]
}

@test "vm_pool_verify: owned check is off by default (legacy callers)" {
  _healthy_stubs
  VM_VERIFY_POOLS=(rpool)
  VM_VERIFY_MOUNTS=()
  unset VM_VERIFY_OWNED
  run vm_pool_verify
  [ "$status" -eq 0 ]
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
