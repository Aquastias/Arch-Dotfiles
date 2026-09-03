#!/usr/bin/env bats
# Seam B (ADR 0094/0095): the curated Noctalia/niri config is the single-source
# stow-ready payload at the repo root — the operator may stow it, and the niri
# adapter seeds a copy into /etc/skel (ADR 0095). These tests read the COMMITTED
# payload and assert its shape:
# required keys/values present, host-bound/orphan content absent, scripts
# shaped, and — the drift guard — that config.toml's enabled list mirrors the
# vendored shared core set (noctalia_core_plugins), so the two cannot drift.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."      # .installer/tests/config → repo root
  CT="$REPO/.config/noctalia/config.toml"
  KDL="$REPO/.config/niri/config.kdl"
  HC="$REPO/.config/hypr/hyprland.conf"
  CYCLE="$REPO/.local/bin/noctalia-cycle-palette"
  ENABLE="$REPO/.local/bin/noctalia-enable-plugins"
  NIRI_SH="$BATS_TEST_DIRNAME/../../lib/packages/niri.sh"
  GTK3="$REPO/.config/gtk-3.0/settings.ini"
  GTK4="$REPO/.config/gtk-4.0/settings.ini"
  QT6CT="$REPO/.config/qt6ct/qt6ct.conf"
  QT6CT_COLORS="$REPO/.config/qt6ct/colors"
}

# ── config.toml: required look ───────────────────────────────────────────────

@test "config.toml exists and is the stow-owned curated look" {
  [ -f "$CT" ]
  # Catppuccin Mocha Lavender via the community palette (ADR 0101).
  grep -q '^builtin = "Catppuccin"' "$CT"
  grep -q '^source = "community"' "$CT"
  grep -q '^mode = "dark"' "$CT"
  grep -q '^community_palette = "Catppuccin Mocha Lavender"' "$CT"
  grep -q '^wallpaper_scheme = "m3-content"' "$CT"
}

@test "config.toml sets the UI font once at [shell], no bar override" {
  grep -q '^font_family = "Noto Sans"' "$CT"
  # exactly one font_family key — the [shell] one; no [bar.default] override
  [ "$(grep -c 'font_family' "$CT")" -eq 1 ]
}

@test "config.toml points the default wallpaper at the packaged asset" {
  grep -q '^path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"' "$CT"
}

@test "config.toml pins plugins to the vendored set (auto_update off)" {
  grep -q '^auto_update = "none"' "$CT"
}

# ── config.toml: host-bound / dead content excluded ──────────────────────────

@test "config.toml carries no host-bound or orphan state" {
  ! grep -q 'Virtual-1' "$CT"          # VM output name
  ! grep -qi 'bing' "$CT"              # captured wallpaper path
  ! grep -q 'login_box' "$CT"          # lockscreen widget geometry
  ! grep -q 'lockscreen-login-box' "$CT"
  ! grep -q 'phone-connect' "$CT"      # orphan widget (plugin not enabled)
  ! grep -q 'ip-monitor' "$CT"         # orphan widget
  ! grep -q 'fel/ocr' "$CT"            # orphan widget
}

@test "config.toml enables none of the dropped plugins (ADR 0094)" {
  ! grep -q 'noctalia/bitwarden' "$CT"
  ! grep -q 'mini-docker' "$CT"
  ! grep -q 'system-updater' "$CT"
}

# ── niri glue + helper scripts ───────────────────────────────────────────────

@test "config.kdl autostarts Noctalia, the enable one-shot, and binds kitty" {
  [ -f "$KDL" ]
  grep -q 'spawn-at-startup "noctalia" "--daemon"' "$KDL"
  grep -q 'noctalia-enable-plugins' "$KDL"
  grep -q 'spawn "kitty"' "$KDL"
}

@test "config.kdl skips the hotkey-overlay so no welcome screen on first login" {
  grep -Eq 'hotkey-overlay[[:space:]]*\{' "$KDL"
  grep -q 'skip-at-startup' "$KDL"
}

# ── shared Bibata cursor default (ADR 0098) ──────────────────────────────────

@test "config.kdl sets the Bibata Modern Ice cursor (ADR 0098)" {
  grep -q 'xcursor-theme "Bibata-Modern-Ice"' "$KDL"
  grep -q 'xcursor-size 24' "$KDL"
}

@test "hyprland.conf sets Bibata hyprcursor + Xcursor fallback (ADR 0098)" {
  grep -q '^env = HYPRCURSOR_THEME,Bibata-Modern-Ice' "$HC"
  grep -q '^env = XCURSOR_THEME,Bibata-Modern-Ice' "$HC"
}

@test "hyprland.conf hosts Noctalia: autostart + IPC launcher/lock (ADR 0097)" {
  grep -q '^exec-once = noctalia --daemon' "$HC"
  grep -q 'noctalia msg panel-toggle launcher' "$HC"
  grep -q 'noctalia msg session lock' "$HC"
  ! grep -q 'hyprlock' "$HC"
}

