#!/usr/bin/env bats
# Tests: the btrfs resnapshot helper and the generated latehooks (split from
# chroot-impermanence-btrfs-and-hooks.bats; shared setup in
# chroot-impermanence-helpers.bash)

load chroot-impermanence-helpers
load ../lib/text-helpers

# ── btrfs FS layer: PostTransaction resnapshot helper (issue 08, ADR 0044) ───
# The .hook file is reused verbatim (slice-agnostic); only the helper body it
# execs goes FS-conditional. btrfs deletes + re-snapshots each @<name>@blank
# from the live subvol over the top-level mount, mirroring the zfs destroy+
# snapshot. Idempotent, errors logged not aborted.

@test "btrfs resnapshot helper: written + executable + bash shebang" {
  export FILESYSTEM=btrfs
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  [ -x "$helper_script" ]
  [[ "$(head -n 1 "$helper_script")" =~ ^#!.*bash ]]
}

@test "btrfs resnapshot helper: btrfs delete + snapshot, never zfs" {
  export FILESYSTEM=btrfs
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  grep -qE "subvolume delete"     "$helper_script"
  grep -qE "subvolume snapshot -r" "$helper_script"
  ! grep -qE "^[^#]*zfs " "$helper_script"
}

@test "btrfs resnapshot helper: references every rollback subvol" {
  export FILESYSTEM=btrfs
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh" dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "@$dataset_name" "$helper_script" || { echo "missing @$dataset_name"; return 1; }
  done
}

@test "btrfs resnapshot helper: end-to-end deletes+snapshots every @blank" {
  export FILESYSTEM=btrfs
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"; : > "$log"
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
btrfs()   { printf 'btrfs %s\n' "\$*" >> "$log"; }
mount()   { :; }
umount()  { :; }
findmnt() { echo /dev/sdX; }
logger()  { :; }
source "$helper_script"
SUBSHELL
  local dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "btrfs subvolume snapshot -r .*/@$dataset_name .*/@$dataset_name@blank" "$log" \
      || { echo "no snapshot for @$dataset_name"; cat "$log"; return 1; }
  done
}

@test "btrfs resnapshot helper: idempotent when delete fails (no @blank)" {
  export FILESYSTEM=btrfs
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"; : > "$log"
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
btrfs() {
  printf 'btrfs %s\n' "\$*" >> "$log"
  [[ "\$1 \$2" == "subvolume delete" ]] && return 1
  return 0
}
mount(){ :; }; umount(){ :; }; findmnt(){ echo /dev/sdX; }; logger(){ :; }
source "$helper_script"
echo "exit=\$?" >> "$log"
SUBSHELL
  grep -qE "exit=0$" "$log"
  grep -qE "btrfs subvolume snapshot -r .*/@usrlocal@blank" "$log"
}

@test "resnapshot helper: documents v1 leak in comments" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  # Operator who reads the helper should learn that no pre-transaction
  # wipe exists (the documented v1 leak).
  grep -qE "v1 leak|pre-transaction|leak" "$helper_script"
}

# Behavioural guard: run each generated latehook with stubbed tools and check
# every rollback dataset/subvol lands at its OWN path. A rename once leaked
# into the hook's escaped guest variable (\${mp}), so every mount targeted a
# bare /new_root and the installed system booted with no /sbin/init.
_run_latehook() { # <hook-file>
  run bash -c "
    zfs() { return 0; }
    mkdir() { :; }
    mount() { echo \"mount \$*\"; }
    getarg() { echo /dev/vda2; }
    resolve_device() { echo \"\$1\"; }
    err() { echo \"err \$*\"; }
    launch_interactive_shell() { echo shell; }
    source '$1'
    run_latehook"
}

@test "zfs: the generated latehook mounts each dataset at its own path" {
  export FILESYSTEM=zfs
  impermanence_boot_hooks_write_rollback
  _run_latehook "$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rpool/ROOT/etc /new_root/etc"* ]]
  [[ "$output" == *"rpool/var/log /new_root/var/log"* ]]
  ! printf '%s\n' "$output" | grep -qE ' /new_root$'
}

@test "btrfs: the generated latehook mounts each subvol at its own path" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  _run_latehook "$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback"
  [ "$status" -eq 0 ]
  [[ "$output" == *"subvol=@etc /dev/vda2 /new_root/etc"* ]]
  ! printf '%s\n' "$output" | grep -qE ' /new_root$'
}

@test "resnapshot helper: keeps the old @blank as the Update Snapshot first" {
  # ADR 0166: the pre-update @blank is renamed to the transaction's @update-*
  # name before it would be destroyed, so Undo Last Update can restore it.
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local keep_line destroy_line
  keep_line="$(first_line_matching "$helper_script" \
    'update-snapshot.sh keep-blank')"
  destroy_line="$(first_line_matching "$helper_script" 'zfs destroy ')"
  [ -n "$keep_line" ] && [ "$keep_line" -lt "$destroy_line" ]
}
