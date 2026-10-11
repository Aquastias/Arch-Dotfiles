#!/usr/bin/env bats
# Tests: btrfs layer and pacman hooks (split from chroot-impermanence.bats;
# shared setup in chroot-impermanence-helpers.bash)

load chroot-impermanence-helpers


# ── btrfs FS layer: btrfs-rollback initramfs hook (issue 08, ADR 0044) ───────
# Mirrors the zfs-rollback hook's contract: a boot-time per-path rollback that
# fails closed to an emergency shell on a missing @blank. btrfs differs in
# mechanics — it mounts the top-level (subvolid=5), `subvolume delete`s each
# rollback subvol and recreates it from its read-only @<name>@blank.

@test "btrfs: writes install hook /usr/lib/initcpio/install/btrfs-rollback" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  local hook_file="$FAKEROOT/usr/lib/initcpio/install/btrfs-rollback"
  [ -f "$hook_file" ]
  grep -qE "^build\\(\\)" "$hook_file"
  grep -qE "add_runscript" "$hook_file"
}

@test "btrfs: does NOT write the zfs-rollback hook" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  [ ! -f "$FAKEROOT/usr/lib/initcpio/install/zfs-rollback" ]
  [ ! -f "$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback" ]
}

@test "btrfs: runtime hook recreates each rollback subvol from @blank" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback" dataset_name
  [ -f "$hook_file" ]
  grep -qE "subvolume delete"   "$hook_file"
  grep -qE "subvolume snapshot" "$hook_file"
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "@$dataset_name" "$hook_file" || { echo "missing @$dataset_name in hook"; return 1; }
  done
}

@test "btrfs: runtime hook fails closed on a missing @blank" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback"
  grep -qE "launch_interactive_shell|emergency" "$hook_file"
  grep -qE "@blank" "$hook_file"
}

@test "btrfs: runtime hook mounts the btrfs top-level (subvolid=5)" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback"
  grep -qE "subvolid=5" "$hook_file"
}

# After the rollback recreates @etc from @blank, the subvols must be mounted
# under the real root (/new_root) in a run_latehook — BEFORE switch_root — so
# PID1 reads a populated /etc (machine-id/hostname/localtime). Left to fstab,
# @etc mounts only at local-fs.target, after PID1 already read the empty @/etc
# mountpoint → systemd-firstboot Initial Setup runs and blocks boot. Mirrors
# the archzfs hook mounting the dataset hierarchy in the initramfs.
@test "btrfs: runtime hook mounts rollback subvols under /new_root (latehook)" {
  export FILESYSTEM=btrfs
  impermanence_boot_hooks_write_rollback
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback" pair
  grep -qE "^run_latehook\(\)" "$hook_file"
  grep -q "/new_root" "$hook_file"
  for pair in @etc:/etc @opt:/opt @srv:/srv @usrlocal:/usr/local; do
    grep -qF "$pair" "$hook_file" || { echo "missing early-mount pair $pair"; return 1; }
  done
}

@test "zfs: still writes the zfs-rollback hook (default FILESYSTEM)" {
  unset FILESYSTEM
  impermanence_boot_hooks_write_rollback
  [ -f "$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback" ]
  [ ! -f "$FAKEROOT/usr/lib/initcpio/hooks/btrfs-rollback" ]
}


# ── slice 2 cycle 1 (tracer): one extension dir → .mount under /usr/lib ─────

@test "extension dir: writes .mount unit under /usr/lib/systemd/system" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-wireguard.mount"
  [ -f "$unit_file" ]
  grep -qE "^What=/persist/etc/wireguard$" "$unit_file"
  grep -qE "^Where=/etc/wireguard$" "$unit_file"
}

@test "extension dir: writes /persist tmpfiles snippet for extensions" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  run_enabled
  local tmpfiles_file="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$tmpfiles_file" ]
  grep -qE "^d /etc/wireguard " "$tmpfiles_file"
}

@test "extension file: writes f entry and .mount unit" {
  PERSIST_FILES=("/etc/foo.conf")
  run_enabled
  local tmpfiles_config="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  local escaped_path unit
  escaped_path="$(systemd-escape --path /etc/foo.conf)"
  unit="$FAKEROOT/usr/lib/systemd/system/$escaped_path.mount"
  grep -qE "^f /etc/foo\.conf " "$tmpfiles_config"
  [ -f "$unit" ]
  grep -qE "^Where=/etc/foo\.conf$" "$unit"
}

