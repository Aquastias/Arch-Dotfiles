#!/usr/bin/env bash
# =============================================================================
# lib/chroot/noctalia-preset.sh — the shared Noctalia work-shell preset
# =============================================================================
# The Noctalia preset is compositor-agnostic (ADR 0097): niri and Hyprland both
# layer the SAME shell — bar, launcher, notifications, lock, wallpaper, OSD,
# palette, curated plugins — so the preset logic lives here, sourced by both
# `extras/desktop/niri/niri.sh` and `extras/desktop/hyprland/hyprland.sh`. Only
# the compositor config file (config.kdl vs hyprland.lua) and the plugin SLICE
# (niri-* vs hypr-*) differ; the seeded `config.toml` is byte-identical.
#
# Extracted from the niri adapter (ADR 0090/0093/0095) with no behaviour change.
# The DECISION to run it (wayland_shell=noctalia) stays with each adapter; this
# module only does the work once it is called.
#
# Caller contract — set these before calling noctalia_preset_install:
#   NOC_JSON          install-noctalia.jsonc (component + slice bools)
#   NOC_SEED_ROOT     prefix for /etc/skel seeds (default: / — the chroot)
#   NOC_CURATED_DIR   staged curated dotfiles source (.config/.local tree)
#   NOC_BAT_GLOB      battery-presence glob for laptop detection
#   NOC_SLICE_FN      compositor plugin-slice fn (noctalia_niri_plugins | …)
# Optional overrides (defaults below): NOC_COMMUNITY_REPO, NOC_COMMUNITY_REF,
#   NOC_PLUGIN_DATA.
# =============================================================================

[[ -n "${_NOCTALIA_PRESET_SH_SOURCED:-}" ]] && return 0
_NOCTALIA_PRESET_SH_SOURCED=1

# The pure Noctalia/niri package maps (preset base, core+slice plugins, deps),
# shared with the Package Resolver so install and query cannot drift (ADR 0090).
# shellcheck source=/dev/null
declare -F noctalia_preset_packages >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../packages/niri.sh"

# Community plugin source, pinned to one v5 commit (ADR 0093) — a single ref
# covers the whole enriched set for every compositor (bump = one SHA).
_NOC_REPO_DEFAULT="https://github.com/noctalia-dev/community-plugins.git"
_NOC_REF_DEFAULT="caed21ab081948435cd770d2e954c99b8bbb72cf"
NOC_COMMUNITY_REPO="${NOC_COMMUNITY_REPO:-$_NOC_REPO_DEFAULT}"
NOC_COMMUNITY_REF="${NOC_COMMUNITY_REF:-$_NOC_REF_DEFAULT}"
# Where a plugin folder is vendored so a fresh box discovers it as `[local]`
# (ADR 0093/0094): the skel DATA dir. The stowed one-shot enables what it finds.
NOC_PLUGIN_DATA="${NOC_PLUGIN_DATA:-etc/skel/.local/share/noctalia/plugins}"

# _noc_bool <key> — an install-noctalia.jsonc component bool (false if absent).
_noc_bool() {
  [[ -f "$NOC_JSON" ]] || { echo false; return; }
  jsonc "$NOC_JSON" | jq -r --arg k "$1" '.[$k] // false'
}

# _noc_laptop — laptop? install-noctalia.jsonc `laptop` wins when set to a
# boolean (true/false); "auto" (the default) or absence falls back to detecting
# a battery. Gates the battery plugin pair (ADR 0093).
_noc_laptop() {
  local v="auto"
  [[ -f "$NOC_JSON" ]] && v="$(jsonc "$NOC_JSON" \
    | jq -r 'if has("laptop") then (.laptop|tostring) else "auto" end')"
  case "$v" in
    true)  echo true;  return ;;
    false) echo false; return ;;
  esac
  compgen -G "${NOC_BAT_GLOB:-/sys/class/power_supply/BAT*}" >/dev/null 2>&1 \
    && echo true || echo false
}

