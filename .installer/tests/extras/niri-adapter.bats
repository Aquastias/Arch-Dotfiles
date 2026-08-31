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
  # Default to "no battery" (desktop) so battery gating is deterministic
  # regardless of the machine running the tests; battery tests override this.
  export NIRI_BAT_GLOB="$TEST_DIR/nobat/BAT*"

  # pacman stub: `-Qq <pkg>` exits 0 only if <pkg> is in NIRI_QQ (the "installed"
  # set, empty by default) so the bitwarden nodejs check is testable; else logs.
  cat > "$STUB_BIN/pacman" <<'PAC'
#!/usr/bin/env bash
if [[ "$1" == "-Qq" ]]; then
  shift
  [[ $# -eq 0 ]] && { printf '%s\n' ${NIRI_QQ:-}; exit 0; }
  for p in "$@"; do printf '%s\n' ${NIRI_QQ:-} | grep -qx "$p" || exit 1; done
  exit 0
fi
echo "pacman $*" >> "$PACMAN_LOG"
PAC
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  # git stub emulating a successful sparse-checkout: `clone` makes the target
  # dir, `sparse-checkout set <subs>` records the requested subdirs, and
  # `checkout` populates each with a v5 plugin.toml (id "noctalia/<sub>").
  cat > "$STUB_BIN/git" <<'GIT'
#!/usr/bin/env bash
echo "git $*" >> "$GIT_LOG"
case "$1" in
  clone) mkdir -p "${@: -1}" ;;
  -C)
    dir="$2"; op="$3"; shift 3
    case "$op" in
      sparse-checkout) shift; printf '%s\n' "$@" >> "$dir/.subs" ;;
      checkout) [[ -f "$dir/.subs" ]] && while read -r s; do
                  mkdir -p "$dir/$s"
                  printf 'id = "noctalia/%s"\nname = "%s"\n' "$s" "$s" \
                    > "$dir/$s/plugin.toml"
                done < "$dir/.subs" ;;
    esac ;;
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

# The niri glue (config.kdl), the Noctalia look (config.toml), the palette cycler
# and the plugin-enable one-shot are stow-owned dotfiles now (ADR 0094) — the
# adapter seeds none of them, only the vendored plugin folders below.
@test "noctalia seeds no config.toml, config.kdl, or helper scripts" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.config/niri/config.kdl" ]
  [ ! -e "$SEED/etc/skel/.config/noctalia/config.toml" ]
  [ ! -e "$SEED/etc/skel/.local/bin/noctalia-cycle-palette" ]
  [ ! -e "$SEED/etc/skel/.local/bin/noctalia-enable-plugins" ]
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

# ── Enriched community plugin set (ADR 0093/0094) ────────────────────────────

@test "noctalia vendors the curated plugin set with tool deps" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  local pl
  for pl in keymap screen-toolkit procmon udiskie ssh-launcher \
            wallpaper-switcher portctl game-launcher hotspot bookmarks \
            llamanager dns-switcher; do
    [ -f "$base/$pl/plugin.toml" ] || { echo "not vendored: $pl"; return 1; }
  done
  # official-repo tool deps installed
  grep -qw "smartmontools" "$PACMAN_LOG"   # drive-health
  grep -qw "wl-mirror" "$PACMAN_LOG"        # wl-screen-mirror
  grep -qw "fzf" "$PACMAN_LOG"             # file-search
  grep -qw "ollama" "$PACMAN_LOG"          # llamanager
  grep -qw "iw" "$PACMAN_LOG"              # hotspot
  grep -qw "bind" "$PACMAN_LOG"            # dns-switcher
  # vendored at the pinned community ref
  grep -q "caed21ab081948435cd770d2e954c99b8bbb72cf" "$GIT_LOG"
}

@test "dropped plugins are never vendored (ADR 0093/0094)" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  local pl
  for pl in bitwarden mini-docker system-updater system-monitor color_picker \
            screen_recorder config-swap calculator battery-threshold; do
    [ ! -e "$base/$pl" ] || { echo "unexpectedly vendored: $pl"; return 1; }
  done
  # the dropped bitwarden CLI backend and mini-docker's docker never install
  ! grep -qw "bitwarden-cli" "$PACMAN_LOG"
  ! grep -qw "docker" "$PACMAN_LOG"
}

@test "a plugin toggled off is not vendored and its unique dep is skipped" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"llamanager":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.local/share/noctalia/plugins/llamanager" ]
  ! grep -qw "ollama" "$PACMAN_LOG"
}

@test "a plugin toggled on is vendored and its unique dep installs" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"llamanager":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  [ -f "$SEED/etc/skel/.local/share/noctalia/plugins/llamanager/plugin.toml" ]
  grep -qw "ollama" "$PACMAN_LOG"
}

@test "all plugin bools off recovers the lean shell (base only)" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"cava":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  [ ! -d "$base" ] || [ -z "$(ls -A "$base")" ]
  grep -qw "noctalia" "$PACMAN_LOG"
}

# ── Laptop-gated battery pair (ADR 0093) ─────────────────────────────────────

@test "battery present (laptop): the battery pair is vendored with upower" {
  mkdir -p "$TEST_DIR/bat/BAT0"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_BAT_GLOB="$TEST_DIR/bat/BAT*"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  [ -f "$base/battery-power-management/plugin.toml" ]
  [ -f "$base/battery-widget/plugin.toml" ]
  grep -qw "upower" "$PACMAN_LOG"
}

@test "no battery (desktop): the battery pair is absent, upower not installed" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"   # setup glob matches no BAT
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  [ ! -e "$base/battery-power-management" ]
  [ ! -e "$base/battery-widget" ]
  ! grep -qw "upower" "$PACMAN_LOG"
}

@test "laptop=true forces the battery pair even without a battery" {
  local nj="$TEST_DIR/nj.jsonc"
  printf '{"laptop":true,"battery-widget":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  local p="$SEED/etc/skel/.local/share/noctalia/plugins/battery-widget"
  [ -f "$p/plugin.toml" ]
}

@test "laptop=false forces the battery pair off even with a battery" {
  mkdir -p "$TEST_DIR/bat/BAT0"
  local nj="$TEST_DIR/nj.jsonc"
  printf '{"laptop":false,"battery-widget":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj" \
    NIRI_BAT_GLOB="$TEST_DIR/bat/BAT*"
  [ "$status" -eq 0 ]
  local p="$SEED/etc/skel/.local/share/noctalia/plugins/battery-widget"
  [ ! -e "$p" ]
}

# ── Offline resilience (ADR 0093) ────────────────────────────────────────────

@test "a plugin fetch failure warns but never aborts the install" {
  # a git that always fails (network down) — no plugin vendored, install ok
  printf '#!/usr/bin/env bash\necho "git $*" >> "$GIT_LOG"\nexit 1\n' \
    > "$STUB_BIN/git"
  chmod +x "$STUB_BIN/git"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  grep -qw "noctalia" "$PACMAN_LOG"
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  [ ! -d "$base" ] || [ -z "$(ls -A "$base")" ]
}
