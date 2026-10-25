#!/usr/bin/env bats
# Tests: config.toml and theming (split from noctalia-stow.bats;
# shared setup in noctalia-stow-helpers.bash)

load noctalia-stow-helpers


# ── config.toml: required look ───────────────────────────────────────────────

@test "config.toml registers the Neovim Theme Template (ADR 0136)" {
  grep -q '\[theme.templates.user.nvim\]' "$CT"
  grep -q 'templates/nvim.lua' "$CT"
  grep -q '~/.config/nvim/themes/noctalia.lua' "$CT"
  [ -f "$REPO/.config/noctalia/templates/nvim.lua" ]
}

@test "config.toml exists and is the stow-owned curated look" {
  [ -f "$CT" ]
  # Catppuccin Mocha Sapphire via the community palette (ADR 0109).
  grep -q '^builtin = "Catppuccin"' "$CT"
  grep -q '^source = "community"' "$CT"
  grep -q '^mode = "dark"' "$CT"
  grep -q '^community_palette = "Catppuccin Mocha Sapphire"' "$CT"
  grep -q '^wallpaper_scheme = "m3-content"' "$CT"
}

@test "config.toml sets the UI font once at [shell], no bar override" {
  grep -q '^font_family = "Noto Sans"' "$CT"
  # exactly one font_family key — the [shell] one; no [bar.default] override
  [ "$(grep -c 'font_family' "$CT")" -eq 1 ]
}

@test "config.toml registers Noctalia's own polkit agent (ADR 0100)" {
  # Off by default upstream; the wlroots sessions have no other agent.
  toml_table shell "$CT" | grep -q '^polkit_agent = true'
}

@test "config.toml pins Noctalia's clipboard keep-alive (ADR 0147)" {
  toml_table shell "$CT" \
    | grep -q '^clipboard_keep_from_closed_apps = true'
}

@test "hypr is click-to-focus; niri adds no focus-follows-mouse (ADR 0147)" {
  local in="$REPO/.config/hypr/conf.d/input.lua"
  grep -q '^ *follow_mouse = 2,' "$in"
  grep -q '^ *float_switch_override_focus = 0,' "$in"
  grep -q '^ *anr_missed_pings = 15,' "$in"
  grep -q '^ *no_update_news = true,' "$in"
  grep -q '^ *no_donation_nag = true,' "$in"
  ! grep -rq 'focus-follows-mouse' "$REPO/.config/niri"
}

@test "both compositors re-enable GTK middle-click paste (ADR 0147)" {
  grep -q 'gtk-enable-primary-paste" "true"' "$NAUTO"
  grep -q 'gtk-enable-primary-paste true' "$HAUTO"
}

@test "config.toml points the default wallpaper at the packaged asset" {
  grep -q '^path = "/usr/share/noctalia/assets/noctalia-wallpaper.png"' "$CT"
}

@test "config.toml pins plugins to the vendored set (auto_update off)" {
  grep -q '^auto_update = "none"' "$CT"
}

# The kcolorscheme template merges its colors into ~/.config/kdeglobals. The
# committed shared config.toml still ships WITHOUT it, so a hand-stow (no
# installer) never leaks into Plasma; the preset injects it into the SEEDED copy,
# shipped together with the combined-box KDE reset that makes it safe (ADR 0123).
@test "config.toml drops the kcolorscheme template (ADR 0104/0123)" {
  ! grep -q 'kcolorscheme' "$CT"
}

