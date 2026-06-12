#!/usr/bin/env bats
# Tests for lib/impermanence-common.sh — Persist Mount verbs and data
# staging helpers. Verbs operate on a temp ROOT; no real /persist touched.

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKEROOT="$TEST_DIR/root"
  CALLS="$TEST_DIR/calls.log"
  BIN_STUBS="$TEST_DIR/bin"
  mkdir -p "$FAKEROOT" "$BIN_STUBS"
  export TEST_DIR FAKEROOT CALLS BIN_STUBS

  cat > "$BIN_STUBS/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
STUB
  chmod +x "$BIN_STUBS/systemctl"
  PATH="$BIN_STUBS:$PATH"
  export PATH

  export IMPERMANENCE_ROOT="$FAKEROOT"
  export IMPERMANENCE_MOUNT="$FAKEROOT/persist"
  mkdir -p "$IMPERMANENCE_MOUNT"

  # shellcheck source=../lib/impermanence-common.sh
  source "$BATS_TEST_DIRNAME/../lib/impermanence-common.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── imp_write_mount_unit: systemd .mount naming contract ────────────────────
# systemd refuses a .mount unit whose filename != the escaped Where= path
# (Loaded: bad-setting). A wrong name silently breaks every Persist Mount on
# boot — curated dirs (/etc/ssh host keys, /etc/secrets age key, …) never get
# bound over the @blank-rolled-back /etc. Regression guard for that class.

@test "imp_write_mount_unit: names the unit after Where= (systemd .mount contract)" {
  local units="$TEST_DIR/units"
  imp_write_mount_unit /etc/ssh "$units"
  local expected; expected="$(systemd-escape -p --suffix=mount /etc/ssh)"
  [ -f "$units/$expected" ]
}

@test "imp_write_mount_unit: systemd-analyze accepts the generated unit" {
  command -v systemd-analyze >/dev/null 2>&1 || skip "systemd-analyze absent"
  local units="$TEST_DIR/units"
  imp_write_mount_unit /etc/ssh "$units"
  local expected; expected="$(systemd-escape -p --suffix=mount /etc/ssh)"
  run systemd-analyze verify "$units/$expected"
  [ "$status" -eq 0 ]
  [[ "$output" != *"bad unit file setting"* ]]
  [[ "$output" != *"doesn't match unit name"* ]]
}

# ── persist_apply ───────────────────────────────────────────────────────────

@test "persist_apply: writes mount unit under \$IMPERMANENCE_MOUNT/etc/systemd/system" {
  persist_apply /etc/foo.conf f
  [ -f "$IMPERMANENCE_MOUNT/etc/systemd/system/etc-foo.conf.mount" ]
}

@test "persist_apply file: appends 'f 0644' tmpfiles entry under \$IMPERMANENCE_MOUNT/etc/tmpfiles.d" {
  persist_apply /etc/foo.conf f
  conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  [ -f "$conf" ]
  grep -qxF "f /etc/foo.conf 0644 root root - -" "$conf"
}

@test "persist_apply dir: appends 'd 0755' tmpfiles entry" {
  persist_apply /etc/wireguard d
  conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  grep -qxF "d /etc/wireguard 0755 root root - -" "$conf"
}

@test "persist_apply: does NOT reload or start systemd" {
  : > "$CALLS"
  persist_apply /etc/foo.conf f
  ! grep -q '^systemctl' "$CALLS"
}

@test "persist_apply: idempotent — calling twice yields the same tmpfiles content" {
  persist_apply /etc/foo.conf f
  persist_apply /etc/foo.conf f
  conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  count=$(grep -cxF "f /etc/foo.conf 0644 root root - -" "$conf")
  [ "$count" = "1" ]
}

# ── persist_activate ────────────────────────────────────────────────────────

@test "persist_activate: invokes daemon-reload and starts the escaped unit" {
  : > "$CALLS"
  persist_activate /etc/foo.conf
  grep -qxF "systemctl daemon-reload" "$CALLS"
  grep -qxF "systemctl start etc-foo.conf.mount" "$CALLS"
}

# ── persist_stage_in_copy ───────────────────────────────────────────────────

@test "persist_stage_in_copy file: copies live → persist; source intact" {
  mkdir -p "$IMPERMANENCE_ROOT/etc"
  printf "hello\n" > "$IMPERMANENCE_ROOT/etc/foo.conf"
  persist_stage_in_copy /etc/foo.conf
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
  [ -f "$IMPERMANENCE_ROOT/etc/foo.conf" ]
  diff "$IMPERMANENCE_ROOT/etc/foo.conf" "$IMPERMANENCE_MOUNT/etc/foo.conf"
}

@test "persist_stage_in_copy dir: recursive copy preserves contents" {
  mkdir -p "$IMPERMANENCE_ROOT/etc/wireguard"
  printf "marker\n" > "$IMPERMANENCE_ROOT/etc/wireguard/marker"
  persist_stage_in_copy /etc/wireguard
  [ -f "$IMPERMANENCE_MOUNT/etc/wireguard/marker" ]
  [ -f "$IMPERMANENCE_ROOT/etc/wireguard/marker" ]
}

# ── persist_unapply ─────────────────────────────────────────────────────────

@test "persist_unapply: stops the escaped unit and daemon-reloads" {
  persist_apply /etc/foo.conf f
  : > "$CALLS"
  persist_unapply /etc/foo.conf
  grep -qxF "systemctl stop etc-foo.conf.mount" "$CALLS"
  grep -qxF "systemctl daemon-reload" "$CALLS"
}

