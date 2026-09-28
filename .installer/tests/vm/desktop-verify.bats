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
  # Clipboard probe (ADR 0147): a file-backed fake clipboard. kitty "owns" the
  # tokens it pipes to `kitten clipboard` (regular, then --use-primary);
  # closing it keeps the regular one (Noctalia adopted) unless $T/lost exists.
  # runuser just runs the command.
  export DESKTOP_VERIFY_CLIP_SECONDS=0.3 DESKTOP_VERIFY_CLIP_SETTLE=0
  stub runuser 'shift 3; exec "$@"'
  stub kitty 'k="s/^ *printf %s \([^ ]*\) | kitten clipboard"
    sed -n "$k;\$/\1/p" <<<"$4" > "'"$T"'/clip"
    sed -n "$k --use-primary;\$/\1/p" <<<"$4" > "'"$T"'/clipp"'
  stub pkill '[ -e "'"$T"'/lost" ] && : > "'"$T"'/clip"; exit 0'
  stub wl-paste 'f="'"$T"'/clip"; [ "$1" = -p ] && f="'"$T"'/clipp"
    [ -s "$f" ] && cat "$f"'
  stub pacman 'echo "hyprland ${HYPR_VER:-0.56.2-1}"'
  stub vercmp '[ "$1" = "$2" ] && { echo 0; exit; }
    [ "$(printf "%s\n" "$1" "$2" | sort -V | head -1)" = "$1" ] \
      && echo -1 || echo 1'
  PATH="$T/bin:$PATH"
}

hypr_only() {
  printf 'hyprland.desktop\n' > "$DESKTOP_VERIFY_STATE/order"
  printf 'HYPR\n' > "$DESKTOP_VERIFY_STATE/tags"
  printf '[Autologin]\nSession=hyprland.desktop\n' > "$DESKTOP_VERIFY_CONF"
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

@test "wlroots session: live + primary + kept after close is CLIPBOARD-OK" {
  run "$PROBER"
  grep -q '===NIRI-CLIPBOARD-OK===' "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: clipboard lost on close is CLIPBOARD-FAIL keep=fail" {
  : > "$T/lost"
  run "$PROBER"
  grep -q '===NIRI-CLIPBOARD-FAIL live=ok primary=ok keep=fail===' \
    "$DESKTOP_VERIFY_TTY"
}

@test "wlroots session: no live paste is CLIPBOARD-FAIL live=fail" {
  stub kitty ':'
  run "$PROBER"
  grep -q '===NIRI-CLIPBOARD-FAIL live=fail primary=fail keep=fail===' \
    "$DESKTOP_VERIFY_TTY"
}

@test "Hyprland < 0.57: a keep miss is expected (keep=xfail, ADR 0147)" {
  hypr_only; : > "$T/lost"
  run "$PROBER"
  grep -q '===HYPR-CLIPBOARD-OK keep=xfail===' "$DESKTOP_VERIFY_TTY"
}

@test "Hyprland >= 0.57: a keep miss is a real CLIPBOARD-FAIL" {
  hypr_only; : > "$T/lost"
  export HYPR_VER=0.57.0-1
  run "$PROBER"
  grep -q '===HYPR-CLIPBOARD-FAIL live=ok primary=ok keep=fail===' \
    "$DESKTOP_VERIFY_TTY"
}

@test "KDE session: no polkit/idle probe is emitted" {
  printf 'plasma.desktop\n' > "$DESKTOP_VERIFY_STATE/order"
  printf 'KDE\n' > "$DESKTOP_VERIFY_STATE/tags"
  run "$PROBER"
  grep -q '===KDE-SESSION-OK===' "$DESKTOP_VERIFY_TTY"
  ! grep -q 'POLKIT\|IDLE\|CLIPBOARD' "$DESKTOP_VERIFY_TTY"
  grep -q '===SESSION-VERIFY-DONE===' "$DESKTOP_VERIFY_TTY"
}
