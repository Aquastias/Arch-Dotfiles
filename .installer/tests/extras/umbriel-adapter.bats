#!/usr/bin/env bats
# Tests for extras/desktop/umbriel/umbriel.sh (ADR 0159).
#
# Strategy: run the adapter as a subprocess with pacman, systemctl, git and
# systemd-detect-virt stubbed as executables in a temp bin dir prepended to
# PATH; session writes go under a temp ROOT, skel seeds under UMBRIEL_SEED_ROOT.
# Umbriel itself is AUR-only (the adapter's install-umbriel.jsonc `aur` list,
# installed later by the Profiles Runner's paru pass), so the adapter installs
# only its repo core and curates a session entry that resolves once the package
# lands. The Noctalia work preset is the shared module (ADR 0097).

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  ROOT="$TEST_DIR/root"
  SEED="$TEST_DIR/seed"
  mkdir -p "$STUB_BIN" "$ROOT"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  WAYLAND_SESSIONS_DIR="/usr/local/share/wayland-sessions"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/umbriel/umbriel.sh"
  AUR_LIST="$BATS_TEST_DIRNAME/../../extras/desktop/umbriel"
  AUR_LIST+="/install-umbriel.jsonc"
  export PACMAN_LOG SYSTEMCTL_LOG WAYLAND_SESSIONS_DIR ROOT
  export UMBRIEL_SEED_ROOT="$SEED"
  export UMBRIEL_BAT_GLOB="$TEST_DIR/nobat/BAT*"

  # pacman: `-Qq` reports nothing installed; every other call is logged.
  cat > "$STUB_BIN/pacman" <<'PAC'
#!/usr/bin/env bash
[[ "$1" == "-Qq" ]] && exit 1
echo "pacman $*" >> "$PACMAN_LOG"
PAC
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  # git: a successful sparse-checkout of the Noctalia plugins (as niri's test),
  # so the preset vendors without its offline retry sleeps.
  cat > "$STUB_BIN/git" <<'GIT'
#!/usr/bin/env bash
case "$1" in
  clone) mkdir -p "${@: -1}" ;;
  -C)
    dir="$2"; op="$3"; shift 3
    case "$op" in
      sparse-checkout) shift; printf '%s\n' "$@" >> "$dir/.subs" ;;
      checkout) [[ -f "$dir/.subs" ]] && while read -r s; do
                  mkdir -p "$dir/$s"
                  printf 'id = "noctalia/%s"\n' "$s" > "$dir/$s/plugin.toml"
                done < "$dir/.subs" ;;
    esac ;;
esac
exit 0
GIT
  # bare metal by default; VM tests flip it
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_BIN/systemd-detect-virt"
  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH"
  CURATED_SESSIONS="$ROOT$WAYLAND_SESSIONS_DIR"

  # Curated-config source (ADR 0095): chroot.sh stages the repo's dotfiles here.
  CURATED="$TEST_DIR/curated"
  mkdir -p "$CURATED/.config/umbriel/conf.d" "$CURATED/.config/noctalia" \
    "$CURATED/.config/qt6ct" "$CURATED/.local/bin"
  echo 'umbriel-config' > "$CURATED/.config/umbriel/config.toml"
  echo '[environment]'  > "$CURATED/.config/umbriel/conf.d/environment.toml"
  echo 'noctalia-config' > "$CURATED/.config/noctalia/config.toml"
  echo 'qt6ct-conf' > "$CURATED/.config/qt6ct/qt6ct.conf"
  echo 'enable' > "$CURATED/.local/bin/noctalia-enable-plugins"
  # The rest of the shared Noctalia payload the preset seeds (as niri's test).
  mkdir -p "$CURATED/.config/pcmanfm-qt/lxqt" \
    "$CURATED/.local/share/file-manager/actions"
  echo 'pcmanfm-settings' > "$CURATED/.config/pcmanfm-qt/lxqt/settings.conf"
  echo 'kitty-action' \
    > "$CURATED/.local/share/file-manager/actions/open-in-kitty.desktop"
  export UMBRIEL_CURATED_DIR="$CURATED"
  SKEL="$SEED/etc/skel"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "installs exactly the repo session core" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "pacman -S --noconfirm --needed seatd xdg-desktop-portal-gtk \
wl-clipboard" "$PACMAN_LOG"
  [ "$(grep -c '^pacman ' "$PACMAN_LOG")" -eq 1 ]
}

