#!/usr/bin/env bats
# Tests for extras/desktop/hyprland/hyprland.sh (ADR 0062).
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed as
# executables in a temp bin dir prepended to PATH. Injectable seams:
#   WAYLAND_SESSIONS_DIR — session-override dir (default; written under ROOT)
#   ROOT                 — prefix for session override + aquamarine pin writes
#   STATE                — install-state.json for the resolved .gpu array
#
# The display manager is no longer this adapter's concern (ADR 0069) — it only
# writes the curated session files; a separate Display Manager Adapter owns the
# greeter.

# _write_command_stubs — pacman/systemctl/git stubs on STUB_BIN that log
# each call (git emulates a sparse-checkout of the Noctalia plugins), plus the
# pacman.conf the pacman stub reads.
_write_command_stubs() {
  # The pacman stub also records the [options] NoExtract lines live when
  # hyprland itself is installed, so a test can prove they precede it.
  cat > "$STUB_BIN/pacman" <<'PACMAN'
#!/usr/bin/env bash
echo "pacman $*" >> "$PACMAN_LOG"
case " $* " in
  *" hyprland "*) sed -n 's/^NoExtract/hyprland-noextract: &/p' \
                    "$ROOT/etc/pacman.conf" >> "$PACMAN_LOG" ;;
esac
PACMAN
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  # git stub emulating a successful sparse-checkout (same as niri-adapter.bats):
  # clone makes the target, sparse-checkout records subs, checkout fills each
  # with a v5 plugin.toml (id "noctalia/<sub>").
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
  _write_pacman_config
  export PATH="$STUB_BIN:$PATH"
}

# _write_pacman_config — the chroot pacman.conf the adapter amends (uwsm
# NoExtract, ADR 0158).
_write_pacman_config() {
  mkdir -p "$ROOT/etc"
  printf '[options]\nHoldPkg = pacman glibc\n\n[core]\n' > "$ROOT/etc/pacman.conf"
}

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  GIT_LOG="$TEST_DIR/git.log"
  ROOT="$TEST_DIR/root"
  SEED="$TEST_DIR/seed"
  STATE="$TEST_DIR/state.json"
  SESSION="$ROOT/usr/local/share/wayland-sessions/hyprland.desktop"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/hyprland/hyprland.sh"

  export PACMAN_LOG SYSTEMCTL_LOG GIT_LOG ROOT STATE
  export HYPR_SEED_ROOT="$SEED"
  # Default to "no battery" (desktop) so laptop plugin gating is deterministic;
  # battery is not exercised here.
  export HYPR_BAT_GLOB="$TEST_DIR/nobat/BAT*"

  _write_command_stubs

  # Curated-config source (ADR 0097, mirroring niri's ADR 0095): chroot.sh
  # stages the repo's single-source Noctalia-wired hyprland.lua PLUS the shared
  # config.toml + noctalia-* helpers here; the adapter seeds them into /etc/skel
  # under wayland_shell=noctalia.
  CURATED="$TEST_DIR/curated"
  mkdir -p "$CURATED/.config/hypr" "$CURATED/.config/noctalia" \
    "$CURATED/.local/bin"
  echo 'hypr-config'     > "$CURATED/.config/hypr/hyprland.lua"
  # Split config (ADR 0107): the entry manifest always ships beside a conf.d/
  # part-file tree — the seed copies it unconditionally.
  mkdir -p "$CURATED/.config/hypr/conf.d"
  echo 'environment' > "$CURATED/.config/hypr/conf.d/environment.lua"
  echo 'noctalia-config' > "$CURATED/.config/noctalia/config.toml"
  echo 'cycle'  > "$CURATED/.local/bin/noctalia-cycle-palette"
  echo 'enable' > "$CURATED/.local/bin/noctalia-enable-plugins"
  echo 'suspend' > "$CURATED/.local/bin/noctalia-idle-suspend"  # ADR 0100
  # pcmanfm-qt curated payload (ADR 0100): settings + right-click actions.
  mkdir -p "$CURATED/.config/pcmanfm-qt/lxqt" \
    "$CURATED/.local/share/file-manager/actions"
  echo 'pcmanfm-settings' > "$CURATED/.config/pcmanfm-qt/lxqt/settings.conf"
  echo 'kitty-action' \
    > "$CURATED/.local/share/file-manager/actions/open-in-kitty.desktop"
  # qt6ct.conf — App Theming Bridge Qt half (ADR 0108): chroot.sh stages it into
  # the curated dir, so the preset seeds it; the mock must provide it.
  mkdir -p "$CURATED/.config/qt6ct"
  echo 'qt6ct-conf' > "$CURATED/.config/qt6ct/qt6ct.conf"
  export HYPR_CURATED_DIR="$CURATED"
}

