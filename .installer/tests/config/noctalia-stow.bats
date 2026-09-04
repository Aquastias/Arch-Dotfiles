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
  HC="$REPO/.config/hypr/hyprland.lua"
  # Split config (ADR 0107): the entry file is a manifest of `include` lines;
  # settings live in these conf.d/ part-files, asserted where each construct now
  # lives.
  NENV="$REPO/.config/niri/conf.d/environment.kdl"
  NAPP="$REPO/.config/niri/conf.d/appearance.kdl"
  NAUTO="$REPO/.config/niri/conf.d/autostart.kdl"
  NBIND="$REPO/.config/niri/conf.d/keybinds.kdl"
  HENV="$REPO/.config/hypr/conf.d/environment.lua"
  HAUTO="$REPO/.config/hypr/conf.d/autostart.lua"
  HBIND="$REPO/.config/hypr/conf.d/keybinds.lua"
  CYCLE="$REPO/.local/bin/noctalia-cycle-palette"
  ENABLE="$REPO/.local/bin/noctalia-enable-plugins"
  NIRI_SH="$BATS_TEST_DIRNAME/../../lib/packages/niri.sh"
  PRESET="$BATS_TEST_DIRNAME/../../lib/chroot/noctalia-preset.sh"
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

# The kcolorscheme template merges its colors into ~/.config/kdeglobals — the
# same file KDE owns. On a kde+compositor box that leak repaints the Plasma
# session, so the template is dropped fleet-wide (ADR 0104): pure-compositor
# boxes have no KColorScheme apps to want it (pcmanfm-qt uses the qt template).
@test "config.toml drops the kcolorscheme template (ADR 0104)" {
  ! grep -q 'kcolorscheme' "$CT"
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

@test "config.kdl is a manifest that includes the conf.d/ part-files" {
  [ -f "$KDL" ]
  grep -q 'include "conf.d/autostart.kdl"' "$KDL"
  grep -q 'include "conf.d/keybinds.kdl"' "$KDL"
}

@test "niri conf.d autostarts Noctalia, the enable one-shot, and binds kitty" {
  grep -q 'spawn-at-startup "noctalia" "--daemon"' "$NAUTO"
  grep -q 'noctalia-enable-plugins' "$NAUTO"
  grep -q 'spawn "kitty"' "$NBIND"
}

@test "niri conf.d skips the hotkey-overlay so no welcome on first login" {
  grep -Eq 'hotkey-overlay[[:space:]]*\{' "$NAPP"
  grep -q 'skip-at-startup' "$NAPP"
}

# ── shared Bibata cursor default (ADR 0098) ──────────────────────────────────

@test "niri conf.d sets the Bibata Modern Ice cursor (ADR 0098)" {
  grep -q 'xcursor-theme "Bibata-Modern-Ice"' "$NENV"
  grep -q 'xcursor-size 24' "$NENV"
}

# The conf.d dir name has a dot (Lua require reads dots as path separators), so
# the manifest puts conf.d/ on package.path and requires parts by basename.
@test "hyprland.lua is a manifest that requires the conf.d/ part-files" {
  [ -f "$HC" ]
  grep -q 'conf.d/?.lua' "$HC"
  grep -q 'require("autostart")' "$HC"
  grep -q 'require("keybinds")' "$HC"
}

@test "hypr conf.d sets Bibata hyprcursor + Xcursor fallback (ADR 0098)" {
  grep -q 'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")' "$HENV"
  grep -q 'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")' "$HENV"
}

@test "hypr conf.d hosts Noctalia: autostart + IPC launcher/lock (ADR 0097)" {
  grep -q 'hl.exec_cmd("noctalia --daemon")' "$HAUTO"
  grep -q 'noctalia msg panel-toggle launcher' "$HBIND"
  grep -q 'noctalia msg session lock' "$HBIND"
  run grep -rq 'hyprlock' "$REPO/.config/hypr"; [ "$status" -ne 0 ]
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

# ── App Theming Bridge: GTK/Qt apps follow Noctalia (ADR 0102/0104) ──────────
# GTK settings.ini are SEEDED by the shared preset, never stowed (ADR 0104):
# Plasma's kde-gtk-config rewrites them every login, and a stow symlink would
# push that write into the dotfiles repo. So the drift guard reads the preset's
# heredoc, not a repo file; qt6ct.conf stays stowed — Plasma never touches it.
# Noctalia's own generated files (noctalia.css, qt6ct's noctalia.conf) are NOT
# part of either payload.

@test "GTK settings.ini are seeded by the preset, not stowed (ADR 0104)" {
  [ ! -e "$REPO/.config/gtk-3.0/settings.ini" ]
  [ ! -e "$REPO/.config/gtk-4.0/settings.ini" ]
  grep -q '\.config/gtk-3.0/settings.ini' "$PRESET"
  grep -q '\.config/gtk-4.0/settings.ini' "$PRESET"
}

@test "seeded gtk-3.0 is adw-gtk3-dark + icons/font/dark (ADR 0102/0104)" {
  grep -q '^gtk-theme-name=adw-gtk3-dark' "$PRESET"
  grep -q '^gtk-icon-theme-name=Papirus-Dark' "$PRESET"
  grep -q '^gtk-font-name=' "$PRESET"
  grep -q '^gtk-application-prefer-dark-theme=true' "$PRESET"
}

@test "seeded GTK config drops stale breeze cursor + host DPI (ADR 0098/0104)" {
  # /etc/skel is a system default: no per-host DPI, no dead breeze cursor.
  run grep -qE 'breeze_cursors|gtk-xft-dpi' "$PRESET"
  [ "$status" -ne 0 ]
}

@test "seeded gtk-4.0 carries no theme name so libadwaita follows gtk.css" {
  # exactly one gtk-theme-name in the preset (the gtk-3.0 one) …
  [ "$(grep -c '^gtk-theme-name=' "$PRESET")" -eq 1 ]
  # … and none after the gtk-4.0 seed begins (awk exits with that count).
  run awk '/gtk-4.0.settings/{f=1} f&&/^gtk-theme-name=/{c++} END{exit c}' \
    "$PRESET"
  [ "$status" -eq 0 ]
}

# The preset seeds Noctalia's setup-complete marker so a fresh first login lands
# on a usable, interactive bar (the wizard is a modal panel that otherwise
# blocks every bar click). Marker is state, not config — seeded, never stowed.
@test "preset seeds the Noctalia setup-wizard-complete marker (first-run)" {
  grep -q '\.local/state/noctalia/\.setup-complete' "$PRESET"
}

# The stow'd compositor configs must NOT force software cursors (real hardware
# keeps the optimal hardware cursor); the software-cursor override is injected
# by the preset ONLY when installing into a VM (virtio-gpu's cursor plane is
# buggy). So: absent from the payload, gated on systemd-detect-virt in the seed.
@test "software-cursor override is VM-gated in the preset, not in the payload" {
  grep -q 'systemd-detect-virt' "$PRESET"
  grep -q 'disable-cursor-plane' "$PRESET"
  grep -q 'no_hardware_cursors' "$PRESET"
  # NOT in the stow'd configs (real hardware keeps hardware cursors); run/status
  # so the negation actually fails the test (a bare `! grep` is errexit-exempt).
  run grep -rq 'no_hardware_cursors' "$REPO/.config/hypr"; [ "$status" -ne 0 ]
  run grep -rq 'disable-cursor-plane' "$REPO/.config/niri"; [ "$status" -ne 0 ]
}

@test "the base preset ships adw-gtk-theme for the GTK bridge (ADR 0102)" {
  # Package is adw-gtk-theme (extra); it ships the adw-gtk3-dark theme dir.
  ( set +u; source "$NIRI_SH"; noctalia_preset_packages ) \
    | grep -qx 'adw-gtk-theme'
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
  grep -q 'QT_QPA_PLATFORMTHEME "qt6ct"' "$NENV"
  grep -q 'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")' "$HENV"
}