@test "extension dir does NOT appear as f entry in tmpfiles" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  PERSIST_FILES=()
  run_enabled
  local tmpfiles_config="$FAKEROOT/persist/etc/tmpfiles.d/impermanence-extensions.conf"
  if grep -qE "^f /etc/wireguard " "$tmpfiles_config"; then return 1; fi
}

@test "extension: .wants symlink under /usr/lib/.../local-fs.target.wants" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  PERSIST_FILES=("/etc/foo.conf")
  run_enabled
  local wants_directory="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants"
  local esc1 esc2
  esc1="$(systemd-escape --path /etc/wireguard)"
  esc2="$(systemd-escape --path /etc/foo.conf)"
  [ -L "$wants_directory/$esc1.mount" ]
  [ -L "$wants_directory/$esc2.mount" ]
  [ "$(readlink "$wants_directory/$esc1.mount")" = "../$esc1.mount" ]
}

@test "extension: moves dir content; source absent, dest present" {
  PERSIST_DIRECTORIES=("/etc/wireguard")
  mkdir -p "$FAKEROOT/etc/wireguard"
  printf 'k' > "$FAKEROOT/etc/wireguard/wg0.conf"
  run_enabled
  [ ! -e "$FAKEROOT/etc/wireguard" ]
  [ -f "$FAKEROOT/persist/etc/wireguard/wg0.conf" ]
}

@test "extension: moves file content; source absent, dest present" {
  PERSIST_FILES=("/etc/foo.conf")
  mkdir -p "$FAKEROOT/etc"
  printf 'bar' > "$FAKEROOT/etc/foo.conf"
  run_enabled
  [ ! -e "$FAKEROOT/etc/foo.conf" ]
  [ -f "$FAKEROOT/persist/etc/foo.conf" ]
  [ "$(cat "$FAKEROOT/persist/etc/foo.conf")" = "bar" ]
}

@test "extension: missing source is skipped (no error)" {
  PERSIST_DIRECTORIES=("/etc/nonexistent")
  IMPERMANENCE_ENABLED=true run impermanence_apply
  [ "$status" -eq 0 ]
}

@test "extension: mv occurs before zfs snapshot" {
  mv() { printf 'mv %s\n' "$*" >> "$CALLS"; command mv "$@"; }
  export -f mv
  PERSIST_FILES=("/etc/foo.conf")
  mkdir -p "$FAKEROOT/etc"
  printf 'x' > "$FAKEROOT/etc/foo.conf"
  run_enabled
  local last_mv first_snap
  last_mv="$(awk '/^mv .*\/etc\/foo.conf / { last = NR } END { print last }' "$CALLS")"
  first_snap="$(awk '/^zfs snapshot / { print NR; exit }' "$CALLS")"
  [ -n "$last_mv" ] && [ -n "$first_snap" ]
  [ "$last_mv" -lt "$first_snap" ]
}


# ── slice 3 cycle 1 (tracer): enabled writes pacman hook file ───────────────

@test "resnapshot hook: enabled writes pacman hook file" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  [ -f "$hook_file" ]
}

@test "resnapshot hook: [Trigger] Type=Package" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Type ?= ?Package$" "$hook_file"
}

@test "resnapshot hook: [Trigger] Operation Install|Upgrade|Remove" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Operation ?= ?Install$" "$hook_file"
  grep -qE "^Operation ?= ?Upgrade$" "$hook_file"
  grep -qE "^Operation ?= ?Remove$"  "$hook_file"
}

@test "resnapshot hook: [Trigger] Target=*" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE '^Target ?= ?\*$' "$hook_file"
}

@test "resnapshot hook: [Action] When=PostTransaction" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^When ?= ?PostTransaction$" "$hook_file"
}

@test "resnapshot hook: [Action] Exec=/usr/lib/impermanence/resnapshot.sh" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Exec ?= ?/usr/lib/impermanence/resnapshot\.sh$" "$hook_file"
}

@test "resnapshot hook: [Action] Description present" {
  run_enabled
  local hook_file="$FAKEROOT/etc/pacman.d/hooks/zz-impermanence-resnapshot.hook"
  grep -qE "^Description ?= ?" "$hook_file"
}

