#!/usr/bin/env bash
# =============================================================================
# extras/desktop/niri/niri.sh — niri scrollable-tiling Wayland compositor
# =============================================================================
# Core-only Desktop Environment Adapter (ADR 0021/0062/0090): installs the
# compositor and session plumbing only. niri ships its own
# /usr/share/wayland-sessions/niri.desktop + niri-session and pulls seatd, so —
# unlike the Hyprland adapter — there is no session-launcher shim and no
# aquamarine DRM pin. The display manager is a separate, operator-selected
# Display Manager Adapter (ADR 0069) — not this adapter's concern.
#
# The optional Noctalia work shell (ADR 0090) layers on top, gated on
# ENVIRONMENT_WAYLAND_SHELL; bare niri (none / unset) installs the core only.
#
# Injectable seams (tests):
#   NIRI_SEED_ROOT       — prefix for /etc/skel seeds (default: / — the chroot)
#   NIRI_BAT_GLOB        — battery-presence glob for laptop detection
#                          (default: /sys/class/power_supply/BAT*)
#   NIRI_JSON            — install-niri.jsonc override (preset component bools)
#   WAYLAND_SESSIONS_DIR — curated session dir
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the curated-session write (default: empty)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIRI_JSON="${NIRI_JSON:-${SCRIPT_DIR}/install-niri.jsonc}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"
# Seed root for the /etc/skel config glue (ADR 0088/0090). Default `/` (the
# chroot); tests point NIRI_SEED_ROOT at a temp dir.
SEED_ROOT="${NIRI_SEED_ROOT:-/}"

# Curated-config source (ADR 0095). chroot.sh stages the repo's single-source
# `.config`/`.local` curated niri+Noctalia dotfiles here so this adapter seeds
# them into /etc/skel — served by default, while the repo copy stays
# independently stowable. Injectable for tests.
NIRI_CURATED_DIR="${NIRI_CURATED_DIR:-${SCRIPT_DIR}/curated}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=niri
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# The pure niri package map, shared with the Package Resolver so install and
# query cannot drift (ADR 0090).
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/packages/niri.sh"

# =============================================================================
# CORE
# =============================================================================
section "niri core"
# shellcheck disable=SC2046  # word-split the one-per-line pure map into args
pacman -S --noconfirm --needed $(niri_core_packages)

# SEAT MANAGER — seatd (ADR 0068). niri uses libseat and takes DRM master via
# seatd directly; enable it so both greeter-launched and manual sessions acquire
# master. Users get the `seat` group from User Core (filtered out on hosts
# without seatd).
systemctl enable seatd

# =============================================================================
# CURATED SESSION — offered to whichever Display Manager is selected (ADR 0069)
# =============================================================================
# niri ships its own /usr/share/wayland-sessions/niri.desktop, but a greeter
# pointed ONLY at the curated /usr/local dir would miss it — e.g. greetd on a
# niri+Hyprland co-install, where the Hyprland adapter creates that dir and
# tuigreet reads only it. Symlink the packaged session into the curated dir so
# niri appears under any DM regardless of DE order (mirrors how the Hyprland
# adapter curates Plasma). niri-only still works via the greeter's /usr/share
# fallback; curating is harmless and uniform.
section "niri curated session"
install -d "${ROOT}${WAYLAND_SESSIONS_DIR}"
ln -sf /usr/share/wayland-sessions/niri.desktop \
  "${ROOT}${WAYLAND_SESSIONS_DIR}/niri.desktop"

# =============================================================================
# NOCTALIA WORK PRESET (ADR 0090) — wayland_shell=noctalia only
# =============================================================================
# Bare niri (none / unset) stops at the core above — the operator's dotfiles own
# the shell (Hyprland core-only precedent). The preset turns a fresh niri box
# into a prepared work desktop: the Noctalia shell + the gaps it does not cover,
# plus a minimal /etc/skel config that autostarts it.

# _niri_bool <key> — an install-niri.jsonc component bool (false when absent).
_niri_bool() {
  [[ -f "$NIRI_JSON" ]] || { echo false; return; }
  jsonc "$NIRI_JSON" | jq -r --arg k "$1" '.[$k] // false'
}

# Battery-presence glob for laptop detection (ADR 0093). Default is real /sys —
# the adapter runs in arch-chroot on the target, so this is live hardware; tests
# point NIRI_BAT_GLOB at a controlled dir.
_NIRI_BAT_GLOB="${NIRI_BAT_GLOB:-/sys/class/power_supply/BAT*}"

# _niri_laptop — laptop? install-niri.jsonc `laptop` wins when set to a boolean
# (true/false); "auto" (the default) or absence falls back to detecting a
# battery. Gates the battery plugin pair (ADR 0093).
_niri_laptop() {
  local v="auto"
  [[ -f "$NIRI_JSON" ]] && v="$(jsonc "$NIRI_JSON" \
    | jq -r 'if has("laptop") then (.laptop|tostring) else "auto" end')"
  case "$v" in
    true)  echo true;  return ;;
    false) echo false; return ;;
  esac
  compgen -G "$_NIRI_BAT_GLOB" >/dev/null 2>&1 && echo true || echo false
}

