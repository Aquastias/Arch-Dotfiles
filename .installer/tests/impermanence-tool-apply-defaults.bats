#!/usr/bin/env bats
# Tests: apply-defaults (split from impermanence-tool.bats;
# shared setup in impermanence-tool-helpers.bash)

load impermanence-tool-helpers


# ── slice 5 cycle 7: apply-defaults adds new curated paths ──────────────────

@test "apply-defaults: writes unit for a path in arrays but not manifest" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local escaped_path; escaped_path="$(systemd-escape --path /etc/machine-id)"
  [ -f "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount" ]
}

@test "apply-defaults: writes wants symlink for new curated path" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local escaped_path; escaped_path="$(systemd-escape --path /etc/ssh)"
  local wants_directory="$IMPERMANENCE_ROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ -L "$wants_directory/$escaped_path.mount" ]
}

@test "apply-defaults: writes curated tmpfiles entry for new path" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local tmpfiles_config="$IMPERMANENCE_ROOT/usr/lib/tmpfiles.d/impermanence-curated.conf"
  [ -f "$tmpfiles_config" ]
  grep -qE "^f /etc/machine-id " "$tmpfiles_config"
  grep -qE "^d /etc/ssh " "$tmpfiles_config"
}

@test "apply-defaults: copies live data to /persist for new path" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  echo "abc123" > "$IMPERMANENCE_ROOT/etc/machine-id"
  "$TOOL" apply-defaults
  [ -f "$IMPERMANENCE_MOUNT/etc/machine-id" ]
  diff "$IMPERMANENCE_ROOT/etc/machine-id" "$IMPERMANENCE_MOUNT/etc/machine-id"
}


# ── slice 5 cycle 8: apply-defaults removes orphaned curated ────────────────

@test "apply-defaults: deletes unit file for orphan manifest path" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  local escaped_path; escaped_path="$(systemd-escape --path /etc/legacy)"
  local unit_directory="$IMPERMANENCE_ROOT/usr/lib/systemd/system"
  mkdir -p "$unit_directory/local-fs.target.wants"
  : > "$unit_directory/$escaped_path.mount"
  ln -sf "../$escaped_path.mount" \
    "$unit_directory/local-fs.target.wants/$escaped_path.mount"
  "$TOOL" apply-defaults
  [ ! -f "$unit_directory/$escaped_path.mount" ]
  [ ! -L "$unit_directory/local-fs.target.wants/$escaped_path.mount" ]
}

@test "apply-defaults: stops orphan unit via systemctl" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  local escaped_path; escaped_path="$(systemd-escape --path /etc/legacy)"
  mkdir -p "$IMPERMANENCE_ROOT/usr/lib/systemd/system"
  : > "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount"
  "$TOOL" apply-defaults
  grep -qE "^systemctl stop $escaped_path.mount$" "$CALLS"
}

@test "apply-defaults: prints orphan data notice with /persist path" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  mkdir -p "$IMPERMANENCE_MOUNT/etc"
  echo "data" > "$IMPERMANENCE_MOUNT/etc/legacy"
  run "$TOOL" apply-defaults
  [[ "$output" == *"/etc/legacy"* ]]
  [[ "$output" == *"$IMPERMANENCE_MOUNT/etc/legacy"* ]] \
    || [[ "$output" == *"data preserved"* ]]
}

@test "apply-defaults: leaves orphan data on /persist (no auto-delete)" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  mkdir -p "$IMPERMANENCE_MOUNT/etc"
  echo "keepme" > "$IMPERMANENCE_MOUNT/etc/legacy"
  "$TOOL" apply-defaults
  [ -f "$IMPERMANENCE_MOUNT/etc/legacy" ]
  grep -q keepme "$IMPERMANENCE_MOUNT/etc/legacy"
}


# ── slice 5 cycle 9: apply-defaults rewrites manifest ───────────────────────

