#!/usr/bin/env bash
# =============================================================================
# extras/desktop/hyprland/hyprland.sh — Hyprland Wayland Compositor
# =============================================================================
# Installs the minimum working-session CORE ONLY (ADR 0021, ADR 0062): the
# compositor, both portals, the polkit agent, the Wayland clipboard bridge.
# Companion apps, bars, launchers, terminals, lock/idle/wallpaper and theming
# (qt6ct) are deliberately NOT installed — the operator brings those via their
# own dotfiles.
#
# Injectable seams (tests):
#   GREETD_CONF_DIR      — greetd config dir (default: /etc/greetd)
#   WAYLAND_SESSIONS_DIR — session-override dir
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the session override + aquamarine DRM pin
#                          writes (default: empty — writes to the live root)
#   STATE                — install-state.json, for the resolved `.gpu` array
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREETD_CONF_DIR="${GREETD_CONF_DIR:-/etc/greetd}"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=HYPR
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# Reuse the one canonical amd+nvidia hybrid predicate (ADR 0053) so the
# aquamarine pin can never drift from the GPU hardening gate. GPU_LIB_ONLY=1
# loads the functions without running gpu.sh's chroot side effects.
# shellcheck source=/dev/null
GPU_LIB_ONLY=1 source "${SCRIPT_DIR}/../../../lib/chroot/gpu.sh"

# =============================================================================
# CORE
# =============================================================================
section "Hyprland core"
pacman -S --noconfirm --needed \
  hyprland \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  polkit-kde-agent \
  wl-clipboard

# =============================================================================
# SESSION LAUNCHER — direct Hyprland, DRM backend, not start-hyprland
# =============================================================================
# Two fixes are baked into the Exec:
#  1. Direct `Hyprland`, not the packaged `start-hyprland` supervisor, which
#     aborts a few seconds in (`std::system_error: Resource deadlock avoided`,
#     core dump) and bounces a DM back to the greeter; a bare `Hyprland` runs.
#  2. `env -u WAYLAND_DISPLAY -u DISPLAY` — if either is set (a prior Plasma
#     Wayland session leaves them in the lingering user manager), aquamarine
#     picks its NESTED backend and renders into an invisible parent window
#     instead of driving the panel (black screen). Unsetting them forces the
#     DRM/KMS backend. Shipped in /usr/local so it wins the greeter's session
#     scan and survives package upgrades; the greetd picker points here.
section "Hyprland session launcher (direct, DRM backend)"
install -d "${ROOT}${WAYLAND_SESSIONS_DIR}"
cat > "${ROOT}${WAYLAND_SESSIONS_DIR}/hyprland.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland compositor (direct launch, DRM backend)
Exec=env -u WAYLAND_DISPLAY -u DISPLAY Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
DESKTOP

# =============================================================================
# DISPLAY MANAGER — greetd whenever Hyprland is installed
# =============================================================================
# greetd/tuigreet launches the compositor directly on its VT, so aquamarine
# takes DRM master. SDDM does NOT grant the aquamarine session master — the
# atomic KMS commit fails "Permission denied" and Hyprland black-screens — even
# though kwin survives the same SDDM handoff. So greetd owns the DM for BOTH a
# sole-Hyprland install AND a KDE co-install, superseding ADR 0062's "SDDM owns
# the DM when KDE is present" (that path never lit the panel for Hyprland).
# KDE-only installs keep SDDM (kde.sh enables it only when Hyprland is absent).
# The check reads the full resolved desktop set, so it is independent of adapter
# execution order (ADR 0005, ADR 0067).
read -ra _desktops <<< "${ENVIRONMENT_DESKTOP:-}"
_has_kde=false
for _de in "${_desktops[@]}"; do
  [[ "$_de" == "kde" ]] && { _has_kde=true; break; }
done

