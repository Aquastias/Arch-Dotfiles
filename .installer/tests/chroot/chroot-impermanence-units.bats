#!/usr/bin/env bats
# Tests: mount units, tmpfiles, manifest (split from chroot-impermanence.bats;
# shared setup in chroot-impermanence-helpers.bash)

load chroot-impermanence-helpers


# ── cycle 1: tracer — disabled is a no-op ────────────────────────────────────

@test "disabled: impermanence_apply exits 0" {
  IMPERMANENCE_ENABLED=false
  run impermanence_apply
  [ "$status" -eq 0 ]
}

@test "disabled: no zfs/zpool calls" {
  IMPERMANENCE_ENABLED=false
  impermanence_apply
  [ ! -s "$CALLS" ]
}


# ── cycle 2+3: datasets are NOT created here — done EARLY in the layout phase ─
# Both the Persist Dataset and the Rollback Datasets are created before pacstrap
# by impermanence_common_create_persist_dataset + impermanence_common_create_rollback_datasets (see
# tests/impermanence-common.bats). Creating them in the Chroot Module is too
# late: rollback datasets would miss pacstrap's content + the zfs-list.cache,
# and the Persist Dataset would mount too late for the curated binds to restore
# /etc state before dbus.

@test "enabled: does NOT create the Persist Dataset (done early in layout)" {
  run_enabled
  ! grep -qE "^zfs create .* rpool/persist\$" "$CALLS"
}

@test "enabled: does NOT create the Rollback Datasets (done early in layout)" {
  run_enabled
  ! grep -qE "^zfs create .* rpool/ROOT/(etc|opt|root|srv|usrlocal)\$" "$CALLS"
}


# ── cycle 4: sorted defaults.manifest ────────────────────────────────────────

@test "enabled: writes /usr/lib/impermanence/defaults.manifest" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/impermanence/defaults.manifest" ]
}

@test "enabled: manifest is sorted union of CURATED_FILES + CURATED_DIRS" {
  run_enabled
  local manifest_file="$FAKEROOT/usr/lib/impermanence/defaults.manifest"
  expected="$(printf '%s\n' \
    "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}" | sort)"
  [ "$(cat "$manifest_file")" = "$expected" ]
}


# ── cycle 5: curated-file .mount unit shape ──────────────────────────────────

@test "enabled: writes .mount unit for /etc/machine-id" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system"
  [ -f "$unit_file/etc-machine\\x2did.mount" ]
}

@test "enabled: file .mount has What=/persist/etc/machine-id" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-machine\\x2did.mount"
  grep -qE "^What=/persist/etc/machine-id$" "$unit_file"
}

# Where= ↔ escaped-name correctness (the persist-<esc>.mount class) is now
# asserted for real, across every curated entry, by tests/chroot/
# mount-unit-validate.bats via `systemd-analyze verify` — no raw grep here.

@test "enabled: file .mount has Type=none and Options=bind" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-machine\\x2did.mount"
  grep -qE "^Type=none$" "$unit_file"
  grep -qE "^Options=bind$" "$unit_file"
}

@test "enabled: a .mount unit exists for every CURATED_FILES entry" {
  run_enabled
  local unit_directory="$FAKEROOT/usr/lib/systemd/system" curated_file escaped_path
  for curated_file in "${CURATED_FILES[@]}"; do
    escaped_path="$(systemd-escape --path "$curated_file")"
    [ -f "$unit_directory/$escaped_path.mount" ] || { echo "missing $curated_file → $escaped_path.mount"; return 1; }
  done
}


# ── cycle 6: dir .mount units, ordering, .wants symlinks ─────────────────────

@test "enabled: writes .mount unit for /etc/ssh (dir)" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-ssh.mount"
  [ -f "$unit_file" ]
  grep -qE "^What=/persist/etc/ssh$" "$unit_file"
  # Where= correctness now validated for real (mount-unit-validate.bats).
}