@test "resnapshot helper: written at /usr/lib/impermanence/resnapshot.sh" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/impermanence/resnapshot.sh" ]
}

@test "resnapshot helper: is executable" {
  run_enabled
  [ -x "$FAKEROOT/usr/lib/impermanence/resnapshot.sh" ]
}

@test "resnapshot helper: starts with bash shebang" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  [[ "$(awk 'NR == 1 { print; exit }' "$helper_script")" =~ ^#!.*bash ]]
}

@test "resnapshot helper: references every Rollback Dataset" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh" dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "rpool/ROOT/$dataset_name" "$helper_script" \
      || { echo "missing rpool/ROOT/$dataset_name in helper"; return 1; }
  done
}

@test "resnapshot helper: contains zfs destroy and zfs snapshot @blank" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  grep -qE "zfs destroy .*@blank" "$helper_script"
  grep -qE "zfs snapshot .*@blank" "$helper_script"
}

@test "resnapshot helper: destroy precedes snapshot in script" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local destroy_line snapshot_line
  destroy_line="$(awk '/zfs destroy / { print NR; exit }' "$helper_script")"
  snapshot_line="$(awk '/zfs snapshot / { print NR; exit }' "$helper_script")"
  [ -n "$destroy_line" ] && [ -n "$snapshot_line" ]
  [ "$destroy_line" -lt "$snapshot_line" ]
}

@test "resnapshot helper: end-to-end re-snapshots every dataset" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # Source the helper in a fresh bash subshell with our own zfs/logger
  # stubs to capture invocations. The setup()-exported zfs function is
  # explicitly unset so it does not shadow the stub.
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs()    { printf 'zfs %s\n'    "\$*" >> "$log"; }
logger() { :; }
source "$helper_script"
SUBSHELL
  local dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "zfs destroy rpool/ROOT/$dataset_name@blank" "$log" \
      || { echo "no destroy for $dataset_name"; cat "$log"; return 1; }
    grep -qE "zfs snapshot rpool/ROOT/$dataset_name@blank" "$log" \
      || { echo "no snapshot for $dataset_name"; cat "$log"; return 1; }
  done
}

@test "resnapshot helper: idempotent when destroy fails (no @blank)" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # destroy returns nonzero (no such snapshot); helper must still snapshot.
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs() {
  printf 'zfs %s\n' "\$*" >> "$log"
  if [[ "\$1" == "destroy" ]]; then return 1; fi
  return 0
}
logger() { :; }
source "$helper_script"
status=\$?
echo "exit=\$status" >> "$log"
SUBSHELL
  grep -qE "exit=0$" "$log"
  local dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "zfs snapshot rpool/ROOT/$dataset_name@blank" "$log" \
      || { echo "no snapshot for $dataset_name"; cat "$log"; return 1; }
  done
}

@test "resnapshot helper: idempotent when snapshot fails (continues)" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  # Even if snapshot of first dataset fails, remaining are attempted and
  # helper exits 0 (errors are logged, not aborted).
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs() {
  printf 'zfs %s\n' "\$*" >> "$log"
  if [[ "\$1" == "snapshot" && "\$2" == *"/etc@blank" ]]; then return 1; fi
  return 0
}
logger() { :; }
source "$helper_script"
echo "exit=\$?" >> "$log"
SUBSHELL
  grep -qE "exit=0$" "$log"
  grep -qE "zfs snapshot rpool/ROOT/usrlocal@blank" "$log"
}

@test "resnapshot helper: invokes logger with -t impermanence" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  grep -qE "logger -t impermanence" "$helper_script"
}

@test "resnapshot helper: logger called at runtime per dataset" {
  run_enabled
  local helper_script="$FAKEROOT/usr/lib/impermanence/resnapshot.sh"
  local log="$TEST_DIR/helper-calls.log"
  : > "$log"
  HELPER_LOG="$log" bash <<SUBSHELL
unset -f zfs logger 2>/dev/null
zfs()    { printf 'zfs %s\n'    "\$*" >> "$log"; }
logger() { printf 'logger %s\n' "\$*" >> "$log"; }
source "$helper_script"
SUBSHELL
  # at least one logger invocation tagged impermanence
  grep -qE "^logger .*-t impermanence" "$log"
}


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
  [[ "$(awk 'NR == 1 { print; exit }' "$helper_script")" =~ ^#!.*bash ]]
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