teardown() { rm -rf "$TEST_DIR"; }

# run_hypr <desktop> [wayland_shell]
run_hypr() {
  local desktops="$1" shell="${2:-}"
  if [[ -n "$shell" ]]; then
    run env ENVIRONMENT_DESKTOP="$desktops" ENVIRONMENT_WAYLAND_SHELL="$shell" \
      bash "$ADAPTER"
  else
    run env ENVIRONMENT_DESKTOP="$desktops" bash "$ADAPTER"
  fi
}

# ── core packages ───────────────────────────────────────────────────────────

@test "installs exactly the working-session core" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  local package
  for package in hyprland seatd xdg-desktop-portal-hyprland \
           xdg-desktop-portal-gtk wl-clipboard; do
    grep -q "$package" "$PACMAN_LOG" || { echo "core missing: $package"; return 1; }
  done
  # Noctalia's own agent serves polkit (ADR 0100); no second agent.
  ! grep -q polkit-kde-agent "$PACMAN_LOG"
}

# uwsm is not installed (ADR 0070): its session deadlocks on first-boot login
# under impermanence, so the uwsm session is dropped and the package with it.
@test "does not install uwsm" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  ! grep "^pacman " "$PACMAN_LOG" | grep -qw "uwsm"
}

# aquamarine can't get DRM master via logind on some hardware (atomic KMS
# commit → "Permission denied", compositor retry-loops → black screen); it uses
# seatd instead, which must be enabled (ADR 0068).
@test "enables seatd so aquamarine gets DRM master" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

@test "enables seatd on a KDE co-install too" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  grep -q "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

# Core-only for apps (ADR 0021/0062) — no launcher, bar, screenshot tool, etc.
# hyprlock is dropped too (ADR 0097): Noctalia locks natively via
# ext-session-lock, so the lock key drives the shell, not a separate locker.
@test "installs no companion packages, no qt6ct, no hyprlock" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  local package
  for package in waybar dunst fuzzel rofi-wayland wofi alacritty hyprlock \
           hypridle hyprpaper grim slurp nwg-look qt6ct qt6ct-kde; do
    ! grep -q "$package" "$PACMAN_LOG" || { echo "unexpected package: $package"; return 1; }
  done
}

# hyprlock is no longer in core (ADR 0097, superseding 0096) — Noctalia is the
# lock, on both compositors.
@test "does not install hyprlock even under noctalia (ADR 0097)" {
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  ! grep -qw "hyprlock" "$PACMAN_LOG"
}

# ── Noctalia preset seeded via /etc/skel (ADR 0097) ──────────────────────────
# Under wayland_shell=noctalia the shared preset seeds the SAME payload as niri
# — the Noctalia-wired hyprland.lua, the byte-identical config.toml, and the
# noctalia-* helpers — all staged into HYPR_CURATED_DIR by chroot.sh, copied
# verbatim (no heredoc, no drift).
@test "noctalia: seeds hyprland.lua + shared config.toml + helpers to skel" {
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  [ -f "$SEED/etc/skel/.config/hypr/hyprland.lua" ]
  grep -qx hypr-config "$SEED/etc/skel/.config/hypr/hyprland.lua"
  [ -f "$SEED/etc/skel/.config/noctalia/config.toml" ]
  grep -qx noctalia-config "$SEED/etc/skel/.config/noctalia/config.toml"
  [ -x "$SEED/etc/skel/.local/bin/noctalia-cycle-palette" ]
  [ -x "$SEED/etc/skel/.local/bin/noctalia-enable-plugins" ]
  # Idle-suspend gate helper (ADR 0100)
  [ -x "$SEED/etc/skel/.local/bin/noctalia-idle-suspend" ]
  # GTK/XWayland cursor fallback (ADR 0098)
  grep -q "Inherits=Bibata-Modern-Ice" \
    "$SEED/etc/skel/.icons/default/index.theme"
  # Shared file manager settings + custom actions (ADR 0100)
  [ -f "$SEED/etc/skel/.config/pcmanfm-qt/lxqt/settings.conf" ]
  [ -f "$SEED/etc/skel/.local/share/file-manager/actions/open-in-kitty.desktop" ]
}