# _noc_seed_plugin <repo> <ref> <subdir> — sparse-checkout <subdir> at <ref>
# into the skel data dir. Returns non-zero on any git/parse failure so a caller
# can warn-and-continue (invoked in an `if`, so set -e is suppressed inside — a
# network failure never aborts the install). plugin.toml presence + a non-empty
# id are validated so a half-checkout is treated as a failure.
_noc_seed_plugin() {
  local repo="$1" ref="$2" sub="$3"
  local tmp; tmp="$(mktemp -d)" || return 1
  local dst="${NOC_SEED_ROOT%/}/${NOC_PLUGIN_DATA}/${sub}"
  git clone --filter=blob:none --no-checkout --sparse "$repo" "$tmp/op" \
    || { rm -rf "$tmp"; return 1; }
  git -C "$tmp/op" sparse-checkout set "$sub" || { rm -rf "$tmp"; return 1; }
  git -C "$tmp/op" checkout "$ref" || { rm -rf "$tmp"; return 1; }
  [[ -f "$tmp/op/$sub/plugin.toml" ]] || { rm -rf "$tmp"; return 1; }
  local id
  id="$(sed -nE 's/^[[:space:]]*id[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' \
    "$tmp/op/$sub/plugin.toml" | head -n1)"
  [[ -n "$id" ]] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  cp -r "$tmp/op/$sub" "$dst"
  rm -rf "$tmp"
}

# _noc_collect_plugins <plugin-list-fn> — append each plugin the list-fn names
# that is enabled (per its install-noctalia.jsonc bool) plus its tool deps to
# the _enabled_pls / _all_deps accumulators (ADR 0093).
_noc_collect_plugins() {
  local pl
  while IFS= read -r pl; do
    [[ "$(_noc_bool "$pl")" == true ]] || continue
    _enabled_pls+=("$pl")
    mapfile -t -O "${#_all_deps[@]}" _all_deps < <(noctalia_plugin_deps "$pl")
  done < <("$1")
}

