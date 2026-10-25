#!/usr/bin/env bats
# Tests for extras/dm/noctalia-greeter/noctalia-greeter.sh — the
# noctalia-greeter Display Manager Adapter (ADR 0158).
#
# Strategy: run the adapter as a subprocess with pacman, systemctl and
# noctalia-greeter-apply-appearance, getent and usermod stubbed as executables in a temp bin dir
# prepended to PATH; config writes redirected to a temp ROOT. Injectable seams:
# GREETD_CONF_DIR, ROOT; SEAT_GROUP=1 makes the `seat` group exist.

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
  for name in pacman systemctl usermod; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "$COMMAND_LOG"\n' "$name" \
      > "$STUB_BIN/$name"
  done
  # The setup step must see the greetd config already written (it resolves
  # the greeter user from it), so the stub records whether it exists.
  cat > "$STUB_BIN/noctalia-greeter-apply-appearance" <<'STUB'
#!/usr/bin/env bash
config=missing
[[ -f "$ROOT$GREETD_CONF_DIR/config.toml" ]] && config=present
sync=missing
[[ -f "$ROOT/var/lib/noctalia-greeter/sync.toml" ]] && sync=present
echo "sync-before-setup=$sync" >> "$COMMAND_LOG"
echo "apply-appearance GREETER_USER=$GREETER_USER $* config=$config" \
  >> "$COMMAND_LOG"
STUB
  # getent: the `seat` group exists only where a DE adapter installed seatd.
  cat > "$STUB_BIN/getent" <<'STUB'
#!/usr/bin/env bash
[[ "$1 $2" == "group seat" && -n "${SEAT_GROUP:-}" ]] || exit 2
echo "seat:x:975:"
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

# niri/Hyprland enable seatd (ADR 0068): libseat tries /run/seatd.sock first,
# which only the `seat` group may open, and logind's fallback can't grant DRM
# master on the AMD laptop — so the greeter compositor needs the group.
@test "adds the greeter user to the seat group when seatd is installed" {
  SEAT_GROUP=1 run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "usermod -aG seat greeter" "$COMMAND_LOG"
}

@test "leaves the greeter's groups alone on a host without seatd" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "^usermod" "$COMMAND_LOG"
}

# Default Session (ADR 0159): desktop[0] is seeded as the remembered last
# session, never `[session].default`, so the operator's next pick wins.
@test "seeds desktop[0] as the greeter's remembered last session" {
  ENVIRONMENT_DESKTOP="niri kde hyprland" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  SYNC="$ROOT/var/lib/noctalia-greeter/sync.toml"
  [ "$(cat "$SYNC")" == "$(printf '[session]\nlast = "niri"')" ]
}

@test "the Default Session names KDE by its plasma session entry" {
  ENVIRONMENT_DESKTOP="kde niri" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx 'last = "plasma"' "$ROOT/var/lib/noctalia-greeter/sync.toml"
}

@test "seeds the Default Session before the setup step chowns sync.toml" {
  ENVIRONMENT_DESKTOP="niri" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx 'sync-before-setup=present' "$COMMAND_LOG"
}

@test "never forces the greeter's default session" {
  ENVIRONMENT_DESKTOP="niri kde" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -rq '^default' "$ROOT/var/lib/noctalia-greeter"
}

@test "no desktop: no Default Session seeded" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/var/lib/noctalia-greeter/sync.toml" ]
}
