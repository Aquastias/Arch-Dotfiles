#!/usr/bin/env bats
# Tests: verbs (split from impermanence-tool.bats;
# shared setup in impermanence-tool-helpers.bash)

load impermanence-tool-helpers


# ── cycle 1: tracer — no verb → usage ───────────────────────────────────────

@test "no verb: exits non-zero" {
  run "$TOOL"
  [ "$status" -ne 0 ]
}

@test "no verb: prints usage to stderr" {
  run "$TOOL"
  [[ "$output" == *"Usage:"* ]]
}


# ── cycle 2: dispatch + arg validation ──────────────────────────────────────

@test "unknown verb: exits non-zero" {
  run "$TOOL" frobnicate
  [ "$status" -ne 0 ]
}

@test "unknown verb: prints usage" {
  run "$TOOL" frobnicate
  [[ "$output" == *"Usage:"* ]]
}

@test "add without path: exits non-zero" {
  run "$TOOL" add
  [ "$status" -ne 0 ]
}

@test "remove without path: exits non-zero" {
  run "$TOOL" remove
  [ "$status" -ne 0 ]
}


# ── cycle 3: preconditions ──────────────────────────────────────────────────

@test "add: errors when persist mount is absent" {
  rm -rf "$IMPERMANENCE_MOUNT"
  run "$TOOL" add /etc/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"impermanence not enabled"* ]]
}

@test "remove: errors when persist mount is absent" {
  rm -rf "$IMPERMANENCE_MOUNT"
  run "$TOOL" remove /etc/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"impermanence not enabled"* ]]
}

@test "add: rejects non-absolute path" {
  run "$TOOL" add etc/foo
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute"* ]]
}

@test "add: rejects path with trailing slash" {
  run "$TOOL" add /etc/foo/
  [ "$status" -ne 0 ]
  [[ "$output" == *"trailing slash"* ]]
}

@test "add: rejects path that is a symlink" {
  mkdir -p "$IMPERMANENCE_ROOT/etc"
  echo data > "$IMPERMANENCE_ROOT/etc/realfile"
  ln -s realfile "$IMPERMANENCE_ROOT/etc/foolink"
  run "$TOOL" add /etc/foolink
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink"* ]]
}

@test "remove: rejects path with trailing slash" {
  run "$TOOL" remove /etc/foo/
  [ "$status" -ne 0 ]
  [[ "$output" == *"trailing slash"* ]]
}

@test "add: rejects path that does not exist on disk" {
  run "$TOOL" add /etc/does-not-exist-on-disk
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "add: rejects a Curated Persist Default" {
  echo "/etc/ssh" > "$IMPERMANENCE_MANIFEST"
  mkdir -p "$FAKEROOT/etc/ssh"
  run "$TOOL" add /etc/ssh
  [ "$status" -ne 0 ]
  [[ "$output" == *"curated"* ]]
}

@test "remove: rejects a Curated Persist Default" {
  echo "/etc/ssh" > "$IMPERMANENCE_MANIFEST"
  run "$TOOL" remove /etc/ssh
  [ "$status" -ne 0 ]
  [[ "$output" == *"curated"* ]]
}


# ── cycle 4: add happy path ─────────────────────────────────────────────────

@test "add file: writes persist mount unit under /usr/lib/systemd/system" {
  seed_live_file /etc/foo.conf
  run "$TOOL" add /etc/foo.conf
  [ "$status" -eq 0 ]
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  [ -f "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount" ]
}

@test "add: links the unit into /usr/lib local-fs.target.wants" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  local wants_directory="$IMPERMANENCE_ROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ -L "$wants_directory/$escaped_path.mount" ]
  [ "$(readlink "$wants_directory/$escaped_path.mount")" = "../$escaped_path.mount" ]
}

@test "add file: mount unit binds /persist<path> over <path>" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  local unit="$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount"
  grep -qE "^What=$IMPERMANENCE_MOUNT/etc/foo.conf$" "$unit"
  grep -qE "^Where=/etc/foo.conf$" "$unit"
}

@test "add file: appends 'f' tmpfiles entry under /persist/etc/tmpfiles.d" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$tmpfiles_config" ]
  grep -qE "^f /etc/foo.conf " "$tmpfiles_config"
}

@test "add dir: appends 'd' tmpfiles entry" {
  seed_live_directory /etc/wireguard
  "$TOOL" add /etc/wireguard
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  grep -qE "^d /etc/wireguard " "$tmpfiles_config"
}

@test "add: preserves existing tmpfiles entries (append-only)" {
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "${tmpfiles_config%/*}"
  printf "d /etc/preexisting 0755 root root - -\n" > "$tmpfiles_config"
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qE "^d /etc/preexisting " "$tmpfiles_config"
  grep -qE "^f /etc/foo.conf " "$tmpfiles_config"
}