# ADR 0123: the preset injects kcolorscheme into the SEEDED config.toml on EVERY
# Noctalia box (combined included) so KDE-framework apps (Dolphin/Gwenview/Kate)
# follow the shell palette. No longer gated on a KDE-free desktop set — on a
# combined box kde.sh's KDE session reset reasserts BreezeDark under Plasma.
@test "preset injects kcolorscheme unconditionally (ADR 0123)" {
  grep -q '"kcolorscheme",' "$PRESET" "$SKEL"
  grep -q 'builtin_ids = ' "$PRESET" "$SKEL"
  # the injection is no longer gated behind a KDE-free desktop set
  ! grep -qF '!= *" kde "*' "$PRESET" "$SKEL"
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

# Close window on Meta+X across both compositors and KDE (ADR 0113) — the old
# Mod+Q close bind is freed, not repurposed.
@test "niri closes the focused window on Mod+X, not Mod+Q (ADR 0113)" {
  grep -Eq 'Mod\+X[^{]*\{ close-window; \}' "$NBIND"
  run grep -Eq 'Mod\+Q[^{]*\{ close-window; \}' "$NBIND"
  [ "$status" -ne 0 ]
}

@test "hypr closes the focused window on SUPER+X, not SUPER+Q (ADR 0113)" {
  grep -Eq '" \+ X".*window\.close' "$HBIND"
  run grep -Eq '" \+ Q".*window\.close' "$HBIND"
  [ "$status" -ne 0 ]
}

# Resolution stays autodetected (ADR 0110): the seeded compositor configs pin no
# host-specific mode — niri omits any `output` block, Hyprland uses `preferred`.
@test "compositor configs seed no hardcoded resolution (ADR 0110)" {
  # niri: no output {} block anywhere in the config tree
  run grep -rEq 'output[[:space:]]+"' "$REPO/.config/niri"
  [ "$status" -ne 0 ]
  # Hyprland: autodetects via preferred, never a WxH@Hz literal
  grep -q 'mode = "preferred"' "$HENV"
  run grep -rEq '[0-9]{3,}x[0-9]{3,}(@[0-9]+)?' "$REPO/.config/hypr"
  [ "$status" -ne 0 ]
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
  grep -q 'installer-plugins-enabled' "$ENABLE"   # the run-once guard
}

# `plugins list` runs on Noctalia's main loop and waits on the plugin-source
# lock its startup export worker holds for minutes on a fresh install: the
# shell (and its ScreenSaver/Notifications names) froze. The one-shot reads
# the vendored ids from disk and only ever calls `enable`.
@test "the plugin-enable one-shot enables vendored ids without plugins list" {
  local test_directory="$BATS_TEST_TMPDIR"
  mkdir -p "$test_directory/bin" "$test_directory/data/noctalia/plugins/a" "$test_directory/data/noctalia/plugins/b"
  printf 'id = "x/a"\nname = "A"\n' > "$test_directory/data/noctalia/plugins/a/plugin.toml"
  printf '  id="y/b"\n' > "$test_directory/data/noctalia/plugins/b/plugin.toml"
  # stub: not running for the first call, then logs every msg
  cat > "$test_directory/bin/noctalia" <<EOF
#!/bin/sh
echo "\$*" >> "$test_directory/calls"
[ -f "$test_directory/up" ] && exit 0
: > "$test_directory/up"; echo "error: noctalia is not running" >&2; exit 1
EOF
  cat > "$test_directory/bin/sleep" <<'EOF'
#!/bin/sh
EOF
  chmod +x "$test_directory/bin/noctalia" "$test_directory/bin/sleep"
  PATH="$test_directory/bin:$PATH" XDG_DATA_HOME="$test_directory/data" XDG_STATE_HOME="$test_directory/state" \
    run "$ENABLE"
  [ "$status" -eq 0 ]
  run grep -c 'plugins list' "$test_directory/calls"
  [ "$output" = 0 ]
  grep -qx 'msg plugins enable x/a' "$test_directory/calls"
  grep -qx 'msg plugins enable y/b' "$test_directory/calls"
  [ -f "$test_directory/state/noctalia/installer-plugins-enabled" ]
}

# Live Theme Bridge (ADR 0116): the runtime half of the App Theming Bridge —
# watches Noctalia's generated color files and nudges each toolkit to re-read so
# RUNNING apps repaint. Qt6 by an atomic rewrite of qt6ct.conf (its dir-watcher
# misses a bare mtime touch); GTK by a best-effort gtk-theme toggle (X11-only —
# palette is relaunch-only on native Wayland, ADR 0116).
@test "the Live Theme Bridge is executable and nudges Qt6 + GTK (ADR 0116)" {
  [ -x "$BRIDGE" ]
  grep -q 'inotifywait' "$BRIDGE"                 # watches the generated files
  grep -q "noctalia" "$BRIDGE"                    # filtered to Noctalia's output
  grep -q 'qt6ct.conf' "$BRIDGE"                  # Qt6 nudge: rewrite the conf
  grep -q 'gtk-theme' "$BRIDGE"                   # GTK best-effort toggle
  grep -q 'color-schemes' "$BRIDGE"               # watch the KColorScheme (0124)
  grep -q 'noctalia\\\.(conf|css|colors)' "$BRIDGE"  # incl. .colors (ADR 0124)
}

@test "both compositors autostart the Live Theme Bridge (ADR 0116)" {
  grep -q 'noctalia-theme-bridge' "$NAUTO"
  grep -q 'noctalia-theme-bridge' "$HAUTO"
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
    | grep -oE '"[^"]+"' | awk '{ gsub(/"/, ""); sub(/.*\//, ""); print }' \
    | sort)"
  core="$( (set +u; source "$NOCTALIA_SH"; noctalia_core_plugins) | sort)"
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
  grep -q '\.config/gtk-3.0/settings.ini' "$PRESET" "$SKEL"
  grep -q '\.config/gtk-4.0/settings.ini' "$PRESET" "$SKEL"
}