section "Display Manager: greetd"
pacman -S --noconfirm --needed greetd greetd-tuigreet
mkdir -p "$GREETD_CONF_DIR"
if $_has_kde; then
  # KDE co-installed: a session picker over EXACTLY the good sessions — this
  # adapter's direct-launch Hyprland override plus Plasma (symlinked in) — from
  # the one curated /usr/local dir, so the packaged (crashy) start-hyprland
  # session and the uwsm variant in /usr/share never appear. tuigreet's default
  # scan is /usr/share/*; --sessions repoints it (tuigreet(1)).
  ln -sf /usr/share/wayland-sessions/plasma.desktop \
    "${ROOT}${WAYLAND_SESSIONS_DIR}/plasma.desktop"
  _greeter_cmd="tuigreet --remember --remember-session --sessions ${WAYLAND_SESSIONS_DIR}"
  _greeter_desc="KDE + Hyprland session picker"
else
  # Sole Hyprland: launch it directly. greetd starts the session with a clean
  # env (the greeter is a TUI, no compositor), so WAYLAND_DISPLAY is unset and
  # aquamarine uses the DRM backend without the env -u guard the override adds.
  _greeter_cmd="tuigreet --cmd Hyprland"
  _greeter_desc="Hyprland"
fi
cat > "${GREETD_CONF_DIR}/config.toml" <<TOML
[terminal]
vt = 1

[default_session]
command = "${_greeter_cmd}"
user = "greeter"
TOML
systemctl enable greetd
info "greetd + tuigreet enabled (${_greeter_desc})."

# =============================================================================
# AQUAMARINE DRM PINNING — hybrid AMD+NVIDIA only
# =============================================================================
# On an nvidia+integrated hybrid the panel hangs off the iGPU and the dGPU is
# powered off on-demand; aquamarine otherwise grabs the first DRM node (often
# the off dGPU) and black-screens. Pin the compositor to the iGPU via a stable,
# colon-free DRM symlink + AQ_DRM_DEVICES, gated on the resolved amd+nvidia set
# from install-state (ADR 0053's seam). Relocated here from the DE-agnostic
# environment.sh (ADR 0050 placement smell): it is Hyprland/aquamarine-specific
# and inert to KWin. AQ_DRM_DEVICES splits on ':' and PCI by-path names contain
# ':' while cardN numbers aren't stable across boots — hence the udev symlink.
_hypr_gpu_vendors() {
  local state="${STATE:-/root/lib-chroot/install-state.json}"
  [[ -f "$state" ]] || return 0
  jq -r '.gpu[]?' "$state" 2>/dev/null
}

_hypr_aq_udev_rule() {
  cat <<'RULES'
# Stable, colon-free DRM card symlinks for AQ_DRM_DEVICES (Hyprland/aquamarine).
# The gate is amd+nvidia, so resolve by PCI vendor: 0x1002 amd (iGPU), 0x10de
# nvidia (dGPU). Managed by the installer (extras/desktop/hyprland/hyprland.sh).
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x1002", SYMLINK+="dri/aq-igpu"
KERNEL=="card[0-9]*", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", ATTRS{vendor}=="0x10de", SYMLINK+="dri/aq-dgpu"
RULES
}

_hypr_aq_pin() {
  local vendors=()
  mapfile -t vendors < <(_hypr_gpu_vendors)
  _gpu_should_harden "${vendors[@]+"${vendors[@]}"}" || {
    info "Not an amd+nvidia hybrid — aquamarine DRM pin skipped."
    return 0
  }
  section "Aquamarine DRM pinning (hybrid GPU)"
  local rule="${ROOT}/usr/lib/udev/rules.d/60-aq-drm-devices.rules"
  mkdir -p "$(dirname "$rule")"
  _hypr_aq_udev_rule > "$rule"

  local env="${ROOT}/etc/environment"
  mkdir -p "$(dirname "$env")"
  [[ -f "$env" ]] && sed -i \
    '/# >>> arch-dotfiles gpu/,/# <<< arch-dotfiles gpu/d' "$env"
  {
    echo '# >>> arch-dotfiles gpu (nvidia PRIME hybrid; see hyprland.sh)'
    echo '# Compositor on the iGPU only — the dGPU is off/on-demand; per-app'
    echo '# nvidia offload is via prime-run, not this list.'
    echo 'AQ_DRM_DEVICES=/dev/dri/aq-igpu'
    echo '# <<< arch-dotfiles gpu'
  } >> "$env"
  info "Aquamarine pinned to the iGPU (AQ_DRM_DEVICES)."
}

_hypr_aq_pin

section "Hyprland installation complete"
