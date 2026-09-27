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
  # pgrep: noctalia runs; no other agent does (per-test override adds one).
  stub pgrep 'case "$*" in *agent*|*polkit*) exit 1 ;; *) exit 0 ;; esac'
  # Noctalia's own log line once its agent registers (v5, VM-observed).
  mkdir -p "$T/home/.cache/noctalia"
  printf '%s %s\n' "2026-09-27 13:57:18.496 [INF] [app]" \
    "polkit authentication agent active" \
    > "$T/home/.cache/noctalia/noctalia.log"
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

@test "wlroots session: Noctalia's active agent is POLKIT-OK agents=noctalia" {
  run "$PROBER"
  grep -q '===NIRI-POLKIT-OK agents=noctalia===' "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: a second agent running is reported alongside" {
  stub pgrep 'case "$*" in *polkit-kde*) exit 0 ;; *agent*|*polkit*) exit 1 ;;
    *) exit 0 ;; esac'
  run "$PROBER"
  local want='agents=noctalia,polkit-kde-authentication-agent-1==='
  grep -q "===NIRI-POLKIT-OK $want" "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: no registered agent is POLKIT-FAIL" {
  : > "$T/home/.cache/noctalia/noctalia.log"
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