@test "persist_unapply: removes the mount unit file" {
  persist_apply /etc/foo.conf f
  unit="$IMPERMANENCE_MOUNT/etc/systemd/system/etc-foo.conf.mount"
  [ -f "$unit" ]
  persist_unapply /etc/foo.conf
  [ ! -f "$unit" ]
}

@test "persist_unapply: removes the tmpfiles entry; preserves other lines" {
  conf="$IMPERMANENCE_MOUNT/etc/tmpfiles.d/impermanence-extensions.conf"
  mkdir -p "$(dirname "$conf")"
  printf "d /etc/other 0755 root root - -\n" > "$conf"
  persist_apply /etc/foo.conf f
  persist_unapply /etc/foo.conf
  grep -qxF "d /etc/other 0755 root root - -" "$conf"
  ! grep -qE "^[df] /etc/foo.conf " "$conf"
}

@test "persist_unapply: does NOT move or delete data at /persist<target>" {
  mkdir -p "$IMPERMANENCE_MOUNT/etc"
  printf "payload\n" > "$IMPERMANENCE_MOUNT/etc/foo.conf"
  persist_apply /etc/foo.conf f
  persist_unapply /etc/foo.conf
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
}

@test "persist_unapply: idempotent — no-op on a never-applied target" {
  : > "$CALLS"
  run persist_unapply /etc/never-applied
  [ "$status" -eq 0 ]
}

# ── persist_restore_data ────────────────────────────────────────────────────

@test "persist_restore_data: moves persist → live; source removed" {
  mkdir -p "$IMPERMANENCE_MOUNT/etc" "$IMPERMANENCE_ROOT/etc"
  printf "payload\n" > "$IMPERMANENCE_MOUNT/etc/foo.conf"
  persist_restore_data /etc/foo.conf
  [ -f "$IMPERMANENCE_ROOT/etc/foo.conf" ]
  [ ! -e "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
  grep -qxF "payload" "$IMPERMANENCE_ROOT/etc/foo.conf"
}

@test "persist_restore_data: replaces existing live path" {
  mkdir -p "$IMPERMANENCE_MOUNT/etc" "$IMPERMANENCE_ROOT/etc"
  printf "stale\n"  > "$IMPERMANENCE_ROOT/etc/foo.conf"
  printf "fresh\n"  > "$IMPERMANENCE_MOUNT/etc/foo.conf"
  persist_restore_data /etc/foo.conf
  grep -qxF "fresh" "$IMPERMANENCE_ROOT/etc/foo.conf"
}

@test "persist_restore_data: missing persist source is a no-op warning" {
  run persist_restore_data /etc/never-persisted
  [ "$status" -eq 0 ]
}

# ── persist_stage_in_move ───────────────────────────────────────────────────

@test "persist_stage_in_move file: moves live → persist; source removed" {
  mkdir -p "$IMPERMANENCE_ROOT/etc"
  printf "payload\n" > "$IMPERMANENCE_ROOT/etc/foo.conf"
  persist_stage_in_move /etc/foo.conf
  [ -f "$IMPERMANENCE_MOUNT/etc/foo.conf" ]
  [ ! -e "$IMPERMANENCE_ROOT/etc/foo.conf" ]
  grep -qxF "payload" "$IMPERMANENCE_MOUNT/etc/foo.conf"
}

@test "persist_stage_in_move dir: moves recursively; source removed" {
  mkdir -p "$IMPERMANENCE_ROOT/etc/wireguard"
  printf "marker\n" > "$IMPERMANENCE_ROOT/etc/wireguard/marker"
  persist_stage_in_move /etc/wireguard
  [ -f "$IMPERMANENCE_MOUNT/etc/wireguard/marker" ]
  [ ! -e "$IMPERMANENCE_ROOT/etc/wireguard" ]
}

@test "persist_stage_in_move: missing source is a no-op (no error)" {
  run persist_stage_in_move /etc/never-existed
  [ "$status" -eq 0 ]
}

# ── persist_apply: install-time path overrides ──────────────────────────────

@test "persist_apply: optional unit_dir overrides default location" {
  local alt="$TEST_DIR/alt-units"
  persist_apply /etc/foo.conf f "$alt"
  [ -f "$alt/etc-foo.conf.mount" ]
  [ ! -f "$IMPERMANENCE_MOUNT/etc/systemd/system/etc-foo.conf.mount" ]
}

@test "persist_apply: optional tmpfiles_file overrides default location" {
  local alt_units="$TEST_DIR/alt-units"
  local alt_conf="$TEST_DIR/alt-tmpfiles/impermanence-curated.conf"
  persist_apply /etc/foo.conf f "$alt_units" "$alt_conf"
  [ -f "$alt_conf" ]
  grep -qxF "f /etc/foo.conf 0644 root root - -" "$alt_conf"
}

@test "persist_stage_in_move: optional roots override IMPERMANENCE_ROOT/IMPERMANENCE_MOUNT" {
  local live="$TEST_DIR/live"
  local dest="$TEST_DIR/dest"
  mkdir -p "$live/etc"
  printf "x\n" > "$live/etc/foo.conf"
  persist_stage_in_move /etc/foo.conf "$live" "$dest"
  [ -f "$dest/etc/foo.conf" ]
  [ ! -e "$live/etc/foo.conf" ]
}
