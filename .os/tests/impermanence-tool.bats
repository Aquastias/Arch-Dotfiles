#!/usr/bin/env bats
# Tests for .os/tools/impermanence.sh — operator CLI for Persist Extensions.
#
# Strategy: redirect filesystem writes under $FAKEROOT via env overrides.
# Stub systemctl/zfs (in $BIN_STUBS, first on PATH) to log argv to $CALLS.

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKEROOT="$TEST_DIR/root"
  CALLS="$TEST_DIR/calls.log"
  BIN_STUBS="$TEST_DIR/bin"
  mkdir -p "$FAKEROOT" "$BIN_STUBS"
  export TEST_DIR FAKEROOT CALLS BIN_STUBS

  TOOL="$BATS_TEST_DIRNAME/../tools/impermanence.sh"
  export TOOL

  MOCK_STATE="$TEST_DIR/mock"
  mkdir -p "$MOCK_STATE"
  : > "$MOCK_STATE/list-units"
  : > "$MOCK_STATE/fragment-paths"
  : > "$MOCK_STATE/what-paths"
  # All Rollback Datasets @blank present by default.
  cat > "$MOCK_STATE/zfs-snapshots" <<EOF
rpool/ROOT/etc@blank
rpool/ROOT/root@blank
rpool/ROOT/opt@blank
rpool/ROOT/srv@blank
rpool/ROOT/usrlocal@blank
EOF
  export MOCK_STATE

  cat > "$BIN_STUBS/zfs" <<'ZFS'
#!/usr/bin/env bash
printf 'zfs %s\n' "$*" >> "$CALLS"
case "$1" in
  list)
    name="${@: -1}"
    if grep -qxF "$name" "$MOCK_STATE/zfs-snapshots"; then
      echo "$name"; exit 0
    fi
    exit 1
    ;;
  diff)
    ds="${@: -1}"
    safe="${ds//\//_}"
    cat "$MOCK_STATE/zfs-diff-$safe" 2>/dev/null
    exit 0
    ;;
esac
ZFS
  chmod +x "$BIN_STUBS/zfs"

  export IMPERMANENCE_RPOOL=rpool

  cat > "$BIN_STUBS/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
case "$1" in
  list-units) cat "$MOCK_STATE/list-units" ;;
  show)
    # systemctl show -p <Prop> --value <unit>
    unit="${@: -1}"
    case "$3" in
      What) grep "^$unit " "$MOCK_STATE/what-paths" 2>/dev/null | awk '{print $2}' ;;
      *)    grep "^$unit " "$MOCK_STATE/fragment-paths" | awk '{print $2}' ;;
    esac
    ;;
esac
STUB
  chmod +x "$BIN_STUBS/systemctl"
  PATH="$BIN_STUBS:$PATH"
  export PATH

  # Default env: impermanence "enabled" (persist mount exists, manifest empty).
  export IMPERMANENCE_ROOT="$FAKEROOT"
  export IMPERMANENCE_MOUNT="$FAKEROOT/persist"
  export IMPERMANENCE_MANIFEST="$FAKEROOT/usr/lib/impermanence/defaults.manifest"
  export IMPERMANENCE_HOSTNAME="testhost"
  export IMPERMANENCE_HOSTS_DIR="$FAKEROOT/os/hosts"
  mkdir -p "$IMPERMANENCE_MOUNT" \
           "$(dirname "$IMPERMANENCE_MANIFEST")" \
           "$IMPERMANENCE_HOSTS_DIR/testhost"
  : > "$IMPERMANENCE_MANIFEST"
  cat > "$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc" <<'JSONC'
{
  "persist": {
    "directories": [],
    "files": []
  }
}
JSONC
}

teardown() { rm -rf "$TEST_DIR"; }

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

# Helper: a "live" file under FAKEROOT, ready to be persisted.
seed_live_file() {
  local path="$1"
  mkdir -p "$IMPERMANENCE_ROOT$(dirname "$path")"
  echo "live-data" > "$IMPERMANENCE_ROOT$path"
}