@test "seeded gtk-3.0 is adw-gtk3-dark + icons/font/dark (ADR 0102/0104)" {
  grep -q '^gtk-theme-name=adw-gtk3-dark' "$PRESET" "$SKEL"
  grep -q '^gtk-icon-theme-name=Papirus-Dark' "$PRESET" "$SKEL"
  grep -q '^gtk-font-name=' "$PRESET" "$SKEL"
  grep -q '^gtk-application-prefer-dark-theme=true' "$PRESET" "$SKEL"
}

@test "seeded GTK config drops stale breeze cursor + host DPI (ADR 0098/0104)" {
  # /etc/skel is a system default: no per-host DPI, no dead breeze cursor.
  run grep -qE 'breeze_cursors|gtk-xft-dpi' "$PRESET" "$SKEL"
  [ "$status" -ne 0 ]
}

@test "seeded gtk-4.0 carries no theme name so libadwaita follows gtk.css" {
  # exactly one gtk-theme-name in the preset (the gtk-3.0 one) …
  [ "$(cat "$PRESET" "$SKEL" | grep -c '^gtk-theme-name=')" -eq 1 ]
  # … and none after the gtk-4.0 seed begins (awk exits with that count).
  run awk '/gtk-4.0.settings/{f=1} f&&/^gtk-theme-name=/{c++} END{exit c}' \
    "$SKEL"
  [ "$status" -eq 0 ]
}

# The preset seeds Noctalia's setup-complete marker so a fresh first login lands
# on a usable, interactive bar (the wizard is a modal panel that otherwise
# blocks every bar click). Marker is state, not config — seeded, never stowed.
@test "preset seeds the Noctalia setup-wizard-complete marker (first-run)" {
  grep -q '\.local/state/noctalia/\.setup-complete' "$PRESET" "$SKEL"
}

# The stow'd compositor configs must NOT force software cursors (real hardware
# keeps the optimal hardware cursor); the software-cursor override is injected
# by the preset ONLY when installing into a VM (virtio-gpu's cursor plane is
# buggy). So: absent from the payload, gated on systemd-detect-virt in the seed.
@test "software-cursor override is VM-gated in the preset, not in the payload" {
  grep -q 'systemd-detect-virt' "$PRESET" "$SKEL"
  grep -q 'disable-cursor-plane' "$PRESET" "$SKEL"
  grep -q 'no_hardware_cursors' "$PRESET" "$SKEL"
  # NOT in the stow'd configs (real hardware keeps hardware cursors); run/status
  # so the negation actually fails the test (a bare `! grep` is errexit-exempt).
  run grep -rq 'no_hardware_cursors' "$REPO/.config/hypr"; [ "$status" -ne 0 ]
  run grep -rq 'disable-cursor-plane' "$REPO/.config/niri"; [ "$status" -ne 0 ]
}

