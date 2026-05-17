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

  cat > "$BIN_STUBS/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
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
  cat > "$IMPERMANENCE_HOSTS_DIR/testhost/config.jsonc" <<'JSONC'
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

@test "add: invokes systemctl start on the persist-<slug>.mount" {
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

@test "add file: appends path to persist.files in host config" {
  seed_live_file /etc/foo.conf
  "$TOOL" add /etc/foo.conf
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/config.jsonc"
  grep -qE '"/etc/foo.conf"' "$cfg"
}

@test "add dir: appends path to persist.directories in host config" {
  seed_live_dir /etc/wireguard
  "$TOOL" add /etc/wireguard
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/config.jsonc"
  grep -qE '"/etc/wireguard"' "$cfg"
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

@test "remove: removes path from persist.files in host config" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  local cfg="$IMPERMANENCE_HOSTS_DIR/testhost/config.jsonc"
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

@test "remove idempotent: second run on non-persisted path is a no-op" {
  seed_persisted_file /etc/foo.conf
  "$TOOL" remove /etc/foo.conf
  : > "$CALLS"
  run "$TOOL" remove /etc/foo.conf
  [ "$status" -eq 0 ]
  [[ "$output" == *"not persisted"* ]]
  [ ! -s "$CALLS" ]
}
