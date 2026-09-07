#!/usr/bin/env bats
# Tests for extras/desktop/kde/kde.sh.
#
# Strategy: run the adapter as a subprocess with pacman and systemctl stubbed
# as executables in a temp bin dir prepended to PATH. Injectable seam:
#   KDE_JSON — path to install-kde.jsonc
#
# apps_list is the 2-level Categorized List shape { category: { pkg: bool } },
# consumed via the Categorized List Parser in bool mode.

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"

  PACMAN_LOG="$TEST_DIR/pacman.log"
  SYSTEMCTL_LOG="$TEST_DIR/systemctl.log"
  KDE_JSON="$TEST_DIR/install-kde.jsonc"
  ADAPTER="$BATS_TEST_DIRNAME/../../extras/desktop/kde/kde.sh"
  # Seed DE defaults into the temp tree, never the real /etc/skel.
  KDE_SEED_ROOT="$TEST_DIR/seed"

  export PACMAN_LOG SYSTEMCTL_LOG KDE_JSON KDE_SEED_ROOT

  printf '#!/usr/bin/env bash\necho "pacman $*" >> "$PACMAN_LOG"\n' \
    > "$STUB_BIN/pacman"
  printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$SYSTEMCTL_LOG"\n' \
    > "$STUB_BIN/systemctl"
  chmod +x "$STUB_BIN/pacman" "$STUB_BIN/systemctl"

  export PATH="$STUB_BIN:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

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
  local kg="$TEST_DIR/seed/etc/skel/.config/kdeglobals"
  [ -f "$kg" ]
  grep -q "widgetStyle=Breeze" "$kg"
  grep -q "Theme=Papirus-Dark" "$kg"
  grep -q "LookAndFeelPackage=org.kde.breezedark.desktop" "$kg"
  # the custom scheme rides inline: a [Colors:*] section + the faster animations
  grep -q "^\[Colors:View\]" "$kg"
  grep -q "AnimationDurationFactor=" "$kg"
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
  local d="$TEST_DIR/seed/etc/skel/.config" f
  for f in kdeglobals kwinrc plasmarc plasmashellrc \
    plasma-org.kde.plasma.desktop-appletsrc kglobalshortcutsrc kcminputrc \
    klipperrc kscreenlockerrc ksmserverrc dolphinrc konsolerc \
    plasma-localerc \
    kactivitymanagerdrc kactivitymanagerd-statsrc powerdevilrc \
    mimeapps.list kwinrulesrc; do
    [ -f "$d/$f" ] || { echo "captured file missing: $f"; return 1; }
  done
}

@test "captured kwinrc pins night light to Location + coords (ADR 0120)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local kw="$TEST_DIR/seed/etc/skel/.config/kwinrc"
  grep -q "Mode=Location"     "$kw"
  grep -q "LatitudeFixed=45"  "$kw"
  grep -q "LongitudeFixed=24" "$kw"
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
  local ka="$TEST_DIR/seed/etc/skel/.config/kactivitymanagerdrc"
  grep -q "=Default" "$ka"
  grep -q "=Dev"     "$ka"
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
  local f="$TEST_DIR/seed/usr/share/sddm/themes/breeze/theme.conf.user"
  [ -f "$f" ]
  grep -q "background=/usr/share/wallpapers/Horos/" "$f"
  grep -q "type=image" "$f"
}

@test "audio-full-volume autostart raises sink and source (ADR 0121)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local f="$TEST_DIR/seed/etc/skel/.config/autostart/kde-audio-full-volume.desktop"
  [ -f "$f" ]
  grep -q "@DEFAULT_AUDIO_SINK@ 1.0"   "$f"
  grep -q "@DEFAULT_AUDIO_SOURCE@ 1.0" "$f"
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
  local f="$TEST_DIR/seed/etc/skel/.config/plasma-welcomerc"
  [ -f "$f" ]
  grep -q "LastSeenVersion=6.7.4" "$f"
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