@test "enabled: a .mount unit exists for every CURATED_DIRS entry" {
  run_enabled
  local unit_directory="$FAKEROOT/usr/lib/systemd/system" curated_directory escaped_path
  for curated_directory in "${CURATED_DIRS[@]}"; do
    escaped_path="$(systemd-escape --path "$curated_directory")"
    [ -f "$unit_directory/$escaped_path.mount" ] || { echo "missing $curated_directory → $escaped_path.mount"; return 1; }
  done
}

@test "enabled: every curated .mount has required ordering directives" {
  run_enabled
  local unit_directory="$FAKEROOT/usr/lib/systemd/system" curated_path escaped_path unit
  for curated_path in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    escaped_path="$(systemd-escape --path "$curated_path")"
    unit="$unit_directory/$escaped_path.mount"
    # After=zfs-mount.service (NOT tmpfiles-setup, which is After=local-fs.target
    # → would form an ordering cycle with our Before=local-fs.target).
    grep -qE "^After=zfs-mount\.service$" "$unit" \
      || { echo "$curated_path missing After=zfs-mount.service"; return 1; }
    ! grep -qE "^After=systemd-tmpfiles-setup" "$unit" \
      || { echo "$curated_path must NOT order After=tmpfiles (cycle)"; return 1; }
    grep -qE "^Before=local-fs\.target$" "$unit" \
      || { echo "$curated_path missing Before"; return 1; }
    grep -qE "^RequiredBy=local-fs\.target$" "$unit" \
      || { echo "$curated_path missing RequiredBy"; return 1; }
  done
}

@test "enabled: .wants symlink under local-fs.target.wants for each unit" {
  run_enabled
  local wants_directory="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants" curated_path escaped_path
  for curated_path in "${CURATED_FILES[@]}" "${CURATED_DIRS[@]}"; do
    escaped_path="$(systemd-escape --path "$curated_path")"
    [ -L "$wants_directory/$escaped_path.mount" ] \
      || { echo "missing wants symlink for $curated_path"; return 1; }
  done
}

@test "enabled: wants symlinks point to ../<unit>.mount (relative)" {
  run_enabled
  local wants_directory="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants"
  local escaped_path target
  escaped_path="$(systemd-escape --path /etc/ssh)"
  target="$(readlink "$wants_directory/$escaped_path.mount")"
  [ "$target" = "../$escaped_path.mount" ]
}


# ── cycle 7: tmpfiles snippet for curated paths ──────────────────────────────

@test "enabled: writes /usr/lib/tmpfiles.d/impermanence-curated.conf" {
  run_enabled
  [ -f "$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" ]
}

@test "enabled: tmpfiles snippet has a d entry for each CURATED_DIRS" {
  run_enabled
  local tmpfiles_file="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" curated_directory
  for curated_directory in "${CURATED_DIRS[@]}"; do
    grep -qE "^d $curated_directory " "$tmpfiles_file" || { echo "missing d $curated_directory"; return 1; }
  done
}

@test "enabled: tmpfiles snippet has an f entry for each CURATED_FILES" {
  run_enabled
  local tmpfiles_file="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-curated.conf" file
  for file in "${CURATED_FILES[@]}"; do
    grep -qE "^f $file " "$tmpfiles_file" || { echo "missing f $file"; return 1; }
  done
}


# ── cycle 8: bootstrap mount pair ────────────────────────────────────────────

@test "enabled: writes /usr/lib/tmpfiles.d/impermanence-bootstrap.conf" {
  run_enabled
  local tmpfiles_file="$FAKEROOT/usr/lib/tmpfiles.d/impermanence-bootstrap.conf"
  [ -f "$tmpfiles_file" ]
  grep -qE "^d /etc/systemd/system " "$tmpfiles_file"
  grep -qE "^d /etc/tmpfiles.d " "$tmpfiles_file"
}

@test "enabled: bootstrap .mount unit exists for /etc/systemd/system" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-systemd-system.mount"
  [ -f "$unit_file" ]
  grep -qE "^What=/persist/etc/systemd/system$" "$unit_file"
  grep -qE "^Where=/etc/systemd/system$" "$unit_file"
}