@test "add file: copies live data to /persist<path>" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
  diff "$IMPERMANENCE_ROOT/etc/foo.conf" "$IMPERMANENCE_MOUNT/etc/foo.conf"
}

@test "add dir: copies directory contents to /persist<path>" {
  seed_live_directory /etc/wireguard
  "$TOOL" add /etc/wireguard
  [ -d "$IMPERMANENCE_MOUNT/etc/wireguard" ]
  [ -f "$IMPERMANENCE_MOUNT/etc/wireguard/marker" ]
}

@test "add: invokes systemctl daemon-reload" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qE "^systemctl daemon-reload$" "$CALLS"
}

@test "add: invokes systemctl start on the <slug>.mount" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  grep -qE "^systemctl start $escaped_path.mount$" "$CALLS"
}

@test "add idempotent: re-running on persisted path is a no-op notice" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  : > "$CALLS"
  run "$TOOL" add /etc/foo.conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"already persisted"* ]]
  # Idempotency: no new systemctl actions on the second run.
  [ ! -s "$CALLS" ]
}

@test "add file: appends path to persist.files in host profile" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local profile_file="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  grep -qE '"/etc/foo.conf"' "$profile_file"
}

@test "add dir: appends path to persist.directories in host profile" {
  seed_live_directory /etc/wireguard
  "$TOOL" add /etc/wireguard
  local profile_file="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  grep -qE '"/etc/wireguard"' "$profile_file"
}

@test "add: rolls back host config entry when materialization fails" {
  seed_live_directory /var/lib/foo
  chmod 555 "$IMPERMANENCE_MOUNT"
  run "$TOOL" add /var/lib/foo
  chmod 755 "$IMPERMANENCE_MOUNT"
  [ "$status" -ne 0 ]
  local profile_file="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  run grep -F "/var/lib/foo" "$profile_file"
  [ "$status" -ne 0 ]
}


# ── cycle 5: remove happy path ──────────────────────────────────────────────

@test "remove: errors when path is not currently persisted" {
  run "$TOOL" remove /etc/never-added
  [ "$status" -eq 0 ]
  [[ "$output" == *"not persisted"* ]]
}

@test "remove: stops the persist mount unit" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  grep -qE "^systemctl stop $escaped_path.mount$" "$CALLS"
}

@test "remove: invokes systemctl daemon-reload" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  grep -qE "^systemctl daemon-reload$" "$CALLS"
}

@test "remove: deletes the persist mount unit file" {
  seed_persisted_file /etc/foo.conf
  local escaped_path; escaped_path="$(systemd-escape --path /etc/foo.conf)"
  local unit="$IMPERMANENCE_ROOT/usr/lib/systemd/system/$escaped_path.mount"
  [ -f "$unit" ]
  "$TOOL" remove /etc/foo.conf
  [ ! -f "$unit" ]
}

@test "remove: removes tmpfiles entry, preserving siblings" {
  seed_persisted_file /etc/foo.conf
  seed_live_file /etc/bar.conf
  "$TOOL" add /etc/bar.conf
  : > "$CALLS"
  local tmpfiles_config="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  "$TOOL" remove /etc/foo.conf
  ! grep -qE "^f /etc/foo.conf " "$tmpfiles_config"
  grep -qE "^f /etc/bar.conf " "$tmpfiles_config"
}

@test "remove: removes path from persist.files in host profile" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  local profile_file="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  ! grep -qE '"/etc/foo.conf"' "$profile_file"
}

@test "remove without --yes: leaves persisted data in place" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  # Without --yes, data stays in /persist (not moved back to live root).
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
}

@test "remove --yes: moves data back to live path" {
  seed_persisted_file /etc/foo.conf
  rm -rf "$IMPERMANENCE_ROOT/etc/foo.conf"
  "$TOOL" remove --yes /etc/foo.conf
  [ -f "$IMPERMANENCE_ROOT/etc/foo.conf" ]
  [ ! -e "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
}

@test "remove --yes: warns when persisted data is missing" {
  seed_persisted_file /etc/foo.conf
  rm -rf "$IMPERMANENCE_MOUNT/etc/foo.conf"
  run "$TOOL" remove --yes /etc/foo.conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to move back"* ]]
}

@test "remove idempotent: second run on non-persisted path is a no-op" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  : > "$CALLS"
  run "$TOOL" remove /etc/foo.conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"not persisted"* ]]
  [ ! -s "$CALLS" ]
}


# ── slice 5 cycle 1: status tracer ──────────────────────────────────────────

@test "status: errors when persist mount is absent" {
  rm -rf "$IMPERMANENCE_MOUNT"
  run "$TOOL" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"impermanence not enabled"* ]]
}


