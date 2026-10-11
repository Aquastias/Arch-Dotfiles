#!/usr/bin/env bats
# Tests: look and settings seeding (split from kde-adapter.bats;
# shared setup in kde-adapter-helpers.bash)

load kde-adapter-helpers


# ── apps_list (categorized, bool mode) ──────────────────────────────────────

@test "selected app under a category is installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":{"sentinel-app":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-app" "$PACMAN_LOG"
}

@test "deselected leaf (false) is not installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":
{"sentinel-keep":true,"sentinel-drop":false}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-keep" "$PACMAN_LOG"
  ! grep -q "sentinel-drop" "$PACMAN_LOG"
}

# The shell package set is DATA now — the shell_packages Categorized List in
# install-kde.jsonc, parsed like apps. This is the MECHANISM test (a sentinel);
# the real 12-package content is covered by resolver.bats (kde-shell) and the
# drift guard that asserts kde-shell == the jsonc shell_packages.
@test "shell section installs the declared shell_packages" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"shell_packages":{"core":{"sentinel-shell":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-shell" "$PACMAN_LOG"
}

@test "shell:false skips the shell packages" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":false,"shell_packages":{"core":{"sentinel-shell":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "sentinel-shell" "$PACMAN_LOG"
}


# ── display manager is no longer the KDE adapter's concern (ADR 0069) ─────────
# The display manager is an operator choice owned by a separate Display Manager
# Adapter. The KDE adapter installs sddm-kcm (a KDE config app) but neither the
# sddm PACKAGE nor its enablement — those moved to dm-sddm.

@test "KDE adapter enables no display manager" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run env ENVIRONMENT_DESKTOP="kde" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "enable sddm" "$SYSTEMCTL_LOG"
  ! grep -q "enable greetd" "$SYSTEMCTL_LOG"
}

@test "KDE adapter installs sddm-kcm but not the sddm package" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"shell_packages":{"integration":{"sddm-kcm":true}}}
JSON
  run env ENVIRONMENT_DESKTOP="kde hyprland" bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sddm-kcm" "$PACMAN_LOG"
  # the bare sddm package is not installed by KDE — dm-sddm owns it
  ! grep -qE '(^|[[:space:]])sddm([[:space:]]|$)' "$PACMAN_LOG"
}


# ── default look: Breeze Dark seeding (ADR 0088) ────────────────────────────

@test "shell phase installs the GTK-dark bridge packages" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,
"shell_packages":{"theming":{"breeze-gtk":true,"kde-gtk-config":true}}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "breeze-gtk" "$PACMAN_LOG"
  grep -q "kde-gtk-config" "$PACMAN_LOG"
}

# The look seed is now the operator's CAPTURED kdeglobals (ADR 0111): a custom
# dark scheme (inline [Colors:*] + ColorSchemeHash) on the Breeze widget style /
# breezedark look-and-feel / Papirus-Dark icons, not the old BreezeDark heredoc.
@test "theme seed writes the captured custom kdeglobals into skel (ADR 0111)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local kdeglobals_file="$TEST_DIR/seed/etc/skel/.config/kdeglobals"
  [ -f "$kdeglobals_file" ]
  grep -q "widgetStyle=Breeze" "$kdeglobals_file"
  grep -q "Theme=Papirus-Dark" "$kdeglobals_file"
  grep -q "LookAndFeelPackage=org.kde.breezedark.desktop" "$kdeglobals_file"
  # the custom scheme rides inline: a [Colors:*] section + the faster animations
  grep -q "^\[Colors:View\]" "$kdeglobals_file"
  grep -q "AnimationDurationFactor=" "$kdeglobals_file"
}


# ── captured Plasma settings seed (ADR 0111) ────────────────────────────────
# The adapter copies the vendored captured config files verbatim into
# /etc/skel/.config, konsave-style — one whole-file copy per file.

@test "captured settings seed lands the full file set in skel (ADR 0111)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local config_directory="$TEST_DIR/seed/etc/skel/.config" seed_file
  for seed_file in kdeglobals kwinrc plasmarc plasmashellrc \
    plasma-org.kde.plasma.desktop-appletsrc kglobalshortcutsrc kcminputrc \
    klipperrc kscreenlockerrc ksmserverrc dolphinrc konsolerc \
    plasma-localerc \
    kactivitymanagerdrc kactivitymanagerd-statsrc powerdevilrc \
    mimeapps.list kwinrulesrc; do
    [ -f "$config_directory/$seed_file" ] || { echo "captured file missing: $seed_file"; return 1; }
  done
}