@test "enabled: bootstrap .mount unit exists for /etc/tmpfiles.d" {
  run_enabled
  local unit_file="$FAKEROOT/usr/lib/systemd/system/etc-tmpfiles.d.mount"
  [ -f "$unit_file" ]
  grep -qE "^What=/persist/etc/tmpfiles\.d$" "$unit_file"
  grep -qE "^Where=/etc/tmpfiles\.d$" "$unit_file"
}

@test "enabled: bootstrap STAGES /etc/systemd/system content onto /persist" {
  # The bind would otherwise cover /etc/systemd/system with an empty dir,
  # hiding install-time enablements (e.g. a sops-runtime symlink) at boot.
  mkdir -p "$FAKEROOT/etc/systemd/system/sysinit.target.wants"
  ln -s /usr/lib/systemd/system/sops-runtime.service \
    "$FAKEROOT/etc/systemd/system/sysinit.target.wants/sops-runtime.service"
  run_enabled
  [ -L "$FAKEROOT/persist/etc/systemd/system/sysinit.target.wants/sops-runtime.service" ]
  # COPY, not move — @blank keeps a fallback copy.
  [ -L "$FAKEROOT/etc/systemd/system/sysinit.target.wants/sops-runtime.service" ]
}

@test "enabled: bootstrap units have .wants symlinks" {
  run_enabled
  local wants_directory="$FAKEROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ -L "$wants_directory/etc-systemd-system.mount" ]
  [ -L "$wants_directory/etc-tmpfiles.d.mount" ]
}


# ── cycle 9: move (not copy) curated paths → /persist ────────────────────────

@test "enabled: COPIES curated file content; source KEPT (frozen in @blank)" {
  # Early-read files (machine-id, …) must stay in /etc so @blank captures real
  # values — they can't be bind-restored before PID 1 reads them.
  # A VALID 32-hex id must be kept verbatim (the validator only regenerates an
  # empty/uninitialized one), then copied to /persist.
  seed_curated /etc/machine-id "0123456789abcdef0123456789abcdef"
  run_enabled
  [ -f "$FAKEROOT/etc/machine-id" ]
  [ "$(cat "$FAKEROOT/etc/machine-id")" = "0123456789abcdef0123456789abcdef" ]
  [ -f "$FAKEROOT/persist/etc/machine-id" ]
  [ "$(cat "$FAKEROOT/persist/etc/machine-id")" = \
    "0123456789abcdef0123456789abcdef" ]
}

@test "enabled: initialises a real machine-id before @blank" {
  : > "$CALLS"
  run_enabled
  # machine-id setup must run, and must precede the @blank snapshots
  grep -qE "^machine-id-setup " "$CALLS"
  local mid_line snap_line
  mid_line="$(awk '/^machine-id-setup / { print NR; exit }' "$CALLS")"
  snap_line="$(awk '/^zfs snapshot .*@blank/ { print NR; exit }' "$CALLS")"
  [ "$mid_line" -lt "$snap_line" ]
}

@test "enabled: moves curated dir content; source absent, dest present" {
  mkdir -p "$FAKEROOT/etc/ssh"
  printf 'hostkey' > "$FAKEROOT/etc/ssh/ssh_host_ed25519_key"
  run_enabled
  [ ! -e "$FAKEROOT/etc/ssh" ]
  [ -d "$FAKEROOT/persist/etc/ssh" ]
  [ -f "$FAKEROOT/persist/etc/ssh/ssh_host_ed25519_key" ]
}

@test "enabled: missing curated source is skipped (no error)" {
  IMPERMANENCE_ENABLED=true run impermanence_apply
  [ "$status" -eq 0 ]
}


# ── cycle 10: @blank snapshots on every Rollback Dataset ─────────────────────