# Discord is a global (all-activities) kickoff favorite: the seeded kickoff is
# file-backed (favoritesPortedToKAstats=false) so the favorites list imports to
# KActivities globally on first login.
@test "captured kickoff favorites are file-backed and include Discord" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local d="$TEST_DIR/seed/etc/skel/.config"
  grep -q "^favoritesPortedToKAstats=false" \
    "$d/plasma-org.kde.plasma.desktop-appletsrc"
  grep -q "^favorites=.*discord.desktop" \
    "$d/plasma-org.kde.plasma.desktop-appletsrc"
}

@test "captured kwin seeds virtual desktops, plugins and 30-min lock" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local d="$TEST_DIR/seed/etc/skel/.config"
  grep -q "wobblywindowsEnabled=true" "$d/kwinrc"
  grep -q "Timeout=30" "$d/kscreenlockerrc"
  grep -q "loginMode=emptySession" "$d/ksmserverrc"
}

# The host-specific monitor/output config is NOT seeded (ADR 0110) — resolution
# stays autodetected.
@test "captured seed excludes the host-specific output config (ADR 0110)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local d="$TEST_DIR/seed/etc/skel/.config"
  [ ! -e "$d/kscreenrc" ]
  [ ! -e "$d/kwinoutputconfig.json" ]
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
  local f="$TEST_DIR/seed/etc/sddm.conf.d/20-kde-theme.conf"
  [ -f "$f" ]
  grep -q "Current=breeze" "$f"
  # dm-sddm owns 10-session-dirs.conf; the KDE theme uses a distinct filename.
  [ ! -e "$TEST_DIR/seed/etc/sddm.conf.d/10-session-dirs.conf" ]
}

# ── first-run suppression seeding (ADR 0088, Q4-B) ──────────────────────────

@test "Plasma Welcome Center autostart is hidden" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "Hidden=true" \
    "$TEST_DIR/seed/etc/skel/.config/autostart/plasma-welcome.desktop"
}

# ADR 0116: on a COMBINED box (kde + a wlroots compositor) a Noctalia session
# leaves the shared GTK theme non-Breeze and kde-gtk-config does not auto-reset
# it, so seed a KDE-only autostart that reasserts Breeze on Plasma login.
@test "combined box seeds the GTK Breeze reset autostart (ADR 0116)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde niri" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local f="$TEST_DIR/seed/etc/skel/.config/autostart/kde-gtk-breeze-reset.desktop"
  grep -q 'gtk-theme Breeze' "$f"
  grep -q '^OnlyShowIn=KDE;' "$f"
}

# On a PURE KDE box the reset must NOT be seeded — it would clobber the operator's
# own GTK theme on every login.
@test "pure KDE box does not seed the GTK Breeze reset (ADR 0116)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -f \
    "$TEST_DIR/seed/etc/skel/.config/autostart/kde-gtk-breeze-reset.desktop" ]
}

@test "Baloo indexing is left enabled" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "Indexing-Enabled=true" "$TEST_DIR/seed/etc/skel/.config/baloofilerc"
}

@test "a default Konsole profile is pre-created and selected" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/seed/etc/skel/.local/share/konsole/Default.profile" ]
  grep -q "DefaultProfile=Default.profile" \
    "$TEST_DIR/seed/etc/skel/.config/konsolerc"
}

@test "Dolphin config version is stamped to suppress migration popups" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "Version=" "$TEST_DIR/seed/etc/skel/.config/dolphinrc"
}

# ── stock (pure) KDE (ADR 0112) ─────────────────────────────────────────────
# With ENVIRONMENT_STOCK set, KDE is upstream-stock: the plasma-meta shell only,
# no captured seed and no apps.

@test "stock KDE installs the shell but seeds nothing captured" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":true,"shell_packages":{"core":{"sentinel-shell":true}},
"apps_list":{"files":{"sentinel-app":true}}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" ENVIRONMENT_STOCK=true run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-shell" "$PACMAN_LOG"
  [ ! -e "$TEST_DIR/seed/etc/skel/.config/kdeglobals" ]
  [ ! -e "$TEST_DIR/seed/etc/skel/.config/kglobalshortcutsrc" ]
}

