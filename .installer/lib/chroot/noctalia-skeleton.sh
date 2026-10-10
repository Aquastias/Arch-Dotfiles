#!/usr/bin/env bash
# =============================================================================
# lib/chroot/noctalia-skeleton.sh — seed the curated Noctalia config into
# /etc/skel
# =============================================================================
# Used by: lib/chroot/noctalia-preset.sh (sources it). Seeds, never stows: a
# fresh box boots the full look by default (ADR 0095/0097) while the same files
# stay independently stowable. Reads NOCTALIA_CURATED_DIR and NOCTALIA_SEED_ROOT
# (see noctalia-preset.sh).
# =============================================================================

# noctalia_skeleton_seed <config_source> <config_destination> — the compositor
# config, the shared Noctalia files, and the GTK/Qt/palette theme seeds. Single
# source — chroot.sh staged these from the repo's .config/.local into
# NOCTALIA_CURATED_DIR. The shared config.toml + helpers are byte-identical
# across compositors; only the compositor config (config_source) differs.
noctalia_skeleton_seed() {
  local config_source="$1" config_destination="$2"
  section "Noctalia curated config"
  if [[ ! -d "$NOCTALIA_CURATED_DIR" ]]; then
    warn "Curated config dir absent (${NOCTALIA_CURATED_DIR}) —" \
         "skel gets no Noctalia config."
    return 0
  fi
  local skeleton="${NOCTALIA_SEED_ROOT%/}/etc/skel"
  _noctalia_skeleton_seed_compositor_config "$skeleton" "$config_source" \
    "$config_destination"
  _noctalia_skeleton_seed_shell_files "$skeleton"
  _noctalia_skeleton_seed_desktop_defaults "$skeleton"
  _noctalia_skeleton_seed_gtk_settings "$skeleton"
  _noctalia_skeleton_seed_qt_theme "$skeleton"
  _noctalia_skeleton_seed_offline_palette "$skeleton"
  info "Curated Noctalia config + cursor + GTK/Qt theming seeded to /etc/skel."
}

_noctalia_skeleton_seed_compositor_config() {
  local skeleton="$1" config_source="$2" config_destination="$3"
  install -Dm644 "${NOCTALIA_CURATED_DIR}/${config_source}" \
    "${skeleton}/${config_destination}"
  # Split config (ADR 0107): the entry file (cfg_src) is a pure manifest of
  # include/require lines; the settings live in a sibling conf.d/ tree, which
  # always ships beside it.
  local _dropin_source _dropin_destination
  _dropin_source="${NOCTALIA_CURATED_DIR}"
  _dropin_source+="/$(parent_directory "$config_source")/conf.d"
  _dropin_destination="${skeleton}"
  _dropin_destination+="/$(parent_directory "$config_destination")/conf.d"
  install -d "$_dropin_destination"
  install -m644 "$_dropin_source"/* "$_dropin_destination/"
  # VM-only software cursor: virtio-gpu's DRM cursor plane is buggy in a guest
  # and the pointer renders as a broken "X". Force software cursors by machine
  # TYPE — injected here, NOT shipped in the stow'd config — so real hardware
  # keeps the optimal hardware cursor. Appended to the conf.d/environment
  # part-file (branch on suffix) so the seeded manifest stays pure (ADR 0107):
  # niri a debug{} block, Hyprland an hl.config cursor (Lua, ADR 0105).
  # (Harmless if detect-virt is unavailable — no-ops, real-HW config stands.)
  if systemd-detect-virt --vm --quiet 2>/dev/null; then
    local _current_extension="${config_destination##*.}"
    local _current_target
    _current_target="${_dropin_destination}/environment.${_current_extension}"
    case "$_current_extension" in
    kdl)
      printf '\ndebug {\n    disable-cursor-plane\n}\n' >> "$_current_target" ;;
    lua)
      printf '\nhl.config({ cursor = { no_hardware_cursors = true } })\n' \
        >> "$_current_target" ;;
    esac
    info "VM detected — SW-cursor override seeded into ${_current_target##*/}."
  fi
}