@test "noctalia: installs the Noctalia preset packages" {
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  local package
  for package in noctalia kitty brightnessctl playerctl pcmanfm-qt; do
    grep -q "$package" "$PACMAN_LOG" || { echo "preset missing: $package"; return 1; }
  done
}

@test "noctalia: vendors the shared core plus the hypr-* slice, never niri-*" {
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  grep -q "sparse-checkout set keymap" "$GIT_LOG"
  grep -q "sparse-checkout set arch-updater" "$GIT_LOG"
  # the Hyprland slice (ADR 0097)
  grep -q "sparse-checkout set hypr-layout-switcher" "$GIT_LOG"
  grep -q "sparse-checkout set hypr-submap" "$GIT_LOG"
  grep -q "sparse-checkout set hypr-screen-mirror" "$GIT_LOG"
  # the niri slice is never vendored on Hyprland
  ! grep -q "sparse-checkout set niri-" "$GIT_LOG"
}

@test "noctalia: installs the hypr slice tool deps (socat)" {
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  grep -qw "socat" "$PACMAN_LOG"
}

@test "noctalia: warns but does not abort when the curated dir is absent" {
  run env HYPR_CURATED_DIR="$TEST_DIR/none" ENVIRONMENT_DESKTOP="hyprland" \
    ENVIRONMENT_WAYLAND_SHELL="noctalia" HYPR_BAT_GLOB="$TEST_DIR/nobat/BAT*" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.config/hypr/hyprland.lua" ]
}

# Split config (ADR 0107): the conf.d/ part-file tree beside the entry manifest
# is seeded whole to /etc/skel next to it.
@test "noctalia: seeds the conf.d/ part-file tree when present (ADR 0107)" {
  mkdir -p "$CURATED/.config/hypr/conf.d"
  echo 'keybinds'    > "$CURATED/.config/hypr/conf.d/keybinds.lua"
  echo 'environment' > "$CURATED/.config/hypr/conf.d/environment.lua"
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  [ -f "$SEED/etc/skel/.config/hypr/hyprland.lua" ]
  [ -f "$SEED/etc/skel/.config/hypr/conf.d/keybinds.lua" ]
  [ -f "$SEED/etc/skel/.config/hypr/conf.d/environment.lua" ]
}

# VM software-cursor override (ADR 0106) relocates onto the split tree (ADR
# 0107): with a conf.d/ present it appends to conf.d/environment.lua, not the
# entry manifest.
@test "noctalia: VM cursor override lands in conf.d/environment when split" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/systemd-detect-virt"
  chmod +x "$STUB_BIN/systemd-detect-virt"
  mkdir -p "$CURATED/.config/hypr/conf.d"
  echo 'environment' > "$CURATED/.config/hypr/conf.d/environment.lua"
  run_hypr "hyprland" noctalia
  [ "$status" -eq 0 ]
  grep -q 'no_hardware_cursors' \
    "$SEED/etc/skel/.config/hypr/conf.d/environment.lua"
  run grep -q 'no_hardware_cursors' "$SEED/etc/skel/.config/hypr/hyprland.lua"
  [ "$status" -ne 0 ]
}

# ── bare Hyprland seeds nothing (wayland_shell=none / unset, ADR 0097) ────────
@test "none: seeds no config and installs no Noctalia (truly bare)" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.config/hypr/hyprland.lua" ]
  [ ! -e "$SEED/etc/skel/.config/noctalia/config.toml" ]
  ! grep -qw "noctalia" "$PACMAN_LOG"
  [ ! -f "$GIT_LOG" ]
}

