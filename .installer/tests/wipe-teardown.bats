#!/usr/bin/env bats
# Tests for the wipe's pre-wipe teardown (lib/wipe/execute.sh): which imported
# ZFS pools and LVM physical volumes sit on the disk being wiped.
#
# install.sh hands the wipe /dev/disk/by-id paths, while zpool and pvs report
# kernel nodes — so membership is decided by device identity (resolved path or
# parent disk), never a substring match that tied sda to sdab.

setup() {
  # shellcheck source=../02-wipe.sh
  source "$BATS_TEST_DIRNAME/../02-wipe.sh"
  info() { :; }; warn() { :; }; section() { :; }
  command_exists() { return 0; }
  DESTROYED="$BATS_TEST_TMPDIR/destroyed"
  : >"$DESTROYED"
  # Two disks: the by-id target resolves to sda; sdab is an unrelated disk.
  readlink() {
    case "$2" in
    /dev/disk/by-id/ata-TARGET) echo /dev/sda ;;
    *) echo "$2" ;;
    esac
  }
  lsblk() {   # lsblk -no PKNAME <part>
    case "${@: -1}" in
    /dev/sda2) echo sda ;; /dev/sdab1) echo sdab ;;
    /dev/nvme0n10p1) echo nvme0n10 ;; *) echo "" ;;
    esac
  }
}

# _pools <name:vdev>... — stub zpool with imported pools and their vdevs.
_pools() {
  POOL_SPEC="$*"
  zpool() {
    local spec
    case "$1" in
    list) for spec in $POOL_SPEC; do echo "${spec%%:*}"; done ;;
    status)
      for spec in $POOL_SPEC; do
        [[ "${spec%%:*}" == "${@: -1}" ]] && echo "	  ${spec#*:}  ONLINE"
      done ;;
    destroy) echo "${@: -1}" >>"$DESTROYED" ;;
    import) return 1 ;;
    esac
  }
}

@test "zfs teardown destroys a pool on the by-id target's partition" {
  _pools "rpool:/dev/sda2"
  wipe_teardown_zfs /dev/disk/by-id/ata-TARGET
  grep -qx rpool "$DESTROYED"
}

@test "zfs teardown leaves a pool on sdab alone when wiping sda" {
  _pools "tank:/dev/sdab1"
  wipe_teardown_zfs /dev/sda
  [ ! -s "$DESTROYED" ]
}

@test "zfs teardown leaves nvme0n10 alone when wiping nvme0n1" {
  _pools "tank:/dev/nvme0n10p1"
  wipe_teardown_zfs /dev/nvme0n1
  [ ! -s "$DESTROYED" ]
}

@test "lvm teardown removes a PV on the by-id target, not one on sdab" {
  pvs() {
    case "$*" in
    *pv_name*) printf '  /dev/sda2\n  /dev/sdab1\n' ;;
    *vg_name*) local device="${*: -1}"; echo "  vg_${device##*/}" ;;
    esac
  }
  vgremove() { echo "vgremove ${@: -1}" >>"$DESTROYED"; }
  pvremove() { echo "pvremove ${@: -1}" >>"$DESTROYED"; }
  wipe_teardown_lvm /dev/disk/by-id/ata-TARGET
  grep -qx "pvremove /dev/sda2" "$DESTROYED"
  ! grep -q sdab "$DESTROYED"
}