@test "captured kwinrc pins night light to Location + coords (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local kwinrc_file="$TEST_DIR/seed/etc/skel/.config/kwinrc"
  grep -q "Mode=Location"     "$kwinrc_file"
  grep -q "LatitudeFixed=45"  "$kwinrc_file"
  grep -q "LongitudeFixed=24" "$kwinrc_file"
}

@test "captured mimeapps makes VLC the default video handler (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "video/mp4=vlc.desktop" \
    "$TEST_DIR/seed/etc/skel/.config/mimeapps.list"
}

@test "captured activities seed Default and Dev (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local activities_file="$TEST_DIR/seed/etc/skel/.config/kactivitymanagerdrc"
  grep -q "=Default" "$activities_file"
  grep -q "=Dev"     "$activities_file"
}


# ── per-Activity Kickoff favorites (ADR 0126) ───────────────────────────────
# Favorites are KActivities links (SQLite DB), not a .config key, so the adapter
# seeds a run-once first-login helper that relinks them per Activity.

@test "favorites helper + autostart seeded, linking per Activity (ADR 0126)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local helper_script="$TEST_DIR/seed/usr/local/bin/kde-seed-favorites"
  local autostart_file="$TEST_DIR/seed/etc/skel/.config/autostart/kde-seed-favorites.desktop"
  [ -x "$helper_script" ]
  [ -f "$autostart_file" ]
  grep -q "Exec=/usr/local/bin/kde-seed-favorites" "$autostart_file"
  grep -q "OnlyShowIn=KDE" "$autostart_file"
  # the launcher's own linking agent + the two Activity UUIDs + :global scope
  grep -q "org.kde.plasma.favorites.applications" "$helper_script"
  grep -q "061c3ccc-9512-4bf9-83d0-0e9d9a9daed7" "$helper_script"
  grep -q "d71c2b09-8d5a-4ce1-aa4f-d868d82a0073" "$helper_script"
  grep -q ":global" "$helper_script"
  # a representative app per scope: global / Default / Dev
  grep -q "virt-manager.desktop" "$helper_script"
  grep -q "steam.desktop"        "$helper_script"
  grep -q "org.kde.kate.desktop" "$helper_script"
  # run-once stamp guard
  grep -q "kde-favorites-seeded" "$helper_script"
}

@test "appletsrc marks favorites ported so legacy import can't race (ADR 0126)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local appletsrc="$TEST_DIR/seed/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
  grep -q "favoritesPortedToKAstats=true" "$appletsrc"
}

@test "statsrc ordering carries the per-Activity favorite sets (ADR 0126)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local statsrc_file="$TEST_DIR/seed/etc/skel/.config/kactivitymanagerd-statsrc"
  # Default ordering carries a Default-only app; Dev ordering a Dev-only app
  grep -q "instance-3-061c3ccc-9512-4bf9-83d0-0e9d9a9daed7" "$statsrc_file"
  grep -q "instance-3-d71c2b09-8d5a-4ce1-aa4f-d868d82a0073" "$statsrc_file"
  grep -A1 "061c3ccc" "$statsrc_file" | grep -q "applications:steam.desktop"
  grep -A1 "d71c2b09" "$statsrc_file" | grep -q "applications:codium.desktop"
}

@test "panel weather widget targets Ramnicu Valcea via met.no (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local appletsrc="$TEST_DIR/seed/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
  # the coordinate-capable widget replaced the stock plasmoid in the same slot
  grep -q "plugin=org.kde.weatherWidget-3" "$appletsrc"
  ! grep -q "provider=bbcukmet" "$appletsrc"          # stock Sibiu config gone
  grep -q '"providerId":"metno"' "$appletsrc"
  grep -q 'lat=45.10&lon=24.37' "$appletsrc"
  grep -q "layoutType=Compact" "$appletsrc"           # operator's compact layout
}

@test "captured Activity Pager carries the operator's settings (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local appletsrc="$TEST_DIR/seed/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
  grep -q "plugin=org.kde.plasma.activitypager" "$appletsrc"   # pager present at all
  grep -q "displayedText=Name" "$appletsrc"
  grep -q "pagerLayout=Horizontal" "$appletsrc"
}

@test "captured Total CPU Use widget renders as a pie chart (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local appletsrc="$TEST_DIR/seed/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc"
  grep -q "chartFace=org.kde.ksysguard.piechart" "$appletsrc"
  ! grep -q "chartFace=org.kde.ksysguard.barchart" "$appletsrc"
}

