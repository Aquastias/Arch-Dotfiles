#!/usr/bin/env bats
# Tests for .os/lib/shell/notifications.sh — send_user_notification helper.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  CAPTURE="$TEST_DIR/argv"
  mkdir -p "$STUB_BIN"
  export TEST_DIR STUB_BIN CAPTURE

  # shellcheck source=../lib/shell/notifications.sh
  source "$BATS_TEST_DIRNAME/../lib/shell/notifications.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

_stub_id() {
  local uid="$1"
  cat > "$STUB_BIN/id" <<EOF
#!/usr/bin/env bash
[[ "\$1" == "-u" ]] && echo "$uid" && exit 0
exit 1
EOF
  chmod +x "$STUB_BIN/id"
}

_stub_loginctl() {
  local include_display="$1"
  local body=""
  [[ "$include_display" == "yes" ]] && body="Display=:0"
  cat > "$STUB_BIN/loginctl" <<EOF
#!/usr/bin/env bash
echo "$body"
EOF
  chmod +x "$STUB_BIN/loginctl"
}

_stub_sudo_capture() {
  # Capture full argv to $CAPTURE so tests can assert on it.
  cat > "$STUB_BIN/sudo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$CAPTURE"
EOF
  chmod +x "$STUB_BIN/sudo"
}

@test "send_user_notification: SUDO_USER unset → exit 1, stderr message" {
  unset SUDO_USER
  run send_user_notification "title" "msg"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be run with sudo"* ]]
}

@test "send_user_notification: dbus socket missing → silent skip, no sudo" {
  _stub_id 99999  # uid with no /run/user/99999/bus
  _stub_sudo_capture
  SUDO_USER=tester \
    PATH="$STUB_BIN:$PATH" \
    run send_user_notification "title" "msg"
  [ "$status" -eq 0 ]
  [ ! -e "$CAPTURE" ]
}

@test "send_user_notification: dbus socket present but no Display= → silent skip" {
  [[ -S "/run/user/$(command id -u)/bus" ]] \
    || skip "no user dbus bus at /run/user/$(command id -u)/bus"
  _stub_id "$(command id -u)"
  _stub_loginctl no
  _stub_sudo_capture
  SUDO_USER=tester \
    PATH="$STUB_BIN:$PATH" \
    run send_user_notification "title" "msg"
  [ "$status" -eq 0 ]
  [ ! -e "$CAPTURE" ]
}

@test "send_user_notification: happy path → sudo invoked with expected argv" {
  [[ -S "/run/user/$(command id -u)/bus" ]] \
    || skip "no user dbus bus at /run/user/$(command id -u)/bus"
  _stub_id "$(command id -u)"
  _stub_loginctl yes
  _stub_sudo_capture
  SUDO_USER=tester \
    PATH="$STUB_BIN:$PATH" \
    run send_user_notification "the title" "the message"
  [ "$status" -eq 0 ]
  [ -f "$CAPTURE" ]
  argv="$(cat "$CAPTURE")"
  [[ "$argv" == *"-u"* ]]
  [[ "$argv" == *"tester"* ]]
  [[ "$argv" == *"notify-send"* ]]
  [[ "$argv" == *"-a"* ]]
  [[ "$argv" == *"Notification"* ]]
  [[ "$argv" == *"dialog-information"* ]]
  [[ "$argv" == *"15000"* ]]
  [[ "$argv" == *"the title"* ]]
  [[ "$argv" == *"the message"* ]]
}