# Community plugin source, pinned to one v5 commit (ADR 0093) — a single ref
# covers the whole enriched set (bump = one SHA).
_NIRI_COMMUNITY_REPO="https://github.com/noctalia-dev/community-plugins.git"
_NIRI_COMMUNITY_REF="caed21ab081948435cd770d2e954c99b8bbb72cf"

# Noctalia v5 plugin vendoring (ADR 0093/0094). Copies a plugin's folder into
# the skel DATA dir at a pinned ref, so a fresh box discovers it as a `[local]`
# source offline. The config that ENABLES it (config.toml's [plugins] list) is
# now a stow-owned dotfile, not seeded here; the stowed first-login one-shot
# runs the per-plugin export. This adapter only vendors.
_NIRI_PLUGIN_DATA="etc/skel/.local/share/noctalia/plugins"

# _niri_seed_plugin <repo> <ref> <subdir> — sparse-checkout <subdir> at <ref>
# into the skel data dir. Returns non-zero on any git/parse failure so a caller
# can warn-and-continue (invoked in an `if`, so set -e is suppressed inside — a
# network failure never aborts the install). The plugin.toml presence + a
# non-empty id are validated so a half-checkout is treated as a failure.
_niri_seed_plugin() {
  local repo="$1" ref="$2" sub="$3"
  local tmp; tmp="$(mktemp -d)" || return 1
  local dst="${SEED_ROOT%/}/${_NIRI_PLUGIN_DATA}/${sub}"
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

# _niri_collect_plugins <plugin-list-fn> — append each plugin the list-fn names
# that is enabled (per its install-niri.jsonc bool) plus its tool deps to the
# _enabled_pls / _all_deps accumulators (ADR 0093).
_niri_collect_plugins() {
  local pl
  while IFS= read -r pl; do
    [[ "$(_niri_bool "$pl")" == true ]] || continue
    _enabled_pls+=("$pl")
    mapfile -t -O "${#_all_deps[@]}" _all_deps < <(noctalia_plugin_deps "$pl")
  done < <("$1")
}

if [[ "${ENVIRONMENT_WAYLAND_SHELL:-}" == noctalia ]]; then
  section "Noctalia work shell"
  # Base preset (pure map) + the enabled optional companions (cava, cliphist).
  _noc_pkgs=()
  mapfile -t _noc_pkgs < <(noctalia_preset_packages)
  [[ "$(_niri_bool cava)" == true ]]     && _noc_pkgs+=(cava)
  [[ "$(_niri_bool cliphist)" == true ]] && _noc_pkgs+=(cliphist)
  pacman -S --noconfirm --needed "${_noc_pkgs[@]}"

  # Seed the curated config into /etc/skel so a fresh box boots the full look by
  # default (ADR 0095, superseding 0094's stow-only delivery): the niri glue
  # (config.kdl), the Noctalia look (config.toml), and the palette-cycle /
  # enable-plugins helpers. Single source — chroot.sh staged these from the
  # repo's .config/.local into NIRI_CURATED_DIR — so the same files stay
  # independently stowable; the installer seeds, it never stows.
  section "Noctalia curated config"
  if [[ -d "$NIRI_CURATED_DIR" ]]; then
    _skel="${SEED_ROOT%/}/etc/skel"
    install -Dm644 "${NIRI_CURATED_DIR}/.config/niri/config.kdl" \
      "${_skel}/.config/niri/config.kdl"
    install -Dm644 "${NIRI_CURATED_DIR}/.config/noctalia/config.toml" \
      "${_skel}/.config/noctalia/config.toml"
    install -d "${_skel}/.local/bin"
    install -m755 "${NIRI_CURATED_DIR}"/.local/bin/noctalia-* \
      "${_skel}/.local/bin/"
    info "Curated niri+Noctalia config seeded to /etc/skel."
  else
    warn "Curated config dir absent (${NIRI_CURATED_DIR}) —" \
         "skel gets no niri/Noctalia config."
  fi

  # Enriched community plugin set (ADR 0093). Collect the enabled plugins and
  # their official-repo tool deps (per-plugin bools in install-niri.jsonc gate
  # each, default on), install deps in one pass, then vendor each at the pinned
  # community ref (the first-login one-shot enables them). A fetch failure warns
  # and continues, so one bad plugin never aborts the install.
  section "Noctalia plugin set"
  _enabled_pls=()
  _all_deps=()
  _niri_collect_plugins noctalia_community_plugins

  # Battery plugins (ADR 0093) — laptop-gated: added only on a machine with a
  # battery, or when install-niri.jsonc forces `laptop`. Desktops get neither.
  if [[ "$(_niri_laptop)" == true ]]; then
    _niri_collect_plugins noctalia_laptop_plugins
  fi

  [[ ${#_all_deps[@]} -gt 0 ]] \
    && pacman -S --noconfirm --needed "${_all_deps[@]}"
  for _pl in "${_enabled_pls[@]:-}"; do
    [[ -n "$_pl" ]] || continue
    if _niri_seed_plugin "$_NIRI_COMMUNITY_REPO" "$_NIRI_COMMUNITY_REF" "$_pl"
    then info "Plugin $_pl vendored."
    else warn "Plugin $_pl fetch failed (offline?) — skipped."; fi
  done
fi

section "niri installation complete"