@test "stock KDE installs no applications" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":true,"shell_packages":{"core":{"sentinel-shell":true}},
"apps_list":{"files":{"sentinel-app":true}}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" ENVIRONMENT_STOCK=true run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  ! grep -q "sentinel-app" "$PACMAN_LOG"
}

# ── malformed apps_list aborts the install ──────────────────────────────────

@test "old flat shape (bool leaf at top) aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"ark":true}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_list.ark"* ]]
  [[ "$output" == *"expected object"* ]]
}

@test "non-bool leaf aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"files":{"dolphin":"yes"}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_list.files.dolphin"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

@test "invalid category name aborts with parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{"Bad_Cat":{"dolphin":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid category name"* ]]
}

# ── apps_extra (categorized, bool mode) ─────────────────────────────────────
# apps_extra installs in the same pacman pass as apps_list (ADR 0087).

@test "selected app under apps_extra is installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"sentinel-extra":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-extra" "$PACMAN_LOG"
}

@test "deselected apps_extra leaf (false) is not installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"sentinel-keep":true,"sentinel-drop":false}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-keep" "$PACMAN_LOG"
  ! grep -q "sentinel-drop" "$PACMAN_LOG"
}

@test "malformed apps_extra aborts with a pathed parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"apps_extra":{"gfx":{"krita":"yes"}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"apps_extra.gfx.krita"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

# ── plugins (categorized, bool mode) ────────────────────────────────────────
# plugins are per-app optdepend enhancers (ADR 0088), same install pass.

@test "selected plugin is installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"plugins":{"dolphin":{"sentinel-plugin":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-plugin" "$PACMAN_LOG"
}

@test "deselected plugin (false) is not installed" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"plugins":{"dolphin":{"sentinel-keep":true,"sentinel-drop":false}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  grep -q "sentinel-keep" "$PACMAN_LOG"
  ! grep -q "sentinel-drop" "$PACMAN_LOG"
}

@test "a package shared across app sections installs once" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"plugins":{"gwenview":{"shared-fmt":true},"digikam":{"shared-fmt":true}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ "$(grep -c "shared-fmt" "$PACMAN_LOG")" -eq 1 ]
}

@test "malformed plugins aborts with a pathed parser error" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":false,"apps":true,"apps_list":{},
"plugins":{"dolphin":{"kio-admin":"yes"}}}
JSON
  run bash "$ADAPTER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins.dolphin.kio-admin"* ]]
  [[ "$output" == *"expected boolean leaf"* ]]
}

# ── shipped install-kde.jsonc regression lock ───────────────────────────────

# apps_list holds exactly the operator's kde-applications-group roster plus the
# three plasma-group no-ops (spectacle / plasma-systemmonitor / discover) that
# plasma-meta already pulls. Membership is mechanical (R21, ADR 0087): a repo
# app belongs here iff its pacman Groups contains `kde-applications`; every
# non-group KDE app lives in apps_extra instead.
@test "shipped apps_list matches the curated roster" {
  # shellcheck source=../../lib/common.sh
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  # shellcheck source=../../lib/config/categorized-list.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local apps_json
  apps_json="$(jsonc "$real" | jq -c '.apps_list')"

  run categorized_list_parse "$apps_json" bool apps_list
  [ "$status" -eq 0 ]
  [ "$(wc -l <<<"$output")" -eq 34 ]
  [ "$(sort <<<"$output")" = "$(printf '%s\n' \
    ark calligra discover dolphin elisa filelight ghostwriter gwenview \
    isoimagewriter k3b kate kcalc kcolorchooser kdeconnect kdenlive keysmith \
    kfind kiten kleopatra kmag kolourpaint konsole krdc krfb ktorrent \
    kwalletmanager merkuro okular partitionmanager plasma-systemmonitor \
    skanpage spectacle sweeper yakuake | sort)" ]
}

