#!/usr/bin/env bats
# Tests for the pacman hooks lib/chroot.sh writes onto the target: the ESP
# mirror (multi-ESP only) and the package-cache cleanup (every install).

setup() {
  error() { echo "ERROR: $*" >&2; exit 1; }
  info() { :; }; warn() { :; }; section() { :; }
  # shellcheck source=../../lib/chroot.sh
  source "$BATS_TEST_DIRNAME/../../lib/chroot.sh"
  MOUNT_ROOT="$BATS_TEST_TMPDIR/mnt"
  HOOKS="$MOUNT_ROOT/etc/pacman.d/hooks"
}

@test "single-ESP install: no mirror hook" {
  chroot_write_esp_mirror_hook 1
  [ ! -e "$HOOKS/95-esp-mirror.hook" ]
}

@test "the paccache cleanup hook is written on every install" {
  # It sat after the mirror writer's single-ESP early return, so most
  # installs never got it.
  chroot_write_paccache_hook
  grep -qx 'Exec = /usr/bin/paccache -rk2' "$HOOKS/90-paccache.hook"
}

@test "chroot_configure_system writes the paccache hook unconditionally" {
  awk '/^chroot_configure_system\(\) \{/, /^\}/' \
    "$BATS_TEST_DIRNAME/../../lib/chroot.sh" \
    | grep -qx '  chroot_write_paccache_hook'
}