@test "enables seatd so Umbriel gets DRM master (ADR 0068)" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -qx "systemctl enable seatd" "$SYSTEMCTL_LOG"
}

@test "declares the compositor and its portal for the vetted paru pass" {
  run bash -c "sed 's://.*::' '$AUR_LIST' | jq -r '.aur[] | keys[]'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx umbriel-git
  echo "$output" | grep -qx xdg-desktop-portal-umbriel-git
}

@test "curates the packaged Umbriel session into the shared /usr/local dir" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(readlink "$CURATED_SESSIONS/umbriel.desktop")" == \
    /usr/share/wayland-sessions/umbriel.desktop ]
}

@test "KDE co-installed: the curated dir also offers Plasma" {
  ENVIRONMENT_DESKTOP="umbriel kde" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(readlink "$CURATED_SESSIONS/plasma.desktop")" == \
    /usr/share/wayland-sessions/plasma.desktop ]
}

@test "Umbriel alone: no Plasma session in the curated dir" {
  ENVIRONMENT_DESKTOP="umbriel" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -L "$CURATED_SESSIONS/plasma.desktop" ]
}

@test "installs no greeter and enables no display manager (ADR 0069)" {
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -Eq "greetd|sddm" "$PACMAN_LOG"
  ! grep -Eq "greetd|sddm" "$SYSTEMCTL_LOG"
}

# ── Noctalia work preset (wayland_shell=noctalia, ADR 0097) ─────────────────

@test "wayland_shell=noctalia installs the shared Noctalia work preset" {
  ENVIRONMENT_WAYLAND_SHELL=noctalia run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "noctalia" "$PACMAN_LOG"
  grep -q "kitty" "$PACMAN_LOG"
}

@test "noctalia seeds the curated Umbriel config + conf.d/ to /etc/skel" {
  ENVIRONMENT_WAYLAND_SHELL=noctalia run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(cat "$SKEL/.config/umbriel/config.toml")" == umbriel-config ]
  [ -f "$SKEL/.config/umbriel/conf.d/environment.toml" ]
  [ -f "$SKEL/.config/noctalia/config.toml" ]
}

@test "wayland_shell=none installs only the core and seeds nothing" {
  ENVIRONMENT_WAYLAND_SHELL=none run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "noctalia" "$PACMAN_LOG"
  [ ! -e "$SKEL/.config/umbriel/config.toml" ]
}

@test "stock Umbriel seeds nothing despite wayland_shell=noctalia (ADR 0112)" {
  ENVIRONMENT_WAYLAND_SHELL=noctalia ENVIRONMENT_STOCK=true \
    run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "noctalia" "$PACMAN_LOG"
  [ ! -e "$SKEL/.config/umbriel/config.toml" ]
}

# VM software cursor (ADR 0106): appended to the seeded conf.d/environment.toml
# as its own table, which Umbriel merges with input.toml's [input.cursor].
@test "in a VM: the seeded config turns Umbriel's hardware cursor off" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/systemd-detect-virt"
  ENVIRONMENT_WAYLAND_SHELL=noctalia run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -B1 -x 'hardware_cursor = false' \
    "$SKEL/.config/umbriel/conf.d/environment.toml" \
    | grep -qx '\[input.cursor\]'
  ! grep -q hardware_cursor "$SKEL/.config/umbriel/config.toml"
}
