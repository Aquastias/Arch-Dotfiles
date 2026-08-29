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
# ENVIRONMENT_NIRI_SHELL; bare niri (none / unset) installs the core only.
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
# NOCTALIA WORK PRESET (ADR 0090) — niri_shell=noctalia only
# =============================================================================
# Bare niri (none / unset) stops at the core above — the operator's dotfiles own
# the shell (Hyprland core-only precedent). The preset turns a fresh niri box
# into a prepared work desktop: the Noctalia shell + the gaps it does not cover,
# plus a minimal /etc/skel config that autostarts it.

# _seed_write <relative-path> — write stdin under SEED_ROOT, creating parents.
_seed_write() {
  local dst="${SEED_ROOT%/}/$1"
  mkdir -p "$(dirname "$dst")"
  cat > "$dst"
}

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

# Bitwarden plugin source, pinned to a v5 commit for a deterministic install
# (ADR 0090/0093). A bad ref (or offline) degrades to skip-with-warning, never
# an abort.
_NIRI_BW_REPO="https://github.com/noctalia-dev/official-plugins.git"
_NIRI_BW_REF="8cb833c3e2502f57e49d34fa64386b4d66794b77"

# Community plugin source, pinned to one v5 commit (ADR 0093) — a single ref
# covers the whole enriched set (bump = two SHAs, this + the official one).
_NIRI_COMMUNITY_REPO="https://github.com/noctalia-dev/community-plugins.git"
_NIRI_COMMUNITY_REF="caed21ab081948435cd770d2e954c99b8bbb72cf"

# Noctalia v5 plugin seeding (ADR 0093). Loads a plugin from its folder in the
# DATA dir and enables it by canonical id in config.toml's [plugins] list — the
# v4 plugins.json path is dead. Plugins are vendored (folder copied at a pinned
# ref), so first daemon start scans + enables them offline; auto_update is off
# and no settings.toml is shipped (the state-dir one loads last and would
# override the seed).
_NIRI_PLUGIN_DATA="etc/skel/.local/share/noctalia/plugins"
_NIRI_ENABLED_PLUGINS=()

# Default palette seeded into config.toml (ADR 0093) — the one theming exception
# to ADR 0090's glue-only rule. Rosé Pine and the other built-ins (Catppuccin,
# Tokyo-Night, Gruvbox, Nord) switch at runtime; only the default is seeded.
_NIRI_DEFAULT_PALETTE="Rosé Pine"

# _niri_seed_plugin <repo> <ref> <subdir> — sparse-checkout <subdir> at <ref>
# into the skel data dir and mark its manifest id (read from plugin.toml)
# enabled. Returns non-zero on any git/parse failure so the caller can
# warn-and-continue (invoked in an `if`, so set -e is suppressed inside — a
# network failure never aborts the install).
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
  _NIRI_ENABLED_PLUGINS+=("$id")
}

# _niri_write_noctalia_config — assemble skel config.toml: the [theme] default
# (the one theming exception to ADR 0090) plus the [plugins] table (vendored ids
# as the enabled list, auto_update=none so no background fetch of a pinned set).
_niri_write_noctalia_config() {
  local list="" id
  for id in "${_NIRI_ENABLED_PLUGINS[@]:-}"; do
    [[ -n "$id" ]] && list+="\"$id\", "
  done
  list="${list%, }"
  _seed_write etc/skel/.config/noctalia/config.toml <<TOML
# Seeded by the installer (ADR 0093): the default palette (the one theming
# exception to ADR 0090) plus vendored plugins enabled by canonical id, with
# auto_update off (pinned installs). Noctalia owns the rest of its look.
[theme]
source = "builtin"
builtin = "${_NIRI_DEFAULT_PALETTE}"

[plugins]
auto_update = "none"
enabled = [${list}]
TOML
}

