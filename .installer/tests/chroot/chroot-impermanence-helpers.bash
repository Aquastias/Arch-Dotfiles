# chroot-impermanence-helpers.bash — shared setup for the chroot-impermanence-*.bats parts
# Tests for .installer/lib/chroot/impermanence.sh — Chroot Configuration Module.
#
# Strategy: stub zfs/zpool/systemctl as bash fns that append argv to $CALLS,
# then source impermanence.sh and call impermanence_apply. Assertions read
# $CALLS plus files generated under $FAKEROOT.

setup() {
  TEST_DIR="$(mktemp -d)"
  CALLS="$TEST_DIR/calls.log"
  FAKEROOT="$TEST_DIR/root"
  mkdir -p "$FAKEROOT"
  export CALLS FAKEROOT

  info()    { :; }
  warn()    { :; }
  error()   { echo "ERROR: $*" >&2; exit 1; }
  section() { :; }
  export -f info warn error section

  zfs() {
    printf 'zfs %s\n' "$*" >> "$CALLS"
    [[ "$1" == "list" ]] && return 1
    return 0
  }
  zpool()   { printf 'zpool %s\n'   "$*" >> "$CALLS"; }
  pacman()  { printf 'pacman %s\n'  "$*" >> "$CALLS"; }
  systemctl() { printf 'systemctl %s\n' "$*" >> "$CALLS"; }
  systemd-machine-id-setup() { printf 'machine-id-setup %s\n' "$*" >> "$CALLS"; }
  # btrfs FS-layer stubs (issue 08): keep the btrfs @blank snapshot step off the
  # real mount/btrfs binaries so a FILESYSTEM=btrfs full apply runs in the harness.
  btrfs()   { printf 'btrfs %s\n'   "$*" >> "$CALLS"; }
  mount()   { printf 'mount %s\n'   "$*" >> "$CALLS"; }
  umount()  { printf 'umount %s\n'  "$*" >> "$CALLS"; }
  findmnt() { echo /dev/sdX; }
  export -f zfs zpool pacman systemctl systemd-machine-id-setup \
    btrfs mount umount findmnt

  export IMPERMANENCE_ENABLED=false
  export IMPERMANENCE_DATASET=rpool/persist
  export IMPERMANENCE_MOUNT=/persist
  export RPOOL=rpool
  export ROOT="$FAKEROOT"
  PERSIST_DIRECTORIES=()
  PERSIST_FILES=()
  export PERSIST_DIRECTORIES PERSIST_FILES

  # shellcheck source=../../lib/chroot/impermanence.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot/impermanence.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# byte_offset <text> <file> — the 0-based byte offset of <text>'s first
# occurrence in <file>; nothing when absent.
byte_offset() {
  NEEDLE="$1" LC_ALL=C awk 'BEGIN { RS = "^$" }
    { at = index($0, ENVIRON["NEEDLE"]); if (at) print at - 1 }' "$2"
}

# Convenience: enable + run, return zfs/zpool call log.
run_enabled() {
  IMPERMANENCE_ENABLED=true
  impermanence_apply
}

# Helper: seed source content under FAKEROOT for a curated path.
seed_curated() {
  local path="$1" content="${2:-content}"
  mkdir -p "$FAKEROOT${path%/*}"
  if [[ "$path" == */ ]] || [[ -d "$FAKEROOT$path" ]]; then
    mkdir -p "$FAKEROOT$path"
    printf '%s' "$content" > "$FAKEROOT$path/marker"
  else
    printf '%s' "$content" > "$FAKEROOT$path"
  fi
}
# Services enabled via `systemctl enable` land in /etc/systemd/system/*.wants;
# under impermanence /etc rolls back and the persist bind is too late for PID1's
# boot transaction, so they never autostart. The step mirrors them onto the
# never-rolled-back /usr/lib tree ([[impermanence-service-enable]]).
_seed_enablements() {
  local sys="$FAKEROOT/usr/lib/systemd/system"
  local etc="$FAKEROOT/etc/systemd/system"
  mkdir -p "$sys" "$etc/multi-user.target.wants" "$etc/graphical.target.wants"
  : > "$sys/NetworkManager.service"      # packaged units the enables point at
  : > "$sys/sshd.service"
  : > "$sys/sddm.service"
  ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "$etc/multi-user.target.wants/NetworkManager.service"
  ln -sf /usr/lib/systemd/system/sshd.service \
    "$etc/multi-user.target.wants/sshd.service"
  ln -sf /usr/lib/systemd/system/sddm.service "$etc/display-manager.service"
  # operator unit that lives ONLY under /etc — must be skipped (would dangle)
  : > "$etc/custom.service"
  ln -sf /etc/systemd/system/custom.service \
    "$etc/multi-user.target.wants/custom.service"
}

