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

# Bitwarden plugin source, pinned to a commit for a deterministic install (ADR
# 0090). A bad ref (or offline) degrades to skip-with-warning, never an abort.
_NIRI_BW_REPO="https://github.com/noctalia-dev/official-plugins.git"
_NIRI_BW_REF="ea6dfe3fae4d4a755dd05390548b04066250ffe9"

# _niri_register_plugin <name> — enable <name> in skel's Noctalia plugins.json
# (Noctalia does not auto-discover; the key must match the plugin dir + manifest
# id). Merges into an existing file, creating it when absent.
_niri_register_plugin() {
  local name="$1"
  local pj="${SEED_ROOT%/}/etc/skel/.config/noctalia/plugins.json"
  local url="https://github.com/noctalia-dev/official-plugins"
  local cur='{}'
  mkdir -p "$(dirname "$pj")"
  [[ -f "$pj" ]] && cur="$(cat "$pj")"
  jq --arg n "$name" --arg u "$url" \
    '.[$n] = {enabled: true, sourceUrl: $u}' <<<"$cur" > "$pj"
}

# _niri_seed_bitwarden_plugin — sparse-checkout the bitwarden/ subfolder at the
# pinned ref into skel and register it. Returns non-zero on any git failure so
# the caller can warn-and-continue (invoked in an `if`, so set -e is suppressed
# inside — a network failure never aborts the install).
_niri_seed_bitwarden_plugin() {
  local tmp; tmp="$(mktemp -d)" || return 1
  local dst="${SEED_ROOT%/}/etc/skel/.config/noctalia/plugins"
  git clone --filter=blob:none --no-checkout --sparse \
    "$_NIRI_BW_REPO" "$tmp/op" || { rm -rf "$tmp"; return 1; }
  git -C "$tmp/op" sparse-checkout set bitwarden || { rm -rf "$tmp"; return 1; }
  git -C "$tmp/op" checkout "$_NIRI_BW_REF" || { rm -rf "$tmp"; return 1; }
  [[ -d "$tmp/op/bitwarden" ]] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$dst"
  rm -rf "$dst/bitwarden"
  cp -r "$tmp/op/bitwarden" "$dst/bitwarden"
  rm -rf "$tmp"
  _niri_register_plugin bitwarden
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

  # Bitwarden vault plugin (ADR 0090). Install the CLI backend, then seed +
  # register the Luau plugin. The install-only step (bitwarden-cli) precedes the
  # network fetch, so an offline box still gets the CLI and only the plugin is
  # skipped. `bw login` is the user's first-boot step.
  if [[ "$(_niri_bool bitwarden)" == true ]]; then
    section "Noctalia Bitwarden plugin"
    # shellcheck disable=SC2046  # word-split the pure map into args
    pacman -S --noconfirm --needed $(noctalia_bitwarden_packages)
    if _niri_seed_bitwarden_plugin; then
      info "Bitwarden plugin seeded + enabled (run 'bw login' to authenticate)."
    else
      warn "Bitwarden plugin fetch failed (offline?) — skipped;" \
        "bitwarden-cli is installed. Add the plugin later from Noctalia."
    fi
  fi
fi

section "niri installation complete"
