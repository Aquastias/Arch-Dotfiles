#!/usr/bin/env bats
# Tests for extras/desktop/niri/niri.sh (ADR 0090).
#
# Strategy: run the adapter as a subprocess with pacman, systemctl and git
# stubbed as executables in a temp bin dir prepended to PATH. Injectable seams:
#   NIRI_SEED_ROOT — prefix for /etc/skel seeds (default /; tests → tmpdir)
#   ENVIRONMENT_NIRI_SHELL — noctalia | none (the shell preset selector)
#   NIRI_JSON      — install-niri.jsonc override (preset component bools)
#
# niri is core-only like Hyprland but leaner: the niri package ships its own
# session file and pulls seatd, so the adapter writes no session file and no
# DRM pin. The display manager is not its concern (ADR 0069).

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  GIT_LOG="$TEST_DIR/git.log"
  SEED="$TEST_DIR/seed"
  ROOT="$TEST_DIR/root"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/niri/niri.sh"

  export PACMAN_LOG SYSTEMCTL_LOG GIT_LOG ROOT
  export NIRI_SEED_ROOT="$SEED"

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  # git stub emulating a successful sparse-checkout: `clone` makes the target
  # dir, `-C <dir> checkout` populates a bitwarden/ tree with a manifest.
  cat > "$STUB_BIN/git" <<'GIT'
#!/usr/bin/env bash
echo "git $*" >> "$GIT_LOG"
case "$1" in
  clone) mkdir -p "${@: -1}" ;;
  -C)    [[ "$3" == checkout ]] && {
           mkdir -p "$2/bitwarden"
           printf '{"id":"bitwarden"}' > "$2/bitwarden/manifest.json"; } ;;
esac
exit 0
GIT
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl" "$STUB_BIN/git"

  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

run_niri() { run env ENVIRONMENT_DESKTOP="niri" "$@" bash "$ADAPTER"; }

# ── core packages ───────────────────────────────────────────────────────────

@test "installs exactly the working-session core" {
  run_niri
  [ "$status" -eq 0 ]
  local p
  for p in niri seatd xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
           polkit-kde-agent wl-clipboard; do
    grep -q "$p" "$PACMAN_LOG" || { echo "core missing: $p"; return 1; }
  done
}

@test "enables seatd so niri gets DRM master" {
  run_niri
  [ "$status" -eq 0 ]
  grep -q "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

# niri ships its own /usr/share/wayland-sessions/niri.desktop; the adapter writes
# no session CONTENT, but curates the packaged one into the shared /usr/local dir
# (symlink) so a greeter reading only that dir (greetd on a niri+Hyprland
# co-install) still offers niri.
@test "curates the packaged niri session into the shared /usr/local dir" {
  run_niri
  [ "$status" -eq 0 ]
  local s="$ROOT/usr/local/share/wayland-sessions/niri.desktop"
  [ -L "$s" ]
  [ "$(readlink "$s")" = "/usr/share/wayland-sessions/niri.desktop" ]
}

@test "installs no greeter and enables no display manager (ADR 0069)" {
  run_niri
  [ "$status" -eq 0 ]
  ! grep -q "greetd" "$PACMAN_LOG"
  ! grep -q "sddm" "$PACMAN_LOG"
  ! grep -q "enable greetd" "$SYSTEMCTL_LOG"
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
}

# ── bare niri seeds nothing (niri_shell=none) ────────────────────────────────

@test "niri_shell=none installs only the core and seeds nothing" {
  run_niri ENVIRONMENT_NIRI_SHELL="none"
  [ "$status" -eq 0 ]
  ! grep -q "noctalia" "$PACMAN_LOG"
  ! grep -q "kitty" "$PACMAN_LOG"
  [ ! -e "$SEED/etc/skel/.config/niri/config.kdl" ]
}

# ── Noctalia work preset (niri_shell=noctalia) ───────────────────────────────

@test "niri_shell=noctalia installs the Noctalia work preset" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local p
  for p in noctalia kitty brightnessctl; do
    grep -q "$p" "$PACMAN_LOG" || { echo "preset missing: $p"; return 1; }
  done
}

@test "niri_shell=noctalia seeds the /etc/skel niri config glue" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local kdl="$SEED/etc/skel/.config/niri/config.kdl"
  [ -f "$kdl" ]
  grep -q 'spawn-at-startup "noctalia"' "$kdl"
  grep -q 'kitty' "$kdl"
}

@test "cava/cliphist install only when toggled on in install-niri.jsonc" {
  local nj="$TEST_DIR/nj.jsonc"
  printf '{"cava":true,"cliphist":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  grep -q "cava" "$PACMAN_LOG"
  grep -q "cliphist" "$PACMAN_LOG"
}

@test "cava/cliphist stay out when toggled off" {
  local nj="$TEST_DIR/nj.jsonc"
  printf '{"cava":false,"cliphist":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  ! grep -qw "cava" "$PACMAN_LOG"
  ! grep -qw "cliphist" "$PACMAN_LOG"
}

# ── Bitwarden plugin (ADR 0090) ──────────────────────────────────────────────

@test "bitwarden on: installs the cli, seeds+registers the plugin at the pin" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  grep -q "bitwarden-cli" "$PACMAN_LOG"
  [ -f "$SEED/etc/skel/.config/noctalia/plugins/bitwarden/manifest.json" ]
  local pj="$SEED/etc/skel/.config/noctalia/plugins.json"
  [ "$(jq -r '.bitwarden.enabled' "$pj")" = "true" ]
  grep -q "ea6dfe3fae4d4a755dd05390548b04066250ffe9" "$GIT_LOG"
}

@test "bitwarden off: no cli, no plugin, no git fetch" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  ! grep -q "bitwarden-cli" "$PACMAN_LOG"
  [ ! -e "$SEED/etc/skel/.config/noctalia/plugins/bitwarden" ]
  [ ! -f "$GIT_LOG" ]
}

@test "bitwarden offline: fetch fails, install succeeds, cli still installed" {
  # a git that always fails (network down)
  printf '#!/usr/bin/env bash\necho "git $*" >> "$GIT_LOG"\nexit 1\n' \
    > "$STUB_BIN/git"
  chmod +x "$STUB_BIN/git"
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  grep -q "bitwarden-cli" "$PACMAN_LOG"
  [ ! -e "$SEED/etc/skel/.config/noctalia/plugins/bitwarden" ]
}