seed_live_dir() {
  local path="$1"
  mkdir -p "$IMPERMANENCE_ROOT$path"
  echo "live-data" > "$IMPERMANENCE_ROOT$path/marker"
}

@test "add file: writes persist mount unit under /persist/etc/systemd/system" {
  seed_live_file /etc/foo.conf
  run "$TOOL" add /etc/foo.conf
  [ "$status" -eq 0 ]
  local esc; esc="$(systemd-escape --path /etc/foo.conf)"
  [ -f "$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount" ]
}

@test "add file: mount unit binds /persist<path> over <path>" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local esc; esc="$(systemd-escape --path /etc/foo.conf)"
  local unit="$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount"
  grep -qE "^What=$IMPERMANENCE_MOUNT/etc/foo.conf$" "$unit"
  grep -qE "^Where=/etc/foo.conf$" "$unit"
}

@test "add file: appends 'f' tmpfiles entry under /persist/etc/tmpfiles.d" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$conf" ]
  grep -qE "^f /etc/foo.conf " "$conf"
}

@test "add dir: appends 'd' tmpfiles entry" {
  seed_live_dir /etc/wireguard
  "$TOOL" add /etc/wireguard
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  grep -qE "^d /etc/wireguard " "$conf"
}

@test "add: preserves existing tmpfiles entries (append-only)" {
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$conf")"
  printf "d /etc/preexisting 0755 root root - -\n" > "$conf"
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  grep -qE "^d /etc/preexisting " "$conf"
  grep -qE "^f /etc/foo.conf " "$conf"
}

@test "add file: copies live data to /persist<path>" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
  diff "$IMPERMANENCE_ROOT/etc/foo.conf" "$IMPERMANENCE_MOUNT/etc/foo.conf"
}

@test "add dir: copies directory contents to /persist<path>" {
  seed_live_dir /etc/wireguard
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
  local esc; esc="$(systemd-escape --path /etc/foo.conf)"
  grep -qE "^systemctl start $esc.mount$" "$CALLS"
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
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  grep -qE '"/etc/foo.conf"' "$cfg"
}

@test "add dir: appends path to persist.directories in host profile" {
  seed_live_dir /etc/wireguard
  "$TOOL" add /etc/wireguard
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  grep -qE '"/etc/wireguard"' "$cfg"
}

@test "add: rolls back host config entry when materialization fails" {
  seed_live_dir /var/lib/foo
  chmod 555 "$IMPERMANENCE_MOUNT"
  run "$TOOL" add /var/lib/foo
  chmod 755 "$IMPERMANENCE_MOUNT"
  [ "$status" -ne 0 ]
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  run grep -F "/var/lib/foo" "$cfg"
  [ "$status" -ne 0 ]
}

# ── cycle 5: remove happy path ──────────────────────────────────────────────

# Seed a persisted state: file is already on /persist, unit + tmpfiles exist,
# and the host config declares it. This is the state `add` leaves behind.
seed_persisted_file() {
  local target="$1"
  seed_live_file "$target"
  "$TOOL" add "$target"
  : > "$CALLS"  # clear add's systemctl calls
}

@test "remove: errors when path is not currently persisted" {
  run "$TOOL" remove /etc/never-added
  [ "$status" -eq 0 ]
  [[ "$output" == *"not persisted"* ]]
}

@test "remove: stops the persist mount unit" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  local esc; esc="$(systemd-escape --path /etc/foo.conf)"
  grep -qE "^systemctl stop $esc.mount$" "$CALLS"
}

@test "remove: invokes systemctl daemon-reload" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  grep -qE "^systemctl daemon-reload$" "$CALLS"
}

@test "remove: deletes the persist mount unit file" {
  seed_persisted_file /etc/foo.conf
  local esc; esc="$(systemd-escape --path /etc/foo.conf)"
  local unit="$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount"
  [ -f "$unit" ]
  "$TOOL" remove /etc/foo.conf
  [ ! -f "$unit" ]
}

