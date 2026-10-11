#!/usr/bin/env bats
# Tests: first run and package lists (split from kde-adapter.bats;
# shared setup in kde-adapter-helpers.bash)

load kde-adapter-helpers


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

# ADR 0116/0123: on a COMBINED box (kde + a wlroots compositor) a Noctalia
# session leaves the shared GTK theme, kdeglobals colours (kcolorscheme is on,
# ADR 0123) and cursor non-Breeze, and Plasma does not self-reset them, so seed a
# KDE-only autostart + helper that reasserts the Breeze look on Plasma login.
@test "combined box seeds the KDE session reset (ADR 0116/0123)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde niri" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local autostart_file="$TEST_DIR/seed/etc/skel/.config/autostart/kde-session-reset.desktop"
  local helper_script="$TEST_DIR/seed/usr/local/bin/kde-session-reset"
  grep -q '^Exec=/usr/local/bin/kde-session-reset' "$autostart_file"
  grep -q '^OnlyShowIn=KDE;' "$autostart_file"
  [ -x "$helper_script" ]
  grep -q 'gtk-theme Breeze' "$helper_script"
  grep -q 'plasma-apply-colorscheme BreezeDark' "$helper_script"
  grep -q 'kreadconfig6 --file kcminputrc' "$helper_script"   # cursor honours KDE choice
}

# On a PURE KDE box the reset must NOT be seeded — it would clobber the operator's
# own look on every login.
@test "pure KDE box does not seed the KDE session reset (ADR 0116/0123)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -f \
    "$TEST_DIR/seed/etc/skel/.config/autostart/kde-session-reset.desktop" ]
  [ ! -f "$TEST_DIR/seed/usr/local/bin/kde-session-reset" ]
}

# ADR 0122: on a COMBINED box the compositor exports QT_QPA_PLATFORMTHEME=qt6ct
# into the shared systemd --user env, which leaks into a same-boot Plasma login;
# seed a Plasma env script that strips it so KDE apps stay Breeze.
@test "combined box seeds the Qt platform-theme un-leak env script (ADR 0122)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde hyprland" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/etc/skel/.config/plasma-workspace/env/kde-unset-qt-platformtheme.sh"
  grep -q 'unset QT_QPA_PLATFORMTHEME' "$seed_file"
  grep -q 'systemctl --user unset-environment QT_QPA_PLATFORMTHEME' "$seed_file"
}

# On a PURE KDE box the un-leak script must NOT be seeded — there is no
# compositor to export the var, so it would be dead payload.
@test "pure KDE box does not seed the Qt platform-theme un-leak (ADR 0122)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run env ENVIRONMENT_DESKTOP="kde" \
    bash "$ADAPTER"
  [ "$status" -eq 0 ]
  [ ! -f \
    "$TEST_DIR/seed/etc/skel/.config/plasma-workspace/env/kde-unset-qt-platformtheme.sh" ]
}

# ADR 0125: Dolphin ships with the embedded Terminal panel hidden. Visibility
# lives only in the base64 QMainWindow state (no KConfig key), so seed a
# dolphinstaterc whose terminalDock flag is hidden.
@test "Dolphin is seeded without the terminal panel (ADR 0125)" {
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local seed_file="$TEST_DIR/seed/etc/skel/.local/state/dolphinstaterc"
  grep -q '^\[State\]' "$seed_file"
  grep -q '^State=' "$seed_file"
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
  [ "$(awk 'END { print NR }' <<<"$output")" -eq 34 ]
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
  local package
  # Old non-applications (relocated / redundant) plus this round's prunes:
  # karbon (⊂ calligra), kclock (mobile), skanlite (⊂ skanpage), arianna
  # (Okular covers EPUB), kgpg (kleopatra kept), kompare (→ kdiff3),
  # keditbookmarks (unrequested).
  for package in sddm-kcm xdg-desktop-portal-kde kimageformats5 pacmanlogviewer \
           octopi karbon kclock skanlite arianna kgpg kompare keditbookmarks; do
    ! grep -qx "$package" <<<"$names" || { echo "still declared: $package"; return 1; }
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

@test "calendar plugins survive Plasma's broken id migration (Audit 20261003)" {
  # migrate-calendar-to-plugin-id.py does `list += str` on entries already in
  # id form, char-splitting them on first login. Seed the skel as already
  # migrated so kconf_update skips it.
  cat > "$KDE_JSON" <<'JSON'
{"shell":true,"apps":false,"apps_list":{}}
JSON
  KDE_SEED_ROOT="$TEST_DIR/seed" run bash "$ADAPTER"
  [ "$status" -eq 0 ]
  local config_directory="$TEST_DIR/seed/etc/skel/.config"
  grep -qx 'enabledCalendarPlugins=astronomicalevents,holidaysevents' \
    "$config_directory/plasma-org.kde.plasma.desktop-appletsrc"
  grep -A2 -Fx '[migrate-calendar-to-plugin-id.upd]' "$config_directory/kconf_updaterc" \
    | grep -qx 'done=migrate-calendar-plugins'
}
