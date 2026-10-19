#!/usr/bin/env bats
# Tests for extras/dm/noctalia-greeter/noctalia-greeter.sh — the
# noctalia-greeter Display Manager Adapter (ADR 0158).
#
# Strategy: run the adapter as a subprocess with pacman, systemctl and
# noctalia-greeter-apply-appearance stubbed as executables in a temp bin dir
# prepended to PATH; config writes redirected to a temp ROOT. Injectable seams:
# GREETD_CONF_DIR, ROOT.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  ROOT="$TEST_DIR/root"
  mkdir -p "$STUB_BIN" "$ROOT"

  COMMAND_LOG="$TEST_DIR/command.log"
  GREETD_CONF_DIR="/etc/greetd"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/dm/noctalia-greeter/noctalia-greeter.sh"

  export COMMAND_LOG GREETD_CONF_DIR ROOT

  local name
  for name in pacman systemctl; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$COMMAND_LOG"\n' "$name" \
      > "$STUB_BIN/$name"
  done
  # The setup step must see the greetd config already written (it resolves
  # the greeter user from it), so the stub records whether it exists.
  cat > "$STUB_BIN/noctalia-greeter-apply-appearance" <<'STUB'
#!/usr/bin/env bash
config=missing
[[ -f "$ROOT$GREETD_CONF_DIR/config.toml" ]] && config=present
echo "apply-appearance GREETER_USER=$GREETER_USER $* config=$config" \
  >> "$COMMAND_LOG"
STUB
  chmod +x "$STUB_BIN"/*

  export PATH="$STUB_BIN:$PATH"
  CONF="$ROOT$GREETD_CONF_DIR/config.toml"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "installs greetd and noctalia-greeter from the repos, nothing else" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "pacman -S --noconfirm --needed greetd noctalia-greeter" \
    "$COMMAND_LOG"
  [ "$(grep -c '^pacman ' "$COMMAND_LOG")" -eq 1 ]
}

@test "greetd launches noctalia-greeter-session as the greeter user on VT 2" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx 'command = "/usr/bin/noctalia-greeter-session"' "$CONF"
  grep -qx 'user = "greeter"' "$CONF"
  grep -qx 'vt = 2' "$CONF"
  grep -qx 'Conflicts=getty@tty2.service' \
    "$ROOT/etc/systemd/system/greetd.service.d/10-vt2.conf"
}

@test "initializes greeter state after the greetd config exists" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx \
    "apply-appearance GREETER_USER=greeter --setup-system config=present" \
    "$COMMAND_LOG"
}

@test "enables the greetd service" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "systemctl enable greetd" "$COMMAND_LOG"
}