@test "remove: removes tmpfiles entry, preserving siblings" {
  seed_persisted_file /etc/foo.conf
  seed_live_file /etc/bar.conf
  "$TOOL" add /etc/bar.conf
  : > "$CALLS"
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  "$TOOL" remove /etc/foo.conf
  ! grep -qE "^f /etc/foo.conf " "$conf"
  grep -qE "^f /etc/bar.conf " "$conf"
}

@test "remove: removes path from persist.files in host profile" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc"
  ! grep -qE '"/etc/foo.conf"' "$cfg"
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

@test "status: labels curated unit (FragmentPath under /usr/lib/)" {
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

@test "status: labels extension unit (FragmentPath under Persist Dataset)" {
  cat > "$MOCK_STATE/list-units" <<EOF
etc-foo.conf.mount loaded active mounted /etc/foo.conf
EOF
  cat > "$MOCK_STATE/what-paths" <<EOF
etc-foo.conf.mount $IMPERMANENCE_MOUNT/etc/foo.conf
EOF
  cat > "$MOCK_STATE/fragment-paths" <<EOF
etc-foo.conf.mount $IMPERMANENCE_MOUNT/etc/systemd/system/etc-foo.conf.mount
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
  echo "$output" | grep -E "rpool/ROOT/root.* 0 " >/dev/null
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

# Seed live data for all Curated Persist Defaults under $IMPERMANENCE_ROOT.
seed_all_curated_live() {
  local p
  for p in /etc/machine-id /etc/hostname /etc/locale.conf \
           /etc/vconsole.conf /etc/adjtime /etc/fstab; do
    mkdir -p "$IMPERMANENCE_ROOT$(dirname "$p")"
    echo "x" > "$IMPERMANENCE_ROOT$p"
  done
  for p in /etc/ssh /etc/secrets /etc/NetworkManager/system-connections \
           /etc/sudoers.d /etc/pacman.d /root; do
    mkdir -p "$IMPERMANENCE_ROOT$p"
  done
}

# ── slice 5 cycle 7: apply-defaults adds new curated paths ──────────────────

@test "apply-defaults: writes unit for a path in arrays but not manifest" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local esc; esc="$(systemd-escape --path /etc/machine-id)"
  [ -f "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$esc.mount" ]
}

@test "apply-defaults: writes wants symlink for new curated path" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local esc; esc="$(systemd-escape --path /etc/ssh)"
  local w="$IMPERMANENCE_ROOT/usr/lib/systemd/system/local-fs.target.wants"
  [ -L "$w/$esc.mount" ]
}

@test "apply-defaults: writes curated tmpfiles entry for new path" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  "$TOOL" apply-defaults
  local conf="$IMPERMANENCE_ROOT/usr/lib/tmpfiles.d/impermanence-curated.conf"
  [ -f "$conf" ]
  grep -qE "^f /etc/machine-id " "$conf"
  grep -qE "^d /etc/ssh " "$conf"
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
  local esc; esc="$(systemd-escape --path /etc/legacy)"
  local unit_dir="$IMPERMANENCE_ROOT/usr/lib/systemd/system"
  mkdir -p "$unit_dir/local-fs.target.wants"
  : > "$unit_dir/$esc.mount"
  ln -sf "../$esc.mount" \
    "$unit_dir/local-fs.target.wants/$esc.mount"
  "$TOOL" apply-defaults
  [ ! -f "$unit_dir/$esc.mount" ]
  [ ! -L "$unit_dir/local-fs.target.wants/$esc.mount" ]
}