if [[ "${ENVIRONMENT_NIRI_SHELL:-}" == noctalia ]]; then
  section "Noctalia work shell"
  # Base preset (pure map) + the enabled optional companions. bitwarden is
  # handled below (it also pulls a CLI + a plugin, not just a package).
  _noc_pkgs=()
  mapfile -t _noc_pkgs < <(noctalia_preset_packages)
  [[ "$(_niri_bool cava)" == true ]]     && _noc_pkgs+=(cava)
  [[ "$(_niri_bool cliphist)" == true ]] && _noc_pkgs+=(cliphist)
  pacman -S --noconfirm --needed "${_noc_pkgs[@]}"

  # Minimal niri config GLUE only (ADR 0090): autostart Noctalia and bind kitty
  # + niri's native screenshot. Noctalia owns its own look (first-run defaults +
  # the operator's dotfiles) — no theming is seeded here.
  section "niri config glue (/etc/skel)"
  _seed_write etc/skel/.config/niri/config.kdl <<'KDL'
// Seeded by the installer (ADR 0090): minimal glue so the Noctalia work shell
// autostarts and a terminal + screenshot are bound on first login. Noctalia
// owns its own look; edit freely — this is only the glue.
spawn-at-startup "noctalia" "--daemon"

binds {
    Mod+Return { spawn "kitty"; }
    Print { screenshot; }
}
KDL
  info "Seeded /etc/skel niri config (Noctalia autostart + kitty)."

  # Bitwarden vault plugin (ADR 0090/0093). Install the CLI backend, then vendor
  # + enable the Luau plugin via the v5 mechanism. The install-only step
  # (bitwarden-cli) precedes the network fetch, so an offline box still gets the
  # CLI and the plugin is skipped. `bw login` is the user's first-boot step.
  if [[ "$(_niri_bool bitwarden)" == true ]]; then
    section "Noctalia Bitwarden plugin"
    # shellcheck disable=SC2046  # word-split the pure map into args
    pacman -S --noconfirm --needed $(noctalia_bitwarden_packages)
    if _niri_seed_plugin "$_NIRI_BW_REPO" "$_NIRI_BW_REF" bitwarden; then
      info "Bitwarden plugin enabled (run 'bw login' to authenticate)."
    else
      warn "Bitwarden plugin fetch failed (offline?) — skipped;" \
        "bitwarden-cli is installed. Add the plugin later from Noctalia."
    fi
  fi

  # Enriched community plugin set (ADR 0093). Collect the enabled plugins and
  # their official-repo tool deps (per-plugin bools in install-niri.jsonc gate
  # each, default on), install deps in one pass, then vendor + enable each at
  # the pinned community ref. A fetch failure warns and continues, so one bad
  # plugin never aborts the install.
  section "Noctalia plugin set"
  _enabled_pls=()
  _all_deps=()
  while IFS= read -r _pl; do
    [[ "$(_niri_bool "$_pl")" == true ]] || continue
    _enabled_pls+=("$_pl")
    mapfile -t -O "${#_all_deps[@]}" _all_deps < <(noctalia_plugin_deps "$_pl")
  done < <(noctalia_community_plugins)

  # Battery plugins (ADR 0093) — laptop-gated: added only on a machine with a
  # battery, or when install-niri.jsonc forces `laptop`. Desktops get neither.
  if [[ "$(_niri_laptop)" == true ]]; then
    while IFS= read -r _pl; do
      [[ "$(_niri_bool "$_pl")" == true ]] || continue
      _enabled_pls+=("$_pl")
      mapfile -t -O "${#_all_deps[@]}" _all_deps \
        < <(noctalia_plugin_deps "$_pl")
    done < <(noctalia_laptop_plugins)
  fi

  [[ ${#_all_deps[@]} -gt 0 ]] \
    && pacman -S --noconfirm --needed "${_all_deps[@]}"
  for _pl in "${_enabled_pls[@]:-}"; do
    [[ -n "$_pl" ]] || continue
    if _niri_seed_plugin "$_NIRI_COMMUNITY_REPO" "$_NIRI_COMMUNITY_REF" "$_pl"
    then info "Plugin $_pl enabled."
    else warn "Plugin $_pl fetch failed (offline?) — skipped."; fi
  done

  # Assemble skel config.toml — the [theme] default + [plugins] enabled list
  # (v5 replaces the dead plugins.json).
  _niri_write_noctalia_config
fi

section "niri installation complete"
