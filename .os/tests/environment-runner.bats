#!/usr/bin/env bats
# Tests for the Environment Runner in lib/chroot/extras.sh.
#
# Strategy: run extras.sh as a subprocess. Injectable seams:
#   EXTRAS_DIR — base path for adapter scripts (default /root/extras)
#   STATE  — path to install-state.json
#            (default /root/lib-chroot/install-state.json)
# Adapter stubs are executable scripts under $EXTRAS_DIR/desktop/<de>/<de>.sh
# that append the DE name to $STUB_LOG.

setup() {
  TEST_DIR="$(mktemp -d)"
  EXTRAS_DIR="$TEST_DIR/extras"
  STATE_FILE="$TEST_DIR/state.json"
  STUB_LOG="$TEST_DIR/invocations.log"
  RUNNER="$BATS_TEST_DIRNAME/../lib/chroot/extras.sh"

  mkdir -p "$EXTRAS_DIR"
  export EXTRAS_DIR STATE_FILE STUB_LOG

  _state > "$STATE_FILE"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Full minimum install-state body. Override fields via $1 (jq filter).
_state() {
  local override="${1:-.}"
  jq -c "$override" <<'JSON'
{"hostname":"h","timezone":"UTC","locale":"en_US.UTF-8","keymap":"us",
 "kernel":"lts", "kernels": ["lts"],"bootloader":"systemd-boot","rpool":"rpool","swap":true,
 "esp_count":1,"extras":{"backup":false,"security":false},
 "impermanence":{"enabled":false,"dataset":"rpool/persist","mount":"/persist"},
 "persist":{"directories":[],"files":[]}}
JSON
}

make_de_stub() {
  local de="$1"
  mkdir -p "$EXTRAS_DIR/desktop/$de"
  printf '#!/usr/bin/env bash\necho "%s" >> "$STUB_LOG"\n' "$de" \
    > "$EXTRAS_DIR/desktop/$de/$de.sh"
  chmod +x "$EXTRAS_DIR/desktop/$de/$de.sh"
}

# ── runner dispatch ───────────────────────────────────────────────────────

@test "empty ENVIRONMENT_DESKTOP exits 0 and invokes no adapters" {
  run env ENVIRONMENT_DESKTOP="" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -eq 0 ]
  [ ! -f "$STUB_LOG" ]
}

@test "single DE in ENVIRONMENT_DESKTOP invokes that adapter" {
  make_de_stub kde
  run env ENVIRONMENT_DESKTOP="kde" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -eq 0 ]
  grep -qx "kde" "$STUB_LOG"
}

@test "multiple DEs invoke all adapters in order" {
  make_de_stub kde
  make_de_stub hyprland
  run env ENVIRONMENT_DESKTOP="kde hyprland" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG")" = "$(printf 'kde\nhyprland')" ]
}

@test "unknown DE exits non-zero with clear error" {
  run env ENVIRONMENT_DESKTOP="gnome" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "gnome" ]]
}

@test "backup script invoked when backup=true in state" {
  _state '.extras.backup = true' > "$STATE_FILE"
  printf '#!/usr/bin/env bash\necho "backup" >> "$STUB_LOG"\n' \
    > "$EXTRAS_DIR/backup.sh"
  chmod +x "$EXTRAS_DIR/backup.sh"
  run env ENVIRONMENT_DESKTOP="" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -eq 0 ]
  grep -qx "backup" "$STUB_LOG"
}

@test "security script invoked when security=true in state" {
  _state '.extras.security = true' > "$STATE_FILE"
  printf '#!/usr/bin/env bash\necho "security" >> "$STUB_LOG"\n' \
    > "$EXTRAS_DIR/security.sh"
  chmod +x "$EXTRAS_DIR/security.sh"
  run env ENVIRONMENT_DESKTOP="" STATE="$STATE_FILE" \
    EXTRAS_DIR="$EXTRAS_DIR" bash "$RUNNER"
  [ "$status" -eq 0 ]
  grep -qx "security" "$STUB_LOG"
}