@test "apply-defaults: stops orphan unit via systemctl" {
  echo "/etc/legacy" > "$IMPERMANENCE_MANIFEST"
  local esc; esc="$(systemd-escape --path /etc/legacy)"
  mkdir -p "$IMPERMANENCE_ROOT/usr/lib/systemd/system"
  : > "$IMPERMANENCE_ROOT/usr/lib/systemd/system/$esc.mount"
  "$TOOL" apply-defaults
  grep -qE "^systemctl stop $esc.mount$" "$CALLS"
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
  local m1; m1="$(cat "$IMPERMANENCE_MANIFEST")"
  "$TOOL" apply-defaults
  [ "$m1" = "$(cat "$IMPERMANENCE_MANIFEST")" ]
}

@test "apply-defaults: second run prints no remove notices" {
  seed_all_curated_live
  "$TOOL" apply-defaults
  run "$TOOL" apply-defaults
  [[ "$output" != *"removed curated default"* ]]
}

# ── slice 5 cycle 11: apply-defaults ignores Persist Extensions ─────────────

@test "apply-defaults: does not touch extension units under /persist/" {
  local ext_dir="$IMPERMANENCE_MOUNT/etc/systemd/system"
  mkdir -p "$ext_dir"
  echo "EXT-CONTENT" > "$ext_dir/etc-foo.conf.mount"
  seed_all_curated_live
  "$TOOL" apply-defaults
  [ -f "$ext_dir/etc-foo.conf.mount" ]
  grep -qx "EXT-CONTENT" "$ext_dir/etc-foo.conf.mount"
}

@test "apply-defaults: does not touch extension tmpfiles under /persist/" {
  local ext_tmp="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$ext_tmp")"
  echo "f /etc/extfoo 0644 root root - -" > "$ext_tmp"
  seed_all_curated_live
  "$TOOL" apply-defaults
  [ -f "$ext_tmp" ]
  grep -qx "f /etc/extfoo 0644 root root - -" "$ext_tmp"
}

@test "apply-defaults: removes stale extension unit when path becomes curated" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  local ext_dir="$IMPERMANENCE_MOUNT/etc/systemd/system"
  local ext_unit="$ext_dir/etc-ssh.mount"
  mkdir -p "$ext_dir"
  echo "STALE-EXT" > "$ext_unit"
  "$TOOL" apply-defaults
  [ ! -f "$ext_unit" ]
}

@test "apply-defaults: removes stale extension tmpfiles entry when path becomes curated" {
  : > "$IMPERMANENCE_MANIFEST"
  seed_all_curated_live
  local ext_tmp="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$ext_tmp")"
  echo "d /etc/ssh 0755 root root - -" > "$ext_tmp"
  echo "f /etc/extfoo 0644 root root - -" >> "$ext_tmp"
  "$TOOL" apply-defaults
  run grep -F "/etc/ssh" "$ext_tmp"
  [ "$status" -ne 0 ]
  grep -qF "/etc/extfoo" "$ext_tmp"
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
  for ds in rpool/ROOT/etc rpool/ROOT/root rpool/ROOT/opt \
            rpool/ROOT/srv rpool/ROOT/usrlocal; do
    echo "$output" | grep -qE "^$ds: 0 paths changed " \
      || { echo "missing clean line for $ds in: $output"; return 1; }
  done
}

# ── slice 6 cycle 3: add tmpfiles idempotency ───────────────────────────────

@test "add idempotent: tmpfiles conf stays at exactly one entry for the path" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$conf" ]
  local n; n="$(grep -cE "^[df] /etc/foo\\.conf " "$conf")"
  [ "$n" -eq 1 ]
}

# ── slice 6 cycle 4: add atomic failure — clean all artifacts ───────────────

@test "add atomic: late systemctl start failure leaves no orphan unit/tmpfiles/data" {
  seed_live_dir /var/lib/foo
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
  local esc; esc="$(systemd-escape --path /var/lib/foo)"
  local unit="$IMPERMANENCE_MOUNT/etc/systemd/system/$esc.mount"
  local conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ ! -f "$unit" ]
  [ ! -e "$IMPERMANENCE_MOUNT/var/lib/foo" ]
  if [ -f "$conf" ]; then
    run grep -F "/var/lib/foo" "$conf"
    [ "$status" -ne 0 ]
  fi
}