@test "the base preset ships adw-gtk-theme for the GTK bridge (ADR 0102)" {
  # Package is adw-gtk-theme (extra); it ships the adw-gtk3-dark theme dir.
  ( set +u; source "$NOCTALIA_SH"; noctalia_preset_packages ) \
    | grep -qx 'adw-gtk-theme'
}

@test "the base preset ships inotify-tools for the Live Theme Bridge (0116)" {
  # inotifywait (inotify-tools, extra) drives the bridge's file watch.
  ( set +u; source "$NOCTALIA_SH"; noctalia_preset_packages ) \
    | grep -qx 'inotify-tools'
}

@test "qt6ct is pre-seeded onto Noctalia's KColorScheme (ADR 0102/0124)" {
  [ -f "$QT6CT" ]
  # points at the .colors KColorScheme (qt6ct-kde applies the full scheme so
  # Dolphin's accents follow), NOT the qt6ct QPalette colors/noctalia.conf (0124).
  grep -q 'color-schemes/noctalia.colors' "$QT6CT"
  ! grep -q 'colors/noctalia.conf' "$QT6CT"
  grep -q '^custom_palette=true' "$QT6CT"
  # Fusion honours the custom palette; Papirus matches the GTK icon theme.
  grep -q '^style=Fusion' "$QT6CT"
  grep -q '^icon_theme=Papirus-Dark' "$QT6CT"
}

# ADR 0108: a fresh box never stows (ADR 0095), so the stow-only qt6ct.conf never
# arrived and Qt/KDE apps rendered default white. The preset must SEED it (from
# the curated dir) and chroot.sh must STAGE it into that dir, on both adapters.
@test "preset seeds qt6ct.conf so a fresh box themes Qt apps (ADR 0108)" {
  grep -q '\.config/qt6ct/qt6ct.conf' "$PRESET" "$SKEL"
  # staged into every wlroots adapter's curated dir by the shared
  # curated-payload helper.
  grep -q '_chroot_stage_curated_compositor niri ' "$CHROOT"
  grep -q '_chroot_stage_curated_compositor hyprland ' "$CHROOT"
  grep -q '_chroot_stage_curated_compositor umbriel ' "$CHROOT"
  grep -q 'qt6ct/qt6ct.conf' "$CHROOT"
}

# ADR 0108/0124: qt6ct.conf points at ~/.local/share/color-schemes/noctalia.colors,
# written only once Noctalia first applies; the preset seeds a static snapshot to
# kill the boot-race white flash + create the dir the bridge watches. Seed-only
# (never a stowed repo file — Noctalia rewrites it → git dirt).
@test "preset seeds a boot-race KColorScheme snapshot (ADR 0108/0124)" {
  grep -q '\.local/share/color-schemes/noctalia.colors' "$PRESET" "$SKEL"
  grep -q '^\[Colors:Selection\]' "$PRESET" "$SKEL"          # a real KColorScheme group
  # NOT a stowed repo file (Noctalia rewrites it → git dirt, ADR 0104).
  [ ! -e "$REPO/.local/share/color-schemes/noctalia.colors" ]
}