@test "enabled: zfs snapshot ds@blank for every Rollback Dataset" {
  run_enabled
  local dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "^zfs snapshot rpool/ROOT/$dataset_name@blank$" "$CALLS" \
      || { echo "missing snapshot for rpool/ROOT/$dataset_name"; return 1; }
  done
}

@test "enabled: @blank snapshot taken AFTER move (post-move call order)" {
  seed_curated /etc/machine-id "secret"
  run_enabled
  # No way to assert ordering between mv and zfs from $CALLS alone (mv isn't
  # logged), but we can assert dest exists at snapshot time by checking the
  # snapshot line appears in $CALLS at all (the move ran before it because
  # apply orders them).
  grep -qE "^zfs snapshot rpool/ROOT/etc@blank$" "$CALLS"
  [ -f "$FAKEROOT/persist/etc/machine-id" ]
}


# ── R1: info log when curated source missing ─────────────────────────────────

@test "enabled: info log emitted for each missing curated source" {
  local log="$TEST_DIR/info.log"
  info() { printf '%s\n' "$*" >> "$log"; }
  export -f info
  run_enabled
  [ -f "$log" ]
  grep -qE "skip.*missing.*machine-id" "$log"
}


# ── R2: rigorous post-move snapshot ordering ─────────────────────────────────

@test "enabled: dir staging (mv) occurs before every @blank snapshot" {
  # Curated DIRS are moved onto the Persist Dataset; that must finish before the
  # @blank snapshots so the snapshot is blank of them. (Curated FILES are copied,
  # not moved — see the machine-id tests.)
  mv() { printf 'mv %s\n' "$*" >> "$CALLS"; command mv "$@"; }
  export -f mv
  mkdir -p "$FAKEROOT/etc/ssh"
  printf 'k' > "$FAKEROOT/etc/ssh/key"
  run_enabled
  local last_mv first_snap
  last_mv="$(awk '/^mv / { last = NR } END { print last }' "$CALLS")"
  first_snap="$(awk '/^zfs snapshot / { print NR; exit }' "$CALLS")"
  [ -n "$last_mv" ] && [ -n "$first_snap" ]
  [ "$last_mv" -lt "$first_snap" ]
}


# ── R3: idempotent dataset creation ──────────────────────────────────────────

@test "enabled: idempotent — second apply on existing datasets is no-op" {
  zfs() {
    printf 'zfs %s\n' "$*" >> "$CALLS"
    [[ "$1" == "list" ]] && return 0
    return 0
  }
  export -f zfs
  run_enabled
  if grep -qE "^zfs create " "$CALLS"; then
    echo "FAIL: created datasets when all already exist"
    cat "$CALLS"
    return 1
  fi
}


# ── C6: mkinitcpio rollback hook pair ────────────────────────────────────────

@test "enabled: writes install hook /usr/lib/initcpio/install/zfs-rollback" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/install/zfs-rollback"
  [ -f "$hook_file" ]
  grep -qE "^build\\(\\)" "$hook_file"
  grep -qE "add_runscript" "$hook_file"
}

@test "enabled: writes runtime hook /usr/lib/initcpio/hooks/zfs-rollback" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  [ -f "$hook_file" ]
  # Must be run_latehook so archzfs has finished its zpool import.
  grep -qE "^run_latehook\\(\\)" "$hook_file"
}

@test "enabled: runtime hook has hardcoded Rollback Dataset list" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback" dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "rpool/ROOT/$dataset_name" "$hook_file" \
      || { echo "missing rpool/ROOT/$dataset_name in runtime hook"; return 1; }
  done
}

@test "enabled: runtime hook fails closed on missing @blank snapshot" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  grep -qE "launch_interactive_shell|emergency" "$hook_file"
  grep -qE "zfs list .* @blank|@blank" "$hook_file"
}

@test "enabled: runtime hook runs zfs rollback -r ds@blank" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  grep -qE "zfs rollback -r" "$hook_file"
}