# apps_extra holds the non-group KDE-ecosystem apps plus the two non-KDE apps the
# operator's KDE experience wants: vlc (default video player) and orca (screen
# reader) — ADR 0120.
@test "shipped apps_extra is exactly the non-group apps (incl. vlc, orca)" {
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local extra_json
  extra_json="$(jsonc "$real" | jq -c '.apps_extra')"

  run categorized_list_parse "$extra_json" bool apps_extra
  [ "$status" -eq 0 ]
  [ "$(sort <<<"$output")" = "$(printf '%s\n' \
    digikam haruna kdiff3 kommit krename krusader krita okteta orca vlc \
    | sort)" ]
}

@test "shipped plugins is exactly the curated enhancer set" {
  source "$BATS_TEST_DIRNAME/../../lib/common.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/categorized-list.sh"
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  local plugins_json
  plugins_json="$(jsonc "$real" | jq -c '.plugins')"

  run categorized_list_parse "$plugins_json" bool plugins
  [ "$status" -eq 0 ]
  [ "$(sort <<<"$output")" = "$(printf '%s\n' \
    darktable dolphin-plugins ebook-tools ffmpegthumbs kde-cli-tools \
    kdegraphics-mobipocket kdegraphics-thumbnailers kimageformats kio-admin \
    krita-plugin-gmic noise-suppression-for-voice opencv qt6-imageformats \
    recordmydesktop sshfs | sort)" ]
}

@test "Ark backends are not duplicated into plugins (they live in Host Core)" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local names
  names="$(jsonc_strip "$real" \
    | jq -r '.plugins | to_entries[].value | keys[]')"
  ! grep -qx "7zip" <<<"$names"
  ! grep -qx "unrar" <<<"$names"
}

@test "the plasma-extras category is gone" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  # shellcheck source=../../lib/jsonc.sh
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  jsonc_strip "$real" | jq -e '.apps_list | has("plasma-extras") | not'
}

@test "the pruned/removed apps appear in no section" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local names
  names="$(jsonc_strip "$real" | jq -r '
    [(.apps_list // {}), (.apps_extra // {}), (.plugins // {})]
    | .[] | to_entries[].value | keys[]')"
  local p
  # Old non-applications (relocated / redundant) plus this round's prunes:
  # karbon (⊂ calligra), kclock (mobile), skanlite (⊂ skanpage), arianna
  # (Okular covers EPUB), kgpg (kleopatra kept), kompare (→ kdiff3),
  # keditbookmarks (unrequested).
  for p in sddm-kcm xdg-desktop-portal-kde kimageformats5 pacmanlogviewer \
           octopi karbon kclock skanlite arianna kgpg kompare keditbookmarks; do
    ! grep -qx "$p" <<<"$names" || { echo "still declared: $p"; return 1; }
  done
}

# octopi (a Qt pacman GUI) is KDE-tied by operator decision (ADR 0094) and ships
# via the adapter aur; pacmanlogviewer is not KDE and stays a Host Core package.
@test "octopi ships via the KDE adapter aur; pacmanlogviewer does not" {
  local real="$BATS_TEST_DIRNAME/../../extras/desktop/kde/install-kde.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  local all
  all="$(jsonc_strip "$real" | jq -r '
    [(.apps_list // {}), (.aur // {})] | .[] | to_entries[].value | keys[]')"
  grep -qx "octopi" <<<"$all"
  ! grep -qx "pacmanlogviewer" <<<"$all"
}

# pacmanlogviewer is not KDE — it stays a Host Core package so both machines get
# it. octopi moved OUT of Host Core into the KDE adapter aur (ADR 0094).
@test "pacmanlogviewer is Host Core; octopi is not host-declared" {
  local core="$BATS_TEST_DIRNAME/../../hosts/core/profile.jsonc"
  source "$BATS_TEST_DIRNAME/../../lib/jsonc.sh"
  jsonc_strip "$core" | jq -e '[.packages.repo | to_entries[].value[]]
    | index("pacmanlogviewer")'
  ! jsonc_strip "$core" | jq -e '[.packages.aur | to_entries[].value[]]
    | index("octopi")'
}