# noctalia_preset_install <cfg-src-rel> <cfg-dst-rel> — install + seed the whole
# preset. <cfg-src-rel>/<cfg-dst-rel> are the compositor config file relative to
# the curated dir / skel (config.kdl on niri, hyprland.lua on Hyprland); the
# shared config.toml + noctalia-* helpers are always seeded. Uses the section/
# info/warn helpers the sourcing adapter already has from extras-common.sh.
noctalia_preset_install() {
  local cfg_src="$1" cfg_dst="$2"

  # Base preset (pure map) + the enabled optional companions (cava, cliphist).
  section "Noctalia work shell"
  local _noc_pkgs=()
  mapfile -t _noc_pkgs < <(noctalia_preset_packages)
  [[ "$(_noc_bool cava)" == true ]]     && _noc_pkgs+=(cava)
  [[ "$(_noc_bool cliphist)" == true ]] && _noc_pkgs+=(cliphist)
  pacman -S --noconfirm --needed "${_noc_pkgs[@]}"

  # Seed the curated config into /etc/skel so a fresh box boots the full look by
  # default (ADR 0095/0097). Single source — chroot.sh staged these from the
  # repo's .config/.local into NOC_CURATED_DIR — so the same files stay
  # independently stowable; the installer seeds, it never stows. The shared
  # config.toml + helpers are byte-identical across compositors; only the
  # compositor config (cfg_src) differs.
  section "Noctalia curated config"
  if [[ -d "$NOC_CURATED_DIR" ]]; then
    local _skel="${NOC_SEED_ROOT%/}/etc/skel"
    install -Dm644 "${NOC_CURATED_DIR}/${cfg_src}" "${_skel}/${cfg_dst}"
    # Split config (ADR 0107): the entry file (cfg_src) is a pure manifest of
    # include/require lines; the settings live in a sibling conf.d/ tree. Seed
    # the whole tree beside the entry file when present. Absent (a pre-split
    # single-file config) → only the entry file is seeded, exactly as before.
    local _confd_src _confd_dst
    _confd_src="${NOC_CURATED_DIR}/$(dirname "$cfg_src")/conf.d"
    _confd_dst="${_skel}/$(dirname "$cfg_dst")/conf.d"
    if [[ -d "$_confd_src" ]]; then
      install -d "$_confd_dst"
      install -m644 "$_confd_src"/* "$_confd_dst/"
    fi
    # VM-only software cursor: virtio-gpu's DRM cursor plane is buggy in a guest
    # and the pointer renders as a broken "X". Force software cursors by machine
    # TYPE — injected here, NOT shipped in the stow'd config — so real hardware
    # keeps the optimal hardware cursor. niri toggles it in `debug{}`, Hyprland
    # via an hl.config cursor block (Lua, ADR 0105); branch on the file suffix.
    # Target the conf.d/environment part-file when the split tree is present so
    # the seeded manifest stays pure (ADR 0107), else the entry file itself.
    # (Harmless if detect-virt is unavailable — no-ops, real-HW config stands.)
    if systemd-detect-virt --vm --quiet 2>/dev/null; then
      local _cur_ext="${cfg_dst##*.}" _cur_tgt="${_skel}/${cfg_dst}"
      [[ -d "$_confd_dst" ]] && _cur_tgt="${_confd_dst}/environment.${_cur_ext}"
      case "$_cur_ext" in
      kdl)
        printf '\ndebug {\n    disable-cursor-plane\n}\n' >> "$_cur_tgt" ;;
      lua)
        printf '\nhl.config({ cursor = { no_hardware_cursors = true } })\n' \
          >> "$_cur_tgt" ;;
      esac
      info "VM detected — seeded software-cursor override into ${_cur_tgt#"${_skel}/"}."
    fi
    install -Dm644 "${NOC_CURATED_DIR}/.config/noctalia/config.toml" \
      "${_skel}/.config/noctalia/config.toml"
    install -d "${_skel}/.local/bin"
    install -m755 "${NOC_CURATED_DIR}"/.local/bin/noctalia-* \
      "${_skel}/.local/bin/"
    # pcmanfm-qt (the shared file manager, ADR 0100): its curated settings +
    # right-click custom actions (Open in kitty / Copy path / Duplicate). Same
    # single-source copy as the rest — stays independently stowable.
    install -Dm644 "${NOC_CURATED_DIR}/.config/pcmanfm-qt/lxqt/settings.conf" \
      "${_skel}/.config/pcmanfm-qt/lxqt/settings.conf"
    install -d "${_skel}/.local/share/file-manager/actions"
    install -m644 \
      "${NOC_CURATED_DIR}"/.local/share/file-manager/actions/*.desktop \
      "${_skel}/.local/share/file-manager/actions/"
    # Default cursor for GTK/XWayland apps (ADR 0098): ~/.icons/default inherits
    # Bibata Modern Ice, matching the compositor's XCURSOR_THEME. KDE seeds its
    # own copy; niri/Hyprland get theirs here (one line, no per-user state).
    install -d "${_skel}/.icons/default"
    printf '[Icon Theme]\nInherits=Bibata-Modern-Ice\n' \
      > "${_skel}/.icons/default/index.theme"
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
      "${_skel}/.local/state/noctalia/.setup-complete"
    # GTK settings.ini — SEEDED, never stowed (ADR 0104). kde-gtk-config
    # rewrites these at every Plasma login; through a stow symlink that write
    # lands in the dotfiles repo (perpetual git dirt). A real skel file lets
    # Plasma own them on KDE while a compositor keeps adw-gtk3-dark here +
    # Noctalia's live gtk.css colors. gtk-4.0 carries no theme name so
    # libadwaita follows gtk.css (ADR 0102). Host-neutral: no DPI/scaling.
    install -Dm644 /dev/stdin "${_skel}/.config/gtk-3.0/settings.ini" <<'EOF'
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
    install -Dm644 /dev/stdin "${_skel}/.config/gtk-4.0/settings.ini" <<'EOF'
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
    info "Curated Noctalia config + cursor + GTK settings seeded to /etc/skel."
  else
    warn "Curated config dir absent (${NOC_CURATED_DIR}) —" \
         "skel gets no Noctalia config."
  fi

  # Enriched plugin set (ADR 0093/0097): the shared core plus this compositor's
  # slice, each gated by its install-noctalia.jsonc bool (default on). Collect
  # both + their official-repo tool deps, install deps in one pass, then vendor
  # each at the pinned ref (the first-login one-shot enables them). A fetch
  # failure warns and continues, so one bad plugin never aborts the install.
  section "Noctalia plugin set"
  local _enabled_pls=() _all_deps=()
  _noc_collect_plugins noctalia_core_plugins
  [[ -n "${NOC_SLICE_FN:-}" ]] && _noc_collect_plugins "$NOC_SLICE_FN"

  # Battery plugins (ADR 0093) — laptop-gated: added only on a machine with a
  # battery, or when install-noctalia.jsonc forces `laptop`. Desktops get none.
  if [[ "$(_noc_laptop)" == true ]]; then
    _noc_collect_plugins noctalia_laptop_plugins
  fi

  [[ ${#_all_deps[@]} -gt 0 ]] \
    && pacman -S --noconfirm --needed "${_all_deps[@]}"
  local _pl
  for _pl in "${_enabled_pls[@]:-}"; do
    [[ -n "$_pl" ]] || continue
    if _noc_seed_plugin "$NOC_COMMUNITY_REPO" "$NOC_COMMUNITY_REF" "$_pl"
    then info "Plugin $_pl vendored."
    else warn "Plugin $_pl fetch failed (offline?) — skipped."; fi
  done
}