@test "apply-defaults: rewrites manifest from current curated arrays" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  "$TOOL" apply-defaults
  grep -qxF /etc/machine-id "$IMPERMANENCE_MANIFEST"
  grep -qxF /etc/ssh "$IMPERMANENCE_MANIFEST"
  ! grep -qxF /etc/legacy "$IMPERMANENCE_MANIFEST"
}

@test "apply-defaults: manifest is sorted" {
  : > "$IMPERMANENCE_MANIFEST"
  "$TOOL" apply-defaults
  diff "$IMPERMANENCE_MANIFEST" <(sort "$IMPERMANENCE_MANIFEST")
}


# ── slice 5 cycle 10: apply-defaults idempotency ────────────────────────────

@test "apply-defaults: second run makes no systemctl calls" {
  seed_all_curated_live
  "$TOOL" apply-defaults
  : > "$CALLS"
  "$TOOL" apply-defaults
  [ ! -s "$CALLS" ]
}

@test "apply-defaults: manifest is stable across two runs" {
  seed_all_curated_live
  "$TOOL" apply-defaults
  local first_manifest; first_manifest="$(cat "$IMPERMANENCE_MANIFEST")"
  "$TOOL" apply-defaults
  [ "$first_manifest" = "$(cat "$IMPERMANENCE_MANIFEST")" ]
}

@test "apply-defaults: second run prints no remove notices" {
  seed_all_curated_live
  "$TOOL" apply-defaults
  run "$TOOL" apply-defaults
  [[ "$output" != *"removed curated default"* ]]
}


# ── slice 5 cycle 11: apply-defaults ignores Persist Extensions ─────────────

@test "apply-defaults: does not touch extension units under /usr/lib" {
  local extensions_directory="$IMPERMANENCE_ROOT/usr/lib/systemd/system"
  mkdir -p "$extensions_directory"
  echo "EXT-CONTENT" > "$extensions_directory/etc-foo.conf.mount"
  seed_all_curated_live
  "$TOOL" apply-defaults
  [ -f "$extensions_directory/etc-foo.conf.mount" ]
  grep -qx "EXT-CONTENT" "$extensions_directory/etc-foo.conf.mount"
}

