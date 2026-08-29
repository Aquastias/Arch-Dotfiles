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

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
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

# ── Rosé Pine palette default (ADR 0093) ─────────────────────────────────────

@test "niri_shell=noctalia seeds the Rosé Pine palette default" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  grep -q '^\[theme\]' "$ct"
  grep -q 'source = "builtin"' "$ct"
  grep -q 'builtin = "Rosé Pine"' "$ct"
}

@test "niri_shell=none seeds no noctalia config.toml" {
  run_niri ENVIRONMENT_NIRI_SHELL="none"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.config/noctalia/config.toml" ]
}

# ── Enriched community plugin set (ADR 0093) ─────────────────────────────────

@test "noctalia vendors+enables the curated plugin set with tool deps" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  local pl
  for pl in keymap screen-toolkit procmon udiskie ssh-launcher \
            wallpaper-switcher; do
    [ -f "$base/$pl/plugin.toml" ] || { echo "not vendored: $pl"; return 1; }
  done
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  grep -q '"noctalia/keymap"' "$ct"
  grep -q '"noctalia/screen-toolkit"' "$ct"
  # official-repo tool deps installed
  grep -qw "smartmontools" "$PACMAN_LOG"   # drive-health
  grep -qw "wl-mirror" "$PACMAN_LOG"        # wl-screen-mirror
  grep -qw "docker" "$PACMAN_LOG"           # mini-docker
  grep -qw "fzf" "$PACMAN_LOG"              # file-search
}

@test "dropped plugins are never vendored" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  local pl
  for pl in system-monitor color_picker screen_recorder config-swap \
            calculator battery-threshold; do
    [ ! -e "$base/$pl" ] || { echo "unexpectedly vendored: $pl"; return 1; }
  done
}

@test "a plugin toggled off is not vendored and its unique dep is skipped" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"mini-docker":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.local/share/noctalia/plugins/mini-docker" ]
  ! grep -qw "docker" "$PACMAN_LOG"
}

@test "a plugin toggled on is vendored and its unique dep installs" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"mini-docker":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  [ -f "$SEED/etc/skel/.local/share/noctalia/plugins/mini-docker/plugin.toml" ]
  grep -qw "docker" "$PACMAN_LOG"
  grep -q '"noctalia/mini-docker"' \
    "$SEED/etc/skel/.config/noctalia/config.toml"
}

@test "all plugin bools off recovers the lean shell (base + palette only)" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  local base="$SEED/etc/skel/.local/share/noctalia/plugins"
  [ ! -d "$base" ] || [ -z "$(ls -A "$base")" ]
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  grep -q 'enabled = \[\]' "$ct"
  grep -q 'builtin = "Rosé Pine"' "$ct"
  grep -qw "noctalia" "$PACMAN_LOG"
}

# ── Palette-cycle tile (ADR 0093) ────────────────────────────────────────────

@test "custom-shortcut on: seeds the palette cycler + tile settings" {
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia"   # custom-shortcut default on
  [ "$status" -eq 0 ]
  local sc="$SEED/etc/skel/.local/bin/noctalia-cycle-palette"
  [ -x "$sc" ]
  grep -q 'colorScheme set' "$sc"
  grep -q 'Rosé Pine' "$sc"
  grep -q 'Nord' "$sc"
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  grep -q 'yocraft/custom-shortcut' "$ct"
  grep -q 'onclick_cmd' "$ct"
  # the built-in Control Center layout is left untouched
  ! grep -q 'control_center.shortcuts' "$ct"
}

@test "custom-shortcut off: no palette cycler or tile settings" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"custom-shortcut":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.local/bin/noctalia-cycle-palette" ]
  ! grep -q 'onclick_cmd' "$SEED/etc/skel/.config/noctalia/config.toml"
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

# ── Bitwarden plugin (ADR 0090) ──────────────────────────────────────────────

@test "bitwarden on: installs the cli, vendors+enables the plugin at the pin" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":true}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  grep -q "bitwarden-cli" "$PACMAN_LOG"
  # v5 layout: plugin folder in the DATA dir, id enabled in config.toml
  [ -f "$SEED/etc/skel/.local/share/noctalia/plugins/bitwarden/plugin.toml" ]
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  grep -q 'auto_update = "none"' "$ct"
  grep -q '"noctalia/bitwarden"' "$ct"
  grep -q "8cb833c3e2502f57e49d34fa64386b4d66794b77" "$GIT_LOG"
  # the dead v4 artifacts are not produced
  [ ! -e "$SEED/etc/skel/.config/noctalia/plugins.json" ]
  [ ! -e "$SEED/etc/skel/.config/noctalia/plugins/bitwarden" ]
  [ ! -e "$SEED/etc/skel/.local/state/noctalia/settings.toml" ]
}

@test "bitwarden off: no cli, no plugin, no git; config.toml empty enabled" {
  local nj="$TEST_DIR/nj.jsonc"; printf '{"bitwarden":false}\n' > "$nj"
  run_niri ENVIRONMENT_NIRI_SHELL="noctalia" NIRI_JSON="$nj"
  [ "$status" -eq 0 ]
  ! grep -q "bitwarden-cli" "$PACMAN_LOG"
  [ ! -e "$SEED/etc/skel/.local/share/noctalia/plugins/bitwarden" ]
  [ ! -f "$GIT_LOG" ]
  local ct="$SEED/etc/skel/.config/noctalia/config.toml"
  [ -f "$ct" ]
  grep -q 'enabled = \[\]' "$ct"
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
  [ ! -e "$SEED/etc/skel/.local/share/noctalia/plugins/bitwarden" ]
  # config.toml still written, bitwarden not in the enabled list
  grep -q 'enabled = \[\]' "$SEED/etc/skel/.config/noctalia/config.toml"
}