@test "avatar seed lands the vendored ~/.face in skel (ADR 0121)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local face="$TEST_DIR/seed/etc/skel/.face"
  [ -f "$face" ]
  # binary-safe copy: byte-identical to the vendored avatar
  cmp -s "$face" \
    "$BATS_TEST_DIRNAME/../../extras/desktop/kde/skel/.face"
}


# ── #06: first-login state (ADR 0121) ───────────────────────────────────────

@test "SDDM login background points at the Horos wallpaper (ADR 0121)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/usr/share/sddm/themes/breeze/theme.conf.user"
  [ -f "$seed_file" ]
  grep -q "background=/usr/share/wallpapers/Horos/" "$seed_file"
  grep -q "type=image" "$seed_file"
}

@test "audio-full-volume autostart raises sink and source (ADR 0121)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/etc/skel/.config/autostart/kde-audio-full-volume.desktop"
  [ -f "$seed_file" ]
  grep -q "@DEFAULT_AUDIO_SINK@ 1.0"   "$seed_file"
  grep -q "@DEFAULT_AUDIO_SOURCE@ 1.0" "$seed_file"
}

@test "welcome LastSeenVersion is stamped from the installed version (ADR 0121)" {
  # pacman -Q returns the installed version; other calls fall through to the log
  printf '#!/usr/bin/env bash\nif [ "$1" = "-Q" ]; then echo "plasma-welcome 6.7.4"; else echo "pacman $*" >> "%s"; fi\n' \
    "$PACMAN_LOG" > "$STUB_BIN/pacman"
  chmod +x "$STUB_BIN/pacman"
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/etc/skel/.config/plasma-welcomerc"
  [ -f "$seed_file" ]
  grep -q "LastSeenVersion=6.7.4" "$seed_file"
}

@test "captured kglobalshortcutsrc binds Window Close to Meta+X (ADR 0113)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -Eq 'Window Close=.*Meta\+X' \
    "$TEST_DIR/seed/etc/skel/.config/kglobalshortcutsrc"
}

# Favorites are no longer file-backed via the inline list (ADR 0126, superseding
# the legacy import): the appletsrc is marked ported so Kickoff reads KActivities
# links, and the inline favorites= carries only the :global set (Discord ∈ both).
@test "kickoff appletsrc is ported; inline favorites is the global set (ADR 0126)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local config_directory="$TEST_DIR/seed/etc/skel/.config"
  grep -q "^favoritesPortedToKAstats=true" \
    "$config_directory/plasma-org.kde.plasma.desktop-appletsrc"
  grep -q "^favorites=.*discord.desktop" \
    "$config_directory/plasma-org.kde.plasma.desktop-appletsrc"
}

@test "captured kwin seeds virtual desktops, plugins and 30-min lock" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local config_directory="$TEST_DIR/seed/etc/skel/.config"
  grep -q "wobblywindowsEnabled=true" "$config_directory/kwinrc"
  grep -q "Timeout=30" "$config_directory/kscreenlockerrc"
  grep -q "loginMode=emptySession" "$config_directory/ksmserverrc"
}

# The host-specific monitor/output config is NOT seeded (ADR 0110) — resolution
# stays autodetected.
@test "captured seed excludes the host-specific output config (ADR 0110)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local config_directory="$TEST_DIR/seed/etc/skel/.config"
  [ ! -e "$config_directory/kscreenrc" ]
  [ ! -e "$config_directory/kwinoutputconfig.json" ]
}

@test "theme seed sets the Bibata Modern Ice cursor (ADR 0098)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "cursorTheme=Bibata-Modern-Ice" \
    "$TEST_DIR/seed/etc/skel/.config/kcminputrc"
  # non-KDE (GTK/X) apps follow via ~/.icons/default
  grep -q "Inherits=Bibata-Modern-Ice" \
    "$TEST_DIR/seed/etc/skel/.icons/default/index.theme"
}

@test "SDDM theme drop-in is Breeze in its own file (no session-dir clobber)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/etc/sddm.conf.d/20-kde-theme.conf"
  [ -f "$seed_file" ]
  grep -q "Current=breeze" "$seed_file"
  # dm-sddm owns 10-session-dirs.conf; the KDE theme uses a distinct filename.
  [ ! -e "$TEST_DIR/seed/etc/sddm.conf.d/10-session-dirs.conf" ]
}