# ── slice 5 cycle 2: status enumerates *.mount units ────────────────

@test "status: prints each active *.mount unit" {
  cat > "$MOCK_STATE/list-units" <<EOF
etc-ssh.mount loaded active mounted /etc/ssh
etc-foo.conf.mount loaded active mounted /etc/foo.conf
EOF
  cat > "$MOCK_STATE/what-paths" <<EOF
etc-ssh.mount $IMPERMANENCE_MOUNT/etc/ssh
etc-foo.conf.mount $IMPERMANENCE_MOUNT/etc/foo.conf
EOF
  run "$TOOL" status
  [[ "$output" == *"etc-ssh.mount"* ]]
  [[ "$output" == *"etc-foo.conf.mount"* ]]
}

# A real system mount (What= not under the Persist Dataset) is not a Persist
# Mount — status must ignore it now that there is no name prefix to glob.
@test "status: ignores non-persist mount units" {
  cat > "$MOCK_STATE/list-units" <<EOF
etc-ssh.mount loaded active mounted /etc/ssh
tmp.mount loaded active mounted /tmp
EOF
  cat > "$MOCK_STATE/what-paths" <<EOF
etc-ssh.mount $IMPERMANENCE_MOUNT/etc/ssh
tmp.mount tmpfs
EOF
  run "$TOOL" status
  [[ "$output" == *"etc-ssh.mount"* ]]
  [[ "$output" != *"tmp.mount"* ]]
}


# ── slice 5 cycle 3: status labels curated vs extension ─────────────────────

@test "status: labels curated unit (/usr/lib + in the curated manifest)" {
  echo /etc/ssh > "$IMPERMANENCE_MANIFEST"
  cat > "$MOCK_STATE/list-units" <<EOF
etc-ssh.mount loaded active mounted /etc/ssh
EOF
  cat > "$MOCK_STATE/what-paths" <<EOF
etc-ssh.mount $IMPERMANENCE_MOUNT/etc/ssh
EOF
  cat > "$MOCK_STATE/fragment-paths" <<EOF
etc-ssh.mount /usr/lib/systemd/system/etc-ssh.mount
EOF
  run "$TOOL" status
  [[ "$output" == *"curated"*"etc-ssh.mount"* ]] \
    || [[ "$output" == *"etc-ssh.mount"*"curated"* ]]
}

@test "status: labels extension unit (/usr/lib, not in the manifest)" {
  cat > "$MOCK_STATE/list-units" <<EOF
etc-foo.conf.mount loaded active mounted /etc/foo.conf
EOF
  cat > "$MOCK_STATE/what-paths" <<EOF
etc-foo.conf.mount $IMPERMANENCE_MOUNT/etc/foo.conf
EOF
  cat > "$MOCK_STATE/fragment-paths" <<EOF
etc-foo.conf.mount /usr/lib/systemd/system/etc-foo.conf.mount
EOF
  run "$TOOL" status
  [[ "$output" == *"extension"*"etc-foo.conf.mount"* ]] \
    || [[ "$output" == *"etc-foo.conf.mount"*"extension"* ]]
}


# ── slice 5 cycle 4: status drift count per Rollback Dataset ────────────────

@test "status: prints drift count per Rollback Dataset" {
  cat > "$MOCK_STATE/zfs-diff-rpool_ROOT_etc" <<EOF
M	/etc/foo
+	/etc/bar
EOF
  run "$TOOL" status
  [[ "$output" == *"rpool/ROOT/etc"* ]]
  [[ "$output" == *"rpool/ROOT/usrlocal"* ]]
  [[ "$output" == *"zfs diff"* ]]
  # etc has 2 lines of diff
  echo "$output" | grep -E "rpool/ROOT/etc.* 2 " >/dev/null
  # other datasets have 0
  echo "$output" | grep -E "rpool/ROOT/opt.* 0 " >/dev/null
}


# ── slice 5 cycle 5: status fails on missing @blank ─────────────────────────

@test "status: exits non-zero if a Rollback Dataset is missing @blank" {
  grep -v '^rpool/ROOT/etc@blank$' "$MOCK_STATE/zfs-snapshots" \
    > "$MOCK_STATE/zfs-snapshots.tmp"
  mv "$MOCK_STATE/zfs-snapshots.tmp" "$MOCK_STATE/zfs-snapshots"
  run "$TOOL" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"rpool/ROOT/etc@blank"* ]]
  [[ "$output" == *"missing"* ]]
}


# ── slice 5 cycle 6: apply-defaults precondition ────────────────────────────

@test "apply-defaults: errors when persist mount is absent" {
  rm -rf "$IMPERMANENCE_MOUNT"
  run "$TOOL" apply-defaults
  [ "$status" -ne 0 ]
  [[ "$output" == *"impermanence not enabled"* ]]
}