@test "the palette cycler is executable and uses the v5 native CLI" {
  [ -x "$CYCLE" ]
  grep -q 'noctalia msg color-scheme-set builtin' "$CYCLE"
  ! grep -q 'qs -c noctalia-shell' "$CYCLE"   # not the dead v4 Quickshell IPC
  grep -q 'Rosé Pine' "$CYCLE"
  grep -q 'Nord' "$CYCLE"
}

@test "the plugin-enable one-shot is executable, [local]-scoped, run-once" {
  [ -x "$ENABLE" ]
  grep -q 'msg plugins enable' "$ENABLE"
  grep -q '\[local\]' "$ENABLE"
  grep -q 'installer-plugins-enabled' "$ENABLE"   # the run-once guard
}

# ── drift guard ──────────────────────────────────────────────────────────────

# config.toml's enabled ids (author/name) reduced to their bare plugin names
# must equal the installer's SHARED CORE plugin set — and ONLY the core set. The
# compositor slices (niri-* / hypr-*) are deliberately NOT in config.toml (ADR
# 0097): they are vendored per-adapter and enabled by the first-login one-shot,
# so config.toml stays byte-identical across compositors. Off-by-one here means
# a core plugin ships enabled-but-not-vendored, or a slice id leaked into the
# shared config — the drift 0094/0097 bans.
@test "config.toml enabled list mirrors the shared core plugin set" {
  local enabled core
  enabled="$(awk '/^enabled = \[/{f=1;next} f&&/^\]/{f=0} f' "$CT" \
    | grep -oE '"[^"]+"' | tr -d '"' | sed 's#.*/##' | sort)"
  core="$( (set +u; source "$NIRI_SH"; noctalia_core_plugins) | sort)"
  [ -n "$enabled" ]
  [ "$enabled" = "$core" ]
}

# The shared config.toml must be compositor-NEUTRAL (ADR 0097): no niri-* or
# hypr-* slice id anywhere — not in the enabled list, not in a bar/widget
# placement — so the one seeded file is byte-identical and correct on both
# compositors. The built-in `workspaces` widget covers workspaces on both.
@test "config.toml carries no compositor-specific slice widget or id" {
  ! grep -qE '(niri|hypr)-' "$CT"
}

# ── App Theming Bridge: GTK/Qt apps follow Noctalia (ADR 0102) ───────────────
# The stow payload's GTK/Qt config is the consuming half of the bridge: it must
# stop fighting Noctalia's live palette (no Breeze, no GTK4 theme name) while
# keeping the keys Noctalia never sets (icons, font, prefer-dark), and route Qt
# through qt6ct on both compositors. Noctalia's own generated files
# (gtk-*/noctalia.css, qt6ct/colors/noctalia.conf) are NOT part of this payload.

@test "gtk-3.0 uses adw-gtk3-dark and keeps icons/font/dark (ADR 0102)" {
  [ -f "$GTK3" ]
  grep -q '^gtk-theme-name=adw-gtk3-dark' "$GTK3"
  grep -q '^gtk-icon-theme-name=Papirus-Dark' "$GTK3"
  grep -q '^gtk-font-name=' "$GTK3"
  grep -q '^gtk-application-prefer-dark-theme=true' "$GTK3"
}

@test "gtk-3.0 drops the stale breeze cursor for Bibata (ADR 0098/0102)" {
  ! grep -q 'breeze_cursors' "$GTK3"
}

@test "gtk-4.0 carries no theme name so libadwaita follows gtk.css (ADR 0102)" {
  [ -f "$GTK4" ]
  grep -q '^gtk-icon-theme-name=Papirus-Dark' "$GTK4"
  grep -q '^gtk-font-name=' "$GTK4"
  # No GTK4 theme name — kept LAST so set -e honours the negation (a middle
  # `! grep` is exempt from errexit and would silently never fail).
  ! grep -q '^gtk-theme-name=' "$GTK4"
}

@test "the base preset ships adw-gtk3 for the GTK bridge (ADR 0102)" {
  ( set +u; source "$NIRI_SH"; noctalia_preset_packages ) | grep -qx 'adw-gtk3'
}

@test "qt6ct is pre-seeded onto Noctalia's generated scheme (ADR 0102)" {
  [ -f "$QT6CT" ]
  grep -q 'colors/noctalia.conf' "$QT6CT"
  grep -q '^custom_palette=true' "$QT6CT"
  # Fusion honours the custom palette; Papirus matches the GTK icon theme.
  grep -q '^style=Fusion' "$QT6CT"
  grep -q '^icon_theme=Papirus-Dark' "$QT6CT"
}

@test "the static Catppuccin qt6ct color files are gone (ADR 0102)" {
  ! compgen -G "$QT6CT_COLORS/catppuccin-mocha-*.conf" >/dev/null
}

@test "QT_QPA_PLATFORMTHEME=qt6ct is set per-compositor (ADR 0102)" {
  # niri's environment{} node sets the value on one line; assert them together.
  grep -q 'QT_QPA_PLATFORMTHEME "qt6ct"' "$KDL"
  grep -q '^env = QT_QPA_PLATFORMTHEME,qt6ct' "$HC"
}