# After rollback, the datasets must be mounted under /new_root — BEFORE
# switch_root — so PID1 reads a populated /etc with the frozen machine-id.
# Left to the post-pivot zfs-mount, /etc is a bare mountpoint at PID1 start:
# systemd mints a TRANSIENT machine-id and dbus/logind/journald key off an
# unstable id → the graphical login can't seat a session (black screen) and
# journald orphans its journal onto the soon-shadowed /var/log. Parity with the
# btrfs hook's early-mount latehook (ADR 0044).
@test "enabled: runtime hook early-mounts rollback datasets under /new_root" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback" pair
  grep -qE "mount -t zfs" "$hook_file"
  grep -q "/new_root" "$hook_file"
  for pair in rpool/ROOT/etc=/etc \
              rpool/ROOT/opt=/opt rpool/ROOT/srv=/srv \
              rpool/ROOT/usrlocal=/usr/local; do
    grep -qF "$pair" "$hook_file" || { echo "missing early-mount pair $pair"; return 1; }
  done
}

# /var + /var/log are separate datasets too — mount them early so dbus's
# machine-id (/var/lib/dbus) and the journal (/var/log) don't land on the
# wrong/empty tree; /var must precede /var/log (nested).
@test "enabled: runtime hook early-mounts /var and /var/log (var first)" {
  run_enabled
  local hook_file="$FAKEROOT/usr/lib/initcpio/hooks/zfs-rollback"
  grep -qF "rpool/var=/var" "$hook_file"
  grep -qF "rpool/var/log=/var/log" "$hook_file"
  local variable_data_position variable_log_position
  variable_data_position="$(byte_offset "rpool/var=/var" "$hook_file")"
  variable_log_position="$(byte_offset "rpool/var/log=/var/log" "$hook_file")"
  [ "$variable_data_position" -lt "$variable_log_position" ]
}


# ── btrfs FS layer (issue 08, ADR 0044): snapshot_blank dispatches on $FILESYSTEM
# On btrfs the rollback containers are subvolumes, not datasets; the @blank
# snapshot is `btrfs subvolume snapshot -r @<name> @<name>@blank` taken over the
# btrfs top-level (subvolid=5), mirroring the per-path ZFS @blank. The full
# top-level mount mechanics are VM-verified; bats covers the snapshot calls.

@test "btrfs: snapshot_blank takes a read-only @blank per rollback subvol" {
  export FILESYSTEM=btrfs
  : > "$CALLS"
  btrfs()   { printf 'btrfs %s\n'  "$*" >> "$CALLS"; }
  mount()   { printf 'mount %s\n'  "$*" >> "$CALLS"; }
  umount()  { printf 'umount %s\n' "$*" >> "$CALLS"; }
  findmnt() { echo /dev/sdX; }
  export -f btrfs mount umount findmnt
  _impermanence_snapshot_blank
  local dataset_name
  for dataset_name in etc opt srv usrlocal; do
    grep -qE "^btrfs subvolume snapshot -r .*/@$dataset_name .*/@$dataset_name@blank$" "$CALLS" \
      || { echo "missing @blank for @$dataset_name"; cat "$CALLS"; return 1; }
  done
}

@test "btrfs: snapshot_blank never calls zfs" {
  export FILESYSTEM=btrfs
  : > "$CALLS"
  btrfs()   { printf 'btrfs %s\n'  "$*" >> "$CALLS"; }
  mount()   { printf 'mount %s\n'  "$*" >> "$CALLS"; }
  umount()  { printf 'umount %s\n' "$*" >> "$CALLS"; }
  findmnt() { echo /dev/sdX; }
  export -f btrfs mount umount findmnt
  _impermanence_snapshot_blank
  ! grep -qE "^zfs " "$CALLS"
}

@test "zfs: snapshot_blank still uses zfs snapshot (default FILESYSTEM)" {
  unset FILESYSTEM
  : > "$CALLS"
  _impermanence_snapshot_blank
  grep -qE "^zfs snapshot rpool/ROOT/etc@blank$" "$CALLS"
}