@test "apply-defaults: does not touch extension tmpfiles under /persist/" {
  local extensions_tmpfiles="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "${extensions_tmpfiles%/*}"
  echo "f /etc/extfoo 0644 root root - -" > "$extensions_tmpfiles"
  seed_all_curated_live
  "$TOOL" apply-defaults
  [ -f "$extensions_tmpfiles" ]
  grep -qx "f /etc/extfoo 0644 root root - -" "$extensions_tmpfiles"
}

@test "apply-defaults: drops a stale legacy /persist unit on becoming curated" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  local extensions_directory="$IMPERMANENCE_MOUNT/etc/systemd/system"
  local ext_unit="$extensions_directory/etc-ssh.mount"
  mkdir -p "$extensions_directory"
  echo "STALE-EXT" > "$ext_unit"
  "$TOOL" apply-defaults
  [ ! -f "$ext_unit" ]
}

@test "apply-defaults: removes stale extension tmpfiles entry when path becomes curated" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  local extensions_tmpfiles="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "${extensions_tmpfiles%/*}"
  echo "d /etc/ssh 0755 root root - -" > "$extensions_tmpfiles"
  echo "f /etc/extfoo 0644 root root - -" >> "$extensions_tmpfiles"
  "$TOOL" apply-defaults
  run grep -F "/etc/ssh" "$extensions_tmpfiles"
  [ "$status" -ne 0 ]
  grep -qF "/etc/extfoo" "$extensions_tmpfiles"
}


# ── slice 6 cycle 1: apply-defaults warns on /persist kind mismatch ─────────

@test "apply-defaults: warns when /persist data kind disagrees with curated kind" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  # /etc/ssh is in CURATED_DIRS, but stage /persist/etc/ssh as a FILE
  # (simulates an older schema where the path used to be a file).
  mkdir -p "$IMPERMANENCE_MOUNT/etc"
  rm -rf "$IMPERMANENCE_MOUNT/etc/ssh"
  echo "wrong-kind" > "$IMPERMANENCE_MOUNT/etc/ssh"
  run "$TOOL" apply-defaults
  [ "$status" -eq 0 ]
  [[ "$output" == *"/etc/ssh"* ]]
  [[ "$output" == *"kind"* ]]
}


# ── slice 6 cycle 2: status zero-drift output ───────────────────────────────

@test "status: clean rollback datasets each report zero drift" {
  # default fixture: no zfs-diff-* files staged → all datasets show 0
  run "$TOOL" status
  [ "$status" -eq 0 ]
  for dataset in rpool/ROOT/etc rpool/ROOT/opt \
            rpool/ROOT/srv rpool/ROOT/usrlocal; do
    echo "$output" | grep -qE "^$dataset: 0 paths changed " \
      || { echo "missing clean line for $dataset in: $output"; return 1; }
  done
}


# ── slice 6 cycle 3: add tmpfiles idempotency ───────────────────────────────

@test "add idempotent: tmpfiles conf stays at exactly one entry for the path" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$tmpfiles_config" ]
  local entry_count; entry_count="$(grep -cE "^[df] /etc/foo\\.conf " "$tmpfiles_config")"
  [ "$entry_count" -eq 1 ]
}


# ── slice 6 cycle 4: add atomic failure — clean all artifacts ───────────────

@test "add atomic: late systemctl start failure leaves no orphan unit/tmpfiles/data" {
  seed_live_directory /var/lib/foo
  # Replace systemctl stub: succeed on daemon-reload, fail on start.
  cat > "$BIN_STUBS/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
case "$1" in
  start) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$BIN_STUBS/systemctl"
  run "$TOOL" add /var/lib/foo
  [ "$status" -ne 0 ]
  local escaped_path; escaped_path="$(systemd-escape --path /var/lib/foo)"
  local unit="$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount"
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ ! -f "$unit" ]
  local wants_directory="$IMPERMANENCE_ROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ ! -L "$wants_directory/$escaped_path.mount" ]
  [ ! -e "$IMPERMANENCE_MOUNT/var/lib/foo" ]
  if [ -f "$tmpfiles_config" ]; then
    run grep -F "/var/lib/foo" "$tmpfiles_config"
    [ "$status" -ne 0 ]
  fi
}


# ── profile lookup (ADR 0020: profile name ≠ hostname) ──────────────────────

@test "profile lookup: finds the profile whose system.hostname pins it" {
  seed_pinned_profile
  export IMPERMANENCE_HOSTNAME="eterniox"
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qF '"/etc/foo.conf"' "$IMPERMANENCE_HOSTS_DIR/desktop/profile.jsonc"
}

@test "profile lookup: IMPERMANENCE_PROFILE names the profile explicitly" {
  seed_pinned_profile
  export IMPERMANENCE_HOSTNAME="unrelated" IMPERMANENCE_PROFILE="desktop"
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qF '"/etc/foo.conf"' "$IMPERMANENCE_HOSTS_DIR/desktop/profile.jsonc"
}

@test "profile lookup: falls back to hosts/vm/<name>" {
  mkdir -p "$IMPERMANENCE_HOSTS_DIR/vm"
  mv "$IMPERMANENCE_HOSTS_DIR/testhost" "$IMPERMANENCE_HOSTS_DIR/vm/testhost"
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qF '"/etc/foo.conf"' "$IMPERMANENCE_HOSTS_DIR/vm/testhost/profile.jsonc"
}

@test "profile lookup: no matching profile aborts before any change" {
  export IMPERMANENCE_HOSTNAME="ghost"
  seed_live_file /etc/foo.conf
  run "$TOOL" add /etc/foo.conf
  [ "$status" -ne 0 ]
  [[ "$output" == *"IMPERMANENCE_PROFILE"* ]]
  [[ "$output" == *"testhost"* ]]
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  [ ! -f "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount" ]
  [ ! -e "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
}
