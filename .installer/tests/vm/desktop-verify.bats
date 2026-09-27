#!/usr/bin/env bats
# vm/fixtures/desktop-verify — the TEST-ONLY session prober. Driven here with
# stubbed system tools (journalctl/busctl/pgrep/id/systemctl) and a temp state
# dir + tty file, so the per-session markers are checked without a VM.

setup() {
  PROBER="$BATS_TEST_DIRNAME/../../vm/fixtures/desktop-verify/desktop-verify"
  T="$(mktemp -d)"
  export DESKTOP_VERIFY_STATE="$T/state" DESKTOP_VERIFY_TTY="$T/tty"
  export DESKTOP_VERIFY_CONF="$T/sddm.conf" DESKTOP_VERIFY_RUNDIR="$T/run"
  export DESKTOP_VERIFY_HOMEDIR="$T/home" DESKTOP_VERIFY_POLL_SECONDS=1
  export DESKTOP_VERIFY_POLKIT_SECONDS=1
  mkdir -p "$DESKTOP_VERIFY_STATE" "$T/run/1000" "$T/bin" \
    "$T/home/.config/noctalia"
  : > "$T/run/1000/wayland-1"
  : > "$DESKTOP_VERIFY_TTY"
  printf 'niri.desktop hyprland.desktop\n' > "$DESKTOP_VERIFY_STATE/order"
  printf 'NIRI HYPR\n' > "$DESKTOP_VERIFY_STATE/tags"
  printf 'tester\n' > "$DESKTOP_VERIFY_STATE/user"
  printf '0\n' > "$DESKTOP_VERIFY_STATE/idx"
  printf '[Autologin]\nSession=niri.desktop\n' > "$DESKTOP_VERIFY_CONF"
  cat > "$T/home/.config/noctalia/config.toml" <<'TOML'
[idle.behavior.lock]
timeout = 300
action = "lock"
enabled = true
TOML
  stub id 'echo 1000'
  stub systemctl 'echo "systemctl $*" >> "'"$T"'/calls"'
  stub pgrep 'exit 0'
  stub busctl 'echo "PID=4242"'
  # A real polkitd registration line, split only to fit the file width.
  stub journalctl 'printf "%s%s\n" \
    "Registered Authentication Agent for unix-session:2 (system bus name " \
    ":1.42 [x], object path /org/freedesktop/PolicyKit1/AuthenticationAgent)"'
  mkdir -p "$T/proc/4242"; printf 'noctalia\n' > "$T/proc/4242/comm"
  export DESKTOP_VERIFY_PROC="$T/proc"
  PATH="$T/bin:$PATH"
}

teardown() { rm -rf "$T"; }

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$T/bin/$1"
  chmod +x "$T/bin/$1"
}

@test "niri session: emits SESSION-OK and advances to the next session" {
  run "$PROBER"
  grep -q '===NIRI-SESSION-OK===' "$DESKTOP_VERIFY_TTY"
  grep -q 'Session=hyprland.desktop' "$DESKTOP_VERIFY_CONF"
  grep -q 'systemctl reboot' "$T/calls"
}

@test "wlroots session: records the registered polkit agent by process" {
  run "$PROBER"
  grep -q '===NIRI-POLKIT-OK agents=noctalia===' "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: no registered agent is POLKIT-FAIL" {
  stub journalctl 'exit 0'
  run "$PROBER"
  grep -q '===NIRI-POLKIT-FAIL===' "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: noctalia running with idle lock enabled is IDLE-OK" {
  run "$PROBER"
  grep -q '===NIRI-IDLE-OK===' "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: idle lock disabled is IDLE-FAIL" {
  sed -i 's/enabled = true/enabled = false/' \
    "$T/home/.config/noctalia/config.toml"
  run "$PROBER"
  grep -q '===NIRI-IDLE-FAIL===' "$DESKTOP_VERIFY_TTY"
}

@test "KDE session: no polkit/idle probe is emitted" {
  printf 'plasma.desktop\n' > "$DESKTOP_VERIFY_STATE/order"
  printf 'KDE\n' > "$DESKTOP_VERIFY_STATE/tags"
  run "$PROBER"
  grep -q '===KDE-SESSION-OK===' "$DESKTOP_VERIFY_TTY"
  ! grep -q 'POLKIT\|IDLE' "$DESKTOP_VERIFY_TTY"
  grep -q '===SESSION-VERIFY-DONE===' "$DESKTOP_VERIFY_TTY"
}