_noctalia_skeleton_seed_shell_files() {
  local skeleton="$1"
  install -Dm644 "${NOCTALIA_CURATED_DIR}/.config/noctalia/config.toml" \
    "${skeleton}/.config/noctalia/config.toml"
  # kcolorscheme merges Noctalia's palette into the SHARED ~/.config/kdeglobals,
  # so KDE-framework apps (Dolphin/Gwenview/Kate) follow the shell palette under
  # a compositor (ADR 0108). Enabled on EVERY Noctalia box now (ADR 0123),
  # combined included: on a combined box `kde.sh` seeds a KDE-login "session
  # reset" that reasserts BreezeDark, so the shared kdeglobals is a login-time
  # tug-of-war that always lands Breeze under Plasma — the same pattern the GTK
  # theme already uses (ADR 0116). Superseded reasoning: ADR 0104/0108 kept it
  # off on combined boxes for lack of that reset. Injected into the SEEDED copy
  # (not the committed config.toml) so a hand-stow without the installer's KDE
  # reset never leaks; the injection and the reset ship together per install.
  sed -i '/^[[:space:]]*builtin_ids = \[/a\        "kcolorscheme",' \
    "${skeleton}/.config/noctalia/config.toml"
  info "Enabled kcolorscheme so KDE-framework apps follow Noctalia (ADR 0123)."
  # User-template inputs (ADR 0128/0129): config.toml declares
  # [theme.templates.user.*] (pi, zsh, p10k-accent); their input_path files
  # live here. Seed the whole dir so Noctalia can render them on a seed-only
  # box — otherwise the templates are declared but absent and live
  # palette-follow silently no-ops (only builtin templates run).
  if [[ -d "${NOCTALIA_CURATED_DIR}/.config/noctalia/templates" ]]; then
    install -d "${skeleton}/.config/noctalia/templates"
    install -m644 "${NOCTALIA_CURATED_DIR}"/.config/noctalia/templates/* \
      "${skeleton}/.config/noctalia/templates/"
    info "Seeded Noctalia user-templates (live palette-follow: pi, zsh)."
  fi
  install -d "${skeleton}/.local/bin"
  install -m755 "${NOCTALIA_CURATED_DIR}"/.local/bin/noctalia-* \
    "${skeleton}/.local/bin/"
}

# The desktop defaults a compositor box needs on first login: the file
# manager, the cursor, and no setup wizard in the way.
_noctalia_skeleton_seed_desktop_defaults() {
  local skeleton="$1"
  # pcmanfm-qt (the shared file manager, ADR 0100): its curated settings +
  # right-click custom actions (Open in kitty / Copy path / Duplicate). Same
  # single-source copy as the rest — stays independently stowable.
  local settings=".config/pcmanfm-qt/lxqt/settings.conf"
  install -Dm644 "${NOCTALIA_CURATED_DIR}/${settings}" \
    "${skeleton}/${settings}"
  install -d "${skeleton}/.local/share/file-manager/actions"
  install -m644 \
    "${NOCTALIA_CURATED_DIR}"/.local/share/file-manager/actions/*.desktop \
    "${skeleton}/.local/share/file-manager/actions/"
  # Default cursor for GTK/XWayland apps (ADR 0098): ~/.icons/default inherits
  # Bibata Modern Ice, matching the compositor's XCURSOR_THEME. KDE seeds its
  # own copy; niri/Hyprland get theirs here (one line, no per-user state).
  install -d "${skeleton}/.icons/default"
  printf '[Icon Theme]\nInherits=Bibata-Modern-Ice\n' \
    > "${skeleton}/.icons/default/index.theme"
  # Suppress Noctalia's first-run setup wizard (ADR 0088 precedent: an
  # adapter marks first-run state so a fresh login is ready, as KDE's
  # Welcome Center does). Noctalia opens the wizard as a modal panel when
  # the marker file is absent, and only ONE panel may be open, so every bar
  # click (clock -> calendar, ...) is a no-op until dismissed. Seeding the
  # empty marker is byte-identical to finishing/closing the wizard (writes
  # the same empty file); the feature stays available (setup_wizard_enabled
  # untouched). The marker is state not config, so seeded, never stowed;
  # respects XDG_STATE_HOME, default ~/.local/state (what skel seeds).
  install -Dm644 /dev/null \
    "${skeleton}/.local/state/noctalia/.setup-complete"
}

_noctalia_skeleton_seed_gtk_settings() {
  local skeleton="$1"
  # GTK settings.ini — SEEDED, never stowed (ADR 0104). kde-gtk-config
  # rewrites these at every Plasma login; through a stow symlink that write
  # lands in the dotfiles repo (perpetual git dirt). A real skel file lets
  # Plasma own them on KDE while a compositor keeps adw-gtk3-dark here +
  # Noctalia's live gtk.css colors. gtk-4.0 carries no theme name so
  # libadwaita follows gtk.css (ADR 0102). Host-neutral: no DPI/scaling.
  install -Dm644 /dev/stdin "${skeleton}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-button-images=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-size=24
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=0
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=Papirus-Dark
gtk-menu-images=true
gtk-primary-button-warps-slider=true
gtk-sound-theme-name=ocean
gtk-theme-name=adw-gtk3-dark
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-toolbar-style=3
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF
  install -Dm644 /dev/stdin "${skeleton}/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-size=24
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=Papirus-Dark
gtk-primary-button-warps-slider=true
gtk-sound-theme-name=ocean
EOF
}

_noctalia_skeleton_seed_qt_theme() {
  local skeleton="$1"
  # qt6ct pre-seed — the App Theming Bridge's Qt half (ADR 0102), SEEDED not
  # stowed (ADR 0108): a fresh box never stows (ADR 0095), so the stow-only
  # qt6ct.conf never arrived and every Qt/KDE app rendered default white. It now
  # points qt6ct at Noctalia's KColorScheme `.colors` (ADR 0124), so qt6ct-kde
  # applies the FULL scheme and KColorScheme apps (Dolphin) follow the accent
  # roles, not just the base palette. Compositor-private — Plasma uses
  # plasma-integration and never reads it, so it is safe on a combined box
  # (0104).
  install -Dm644 "${NOCTALIA_CURATED_DIR}/.config/qt6ct/qt6ct.conf" \
    "${skeleton}/.config/qt6ct/qt6ct.conf"
  # Boot-race belt (ADR 0108/0124): qt6ct.conf points at
  # ~/.local/share/color-schemes/noctalia.colors, which the kcolorscheme
  # template (ADR 0123) only writes once Noctalia's daemon first applies. Seed a
  # static snapshot of the default palette's KColorScheme so an app launched in
  # the sub-second before that first apply is themed, not white, AND the dir
  # exists for the Live Theme Bridge's watch. Noctalia OVERWRITES it on first
  # apply (self-heals). Seed-only (never stowed — a stow symlink would push
  # Noctalia's write into the repo, 0104). Update with the default palette
  # (0109).
  install -Dm644 /dev/stdin \
    "${skeleton}/.local/share/color-schemes/noctalia.colors" <<'EOF'
[General]
ColorScheme=Noctalia
Name=noctalia

[Colors:Button]
BackgroundAlternate=39,40,57
BackgroundNormal=58,59,80
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=205,214,244
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[Colors:Complementary]
BackgroundAlternate=39,40,57
BackgroundNormal=30,30,46
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=211,239,251
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[Colors:Header]
BackgroundAlternate=30,30,46
BackgroundNormal=49,50,68
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=205,214,244
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[Colors:Selection]
BackgroundAlternate=39,40,57
BackgroundNormal=116,199,236
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=30,30,46
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=187,16,64
ForegroundNeutral=24,147,170
ForegroundNormal=30,30,46
ForegroundPositive=24,147,170
ForegroundVisited=206,224,253

[Colors:Tooltip]
BackgroundAlternate=30,30,46
BackgroundNormal=49,50,68
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=205,214,244
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[Colors:View]
BackgroundAlternate=49,50,68
BackgroundNormal=30,30,46
DecorationFocus=211,239,251
DecorationHover=30,30,46
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=205,214,244
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[Colors:Window]
BackgroundAlternate=18,113,156
BackgroundNormal=49,50,68
DecorationFocus=116,199,236
DecorationHover=116,199,236
ForegroundActive=116,199,236
ForegroundInactive=166,173,200
ForegroundLink=137,180,250
ForegroundNegative=243,139,168
ForegroundNeutral=137,220,235
ForegroundNormal=205,214,244
ForegroundPositive=137,220,235
ForegroundVisited=206,224,253

[WM]
activeBackground=18,113,156
activeBlend=211,239,251
activeForeground=211,239,251
inactiveBackground=30,30,46
inactiveBlend=166,173,200
inactiveForeground=166,173,200
EOF
}

_noctalia_skeleton_seed_offline_palette() {
  local skeleton="$1"
  # Offline default palette (ADR 0109): the default is the COMMUNITY palette
  # "Catppuccin Mocha Sapphire", normally fetched from api.noctalia.dev. Seed
  # its cache JSON so first boot resolves it with ZERO network — Noctalia reads
  # $XDG_STATE_HOME/noctalia/community-palettes/<url-encoded-name>.json (the %20
  # is its URL-encoding of the space). Seed-only; without it an offline first
  # boot falls back to builtin Catppuccin (Mocha, mauve accent) until network.
  local palette="${skeleton}/.local/state/noctalia"
  palette+="/community-palettes/Catppuccin%20Mocha%20Sapphire.json"
  install -Dm644 /dev/stdin "$palette" <<'EOF'
{
  "dark": {
    "mPrimary": "#74c7ec",
    "mOnPrimary": "#1e1e2e",
    "mSecondary": "#89b4fa",
    "mOnSecondary": "#1e1e2e",
    "mTertiary": "#89dceb",
    "mOnTertiary": "#1e1e2e",
    "mError": "#f38ba8",
    "mOnError": "#1e1e2e",
    "mSurface": "#1e1e2e",
    "mOnSurface": "#cdd6f4",
    "mSurfaceVariant": "#313244",
    "mOnSurfaceVariant": "#a6adc8",
    "mOutline": "#6c7086",
    "mShadow": "#11111b",
    "mHover": "#45475a",
    "mOnHover": "#cdd6f4",
    "terminal": {
      "normal": {
        "black": "#45475a",
        "red": "#f38ba8",
        "green": "#a6e3a1",
        "yellow": "#f9e2af",
        "blue": "#89b4fa",
        "magenta": "#f5c2e7",
        "cyan": "#94e2d5",
        "white": "#bac2de"
      },
      "bright": {
        "black": "#585b70",
        "red": "#f38ba8",
        "green": "#a6e3a1",
        "yellow": "#f9e2af",
        "blue": "#89b4fa",
        "magenta": "#f5c2e7",
        "cyan": "#94e2d5",
        "white": "#a6adc8"
      },
      "foreground": "#cdd6f4",
      "background": "#1e1e2e",
      "selectionFg": "#cdd6f4",
      "selectionBg": "#585b70",
      "cursorText": "#1e1e2e",
      "cursor": "#f5e0dc"
    }
  },
  "light": {
    "mPrimary": "#209fb5",
    "mOnPrimary": "#eff1f5",
    "mSecondary": "#1e66f5",
    "mOnSecondary": "#eff1f5",
    "mTertiary": "#04a5e5",
    "mOnTertiary": "#eff1f5",
    "mError": "#d20f39",
    "mOnError": "#eff1f5",
    "mSurface": "#eff1f5",
    "mOnSurface": "#4c4f69",
    "mSurfaceVariant": "#ccd0da",
    "mOnSurfaceVariant": "#6c6f85",
    "mOutline": "#9ca0b0",
    "mShadow": "#dce0e8",
    "mHover": "#bcc0cc",
    "mOnHover": "#4c4f69",
    "terminal": {
      "normal": {
        "black": "#5c5f77",
        "red": "#d20f39",
        "green": "#40a02b",
        "yellow": "#df8e1d",
        "blue": "#1e66f5",
        "magenta": "#ea76cb",
        "cyan": "#179299",
        "white": "#acb0be"
      },
      "bright": {
        "black": "#6c6f85",
        "red": "#d20f39",
        "green": "#40a02b",
        "yellow": "#df8e1d",
        "blue": "#1e66f5",
        "magenta": "#ea76cb",
        "cyan": "#179299",
        "white": "#bcc0cc"
      },
      "foreground": "#4c4f69",
      "background": "#eff1f5",
      "selectionFg": "#4c4f69",
      "selectionBg": "#acb0be",
      "cursorText": "#eff1f5",
      "cursor": "#dc8a78"
    }
  }
}
EOF
}