# Stock (pure) Hyprland seeds nothing even if wayland_shell says noctalia — the
# ENVIRONMENT_STOCK guard wins (ADR 0112).
@test "stock: seeds nothing despite wayland_shell=noctalia" {
  run env ENVIRONMENT_DESKTOP="hyprland" ENVIRONMENT_WAYLAND_SHELL="noctalia" \
    ENVIRONMENT_STOCK="true" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -e "$SEED/etc/skel/.config/hypr/hyprland.lua" ]
  ! grep -qw "noctalia" "$PACMAN_LOG"
}

# ── session override (start-hyprland, DRM backend) ───────────────────────────

@test "ships a wayland-session override that launches start-hyprland on DRM" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ -f "$SESSION" ]
  # start-hyprland (Hyprland 0.53+ recommended, kills the red warning; the old
  # crash was the DRM-master issue, fixed by seatd), WAYLAND_DISPLAY/DISPLAY
  # unset so aquamarine uses the DRM backend not the nested one (ADR 0067/0068).
  grep -qx 'Exec=env -u WAYLAND_DISPLAY -u DISPLAY start-hyprland' "$SESSION"
}

@test "does not offer a uwsm session (dropped, ADR 0070)" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/usr/local/share/wayland-sessions/hyprland-uwsm.desktop" ]
}

# noctalia-greeter scans /usr/share unconditionally (ADR 0158), so the packaged
# uwsm session must never reach disk — not just stay out of the curated dir.
@test "keeps the packaged uwsm session off disk under every greeter" {
  local uwsm=usr/share/wayland-sessions/hyprland-uwsm.desktop
  mkdir -p "$ROOT/${uwsm%/*}"
  touch "$ROOT/$uwsm"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/$uwsm" ]
  # NoExtract lands in [options] before hyprland is installed.
  grep -qx "hyprland-noextract: NoExtract = $uwsm" "$PACMAN_LOG"
}

@test "the uwsm NoExtract is written once across re-runs" {
  run_hypr "hyprland"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^NoExtract = .*hyprland-uwsm' "$ROOT/etc/pacman.conf")" -eq 1 ]
}

# ── display manager relinquished to the DM adapter (ADR 0069) ────────────────
# The Hyprland adapter no longer installs or enables any greeter; it only writes
# the curated session files the selected Display Manager Adapter offers.

@test "Hyprland adapter installs no greeter and enables no display manager" {
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  ! grep -q "greetd" "$PACMAN_LOG"
  ! grep -q "enable greetd" "$SYSTEMCTL_LOG"
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
}

@test "KDE co-installed: curated dir offers Plasma + start-hyprland" {
  run_hypr "kde hyprland"
  [ "$status" -eq 0 ]
  # The /usr/share duplicates never reach the picker — the greeter is pointed
  # at this curated dir (greetd via --sessions, sddm via pinned SessionDir).
  [ -L "$ROOT/usr/local/share/wayland-sessions/plasma.desktop" ]
  [ ! -e "$ROOT/usr/local/share/wayland-sessions/hyprland-uwsm.desktop" ]
  [ -f "$SESSION" ]
}

@test "KDE co-installed: Plasma session is curated regardless of DE order" {
  run_hypr "hyprland kde"
  [ "$status" -eq 0 ]
  [ -L "$ROOT/usr/local/share/wayland-sessions/plasma.desktop" ]
}

# ── aquamarine DRM pinning: hybrid amd+nvidia only ───────────────────────────

@test "hybrid amd+nvidia: writes the udev rule and AQ_DRM_DEVICES pin" {
  printf '{"gpu":["amd","nvidia"]}\n' > "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
  grep -q 'AQ_DRM_DEVICES=/dev/dri/aq-igpu' "$ROOT/etc/environment"
}

@test "single-vendor GPU: neither udev rule nor pin is written" {
  printf '{"gpu":["amd"]}\n' > "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
  [ ! -f "$ROOT/etc/environment" ]
}

@test "no install-state present: pin is skipped without error" {
  rm -f "$STATE"
  run_hypr "hyprland"
  [ "$status" -eq 0 ]
  [ ! -f "$ROOT/usr/lib/udev/rules.d/60-aq-drm-devices.rules" ]
}