# ADR 0109: the default is the COMMUNITY palette "Catppuccin Mocha Sapphire";
# the preset seeds its cache JSON so first boot resolves it OFFLINE (no
# api.noctalia.dev). Seed-only, into the XDG_STATE community-palettes cache.
@test "preset seeds the Sapphire palette JSON for offline first boot (ADR 0109)" {
  grep -q 'community-palettes/Catppuccin%20Mocha%20Sapphire.json' "$PRESET" "$SKEL"
  grep -q '"mPrimary": "#74c7ec"' "$PRESET" "$SKEL"
  # not a stowed repo file (state, not config)
  [ ! -e "$REPO/.local/state/noctalia/community-palettes" ]
}

@test "the static Catppuccin qt6ct color files are gone (ADR 0102)" {
  ! compgen -G "$QT6CT_COLORS/catppuccin-mocha-*.conf" >/dev/null
}

@test "QT_QPA_PLATFORMTHEME=qt6ct is set per-compositor (ADR 0102)" {
  # niri's environment{} node sets the value on one line; assert them together.
  grep -q 'QT_QPA_PLATFORMTHEME "qt6ct"' "$NENV"
  grep -q 'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")' "$HENV"
}


# ── Kitty Theme Template: kitty follows Noctalia (ADR 0130) ──────────────────
# A USER template, NOT the builtin kitty template — the builtin's apply.sh
# rewrites kitty.conf and would clobber the stow symlink. kitty.conf includes
# the generated output; the output is seed-only (gitignored), never stowed.

@test "config.toml drops the builtin kitty template (ADR 0130)" {
  # builtin_ids must NOT carry a "kitty", entry (else apply.sh rewrites the
  # stowed kitty.conf). The user-template header [.user.kitty] is not quoted.
  ! grep -qE '^[[:space:]]*"kitty",' "$CT"
}

@test "config.toml declares the kitty user-template (ADR 0130)" {
  grep -q '^\s*\[theme.templates.user.kitty\]' "$CT"
  grep -q 'noctalia/templates/kitty.conf' "$CT"
  grep -q '~/.config/kitty/themes/noctalia.conf' "$CT"
}

@test "kitty.conf includes the generated theme, not Catppuccin (ADR 0130)" {
  [ -f "$KITTY" ]
  grep -q '^include themes/noctalia.conf' "$KITTY"
  ! grep -q 'catppuccin' "$KITTY"
  # the LS_COLORS env pass-through part-file was dropped from the include list
  ! grep -q 'conf/env.conf' "$KITTY"
}

@test "the kitty template input maps the palette terminal roles (ADR 0130)" {
  [ -f "$KTPL" ]
  grep -q 'color0 {{colors.terminal_normal_black.default.hex}}' "$KTPL"
  grep -q '^background .*terminal_background.default.hex' "$KTPL"
  # engine parses comments too (ADR 0129): no double-brace tag in any comment.
  run grep -E '^[[:space:]]*#.*\{\{' "$KTPL"
  [ "$status" -ne 0 ]
}

@test "the generated kitty theme is seed-only, never stowed (ADR 0130/0104)" {
  # Noctalia rewrites themes/noctalia.conf; a stowed copy would push into repo.
  [ ! -e "$KTHEMES/noctalia.conf" ]
  grep -q '^\.config/kitty/themes/' "$REPO/.gitignore"
}

@test "the static Catppuccin kitty theme files are gone (ADR 0130)" {
  ! compgen -G "$KTHEMES/catppuccin-*.conf" >/dev/null
}

# Session-aware window decorations (ADR 0130): default `no` so KDE keeps KWin's
# system titlebar/borders (movable/closable); the compositors export
# KITTY_DECORATIONS, applied via `envinclude`, to hide them for tiling.
@test "kitty decorations session-aware: default no + envinclude (ADR 0130)" {
  grep -q '^hide_window_decorations         no' \
    "$KHOME/conf/window-layout.conf"
  grep -q '^envinclude KITTY_DECORATIONS' "$KITTY"
  # both compositors export the hide-decorations override
  grep -q 'KITTY_DECORATIONS "hide_window_decorations yes"' "$NENV"
  grep -q 'KITTY_DECORATIONS", "hide_window_decorations yes"' "$HENV"
}
