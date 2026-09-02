#!/usr/bin/env bash
# =============================================================================
# extras/desktop/hyprland/hyprland.sh — Hyprland Wayland Compositor
# =============================================================================
# Installs the minimum working-session CORE ONLY (ADR 0021, ADR 0062): the
# compositor, both portals, the polkit agent, the Wayland clipboard bridge. The
# SHELL is the shared Noctalia work preset (ADR 0097) — the SAME one niri uses —
# layered on top and gated on ENVIRONMENT_WAYLAND_SHELL: under `noctalia` the
# adapter hands off to lib/chroot/noctalia-preset.sh, which installs Noctalia +
# its gaps and seeds the Noctalia-wired hyprland.conf + shared config.toml +
# helpers into /etc/skel; under `none` the box is truly bare (nothing seeded, the
# operator brings their own config — symmetric with bare niri). hyprlock is NO
# LONGER installed (ADR 0097, superseding 0096): Noctalia locks natively via
# ext-session-lock-v1, so the lock bind drives Noctalia, not a separate locker.
#
# Injectable seams (tests):
#   WAYLAND_SESSIONS_DIR — session-override dir
#                          (default: /usr/local/share/wayland-sessions)
#   ROOT                 — prefix for the session override + aquamarine DRM pin
#                          writes (default: empty — writes to the live root)
#   HYPR_SEED_ROOT       — prefix for the /etc/skel config seed (default: /)
#   HYPR_CURATED_DIR     — curated dotfiles source (hyprland.conf + the shared
#                          Noctalia config.toml + helpers; default SCRIPT_DIR/curated)
#   HYPR_JSON            — install-noctalia.jsonc override (preset component bools)
#   HYPR_BAT_GLOB        — battery-presence glob for laptop plugin gating
#   STATE                — install-state.json, for the resolved `.gpu` array
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_WS_DIR_DEFAULT=/usr/local/share/wayland-sessions
WAYLAND_SESSIONS_DIR="${WAYLAND_SESSIONS_DIR:-$_WS_DIR_DEFAULT}"
ROOT="${ROOT:-}"
# Seed root for the /etc/skel config (ADR 0095/0097).
# Default `/` (the chroot); tests point HYPR_SEED_ROOT at a temp dir.
SEED_ROOT="${HYPR_SEED_ROOT:-/}"
# Curated-config source (ADR 0097). chroot.sh stages the repo's single-source
# Noctalia-wired hyprland.conf + the shared config.toml + noctalia-* helpers here
# so this adapter seeds them into /etc/skel — served by default, while the repo
# copies stay stowable. Injectable for tests.
HYPR_CURATED_DIR="${HYPR_CURATED_DIR:-${SCRIPT_DIR}/curated}"
# The Noctalia preset toggles, SHARED with the niri adapter (ADR 0097).
HYPR_JSON="${HYPR_JSON:-${SCRIPT_DIR}/../install-noctalia.jsonc}"

# shellcheck disable=SC2034  # read by chroot/extras-common.sh after sourcing
DE_TAG=HYPR
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/extras-common.sh"
# Reuse the one canonical amd+nvidia hybrid predicate (ADR 0053) so the
# aquamarine pin can never drift from the GPU hardening gate. GPU_LIB_ONLY=1
# loads the functions without running gpu.sh's chroot side effects.
# shellcheck source=/dev/null
GPU_LIB_ONLY=1 source "${SCRIPT_DIR}/../../../lib/chroot/gpu.sh"
# The shared Noctalia work-shell preset (ADR 0097) — same module the niri adapter
# uses; pulls in the pure package maps it needs.
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/chroot/noctalia-preset.sh"

# =============================================================================
# CORE
# =============================================================================
# The minimum working-session core (ADR 0021/0062). No companion apps — the
# shell (Noctalia) is the gated preset below; the launcher/lock keys drive
# Noctalia's IPC, so hyprlock is gone (ADR 0097). A file manager the curated
# config's Super+E references stays operator-supplied.
section "Hyprland core"
pacman -S --noconfirm --needed \
  hyprland \
  seatd \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  polkit-kde-agent \
  wl-clipboard

# SEAT MANAGER — seatd, not logind (ADR 0068).
# aquamarine (Hyprland's backend) could not obtain DRM master via logind on
# real hardware: every atomic KMS commit returned "Permission denied" and the
# compositor retry-looped forever (black screen / "hotplug storm"), even though
# the session showed Active on seat0 and nothing else held the card. aquamarine
# PREFERS seatd anyway — its log tries /run/seatd.sock first, then falls back to
# the failing logind path. seatd grants DRM master directly. Enable it; users
# get the `seat` group from User Core (filtered out on hosts without seatd), so
# both greetd sessions and manual launches acquire master. kwin is unaffected —
# this is Hyprland/aquamarine-specific.
systemctl enable seatd

# =============================================================================
# SESSION LAUNCHER — start-hyprland, DRM backend
# =============================================================================
# Two things are baked into the Exec:
#  1. `start-hyprland`, Hyprland 0.53+'s recommended launcher (crash recovery +
#     safe mode). The bare `Hyprland` binary runs but throws a red "launched
#     without start-hyprland" warning. An earlier `start-hyprland` crash
#     (`std::system_error: Resource deadlock avoided`) was a symptom of the
#     DRM-master failure ADR 0068 fixed with seatd, so it runs clean now.
#  2. `env -u WAYLAND_DISPLAY -u DISPLAY` — if either is set (a prior Plasma
#     Wayland session leaves them in the lingering user manager), aquamarine
#     picks its NESTED backend and renders into an invisible parent window
#     instead of driving the panel (black screen). Unsetting them forces the
#     DRM/KMS backend. Shipped in /usr/local so it wins the greeter's session
#     scan and survives package upgrades; the greeter (greetd or SDDM) points
#     here. This is the SOLE Hyprland session offered (ADR 0070).
section "Hyprland session launcher (start-hyprland, DRM backend)"
install -d "${ROOT}${WAYLAND_SESSIONS_DIR}"
cat > "${ROOT}${WAYLAND_SESSIONS_DIR}/hyprland.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=Hyprland compositor (start-hyprland, DRM backend)
Exec=env -u WAYLAND_DISPLAY -u DISPLAY start-hyprland
Type=Application
DesktopNames=Hyprland
Keywords=tiling;wayland;compositor;
DESKTOP

# =============================================================================
# CURATED SESSIONS — offered to whichever Display Manager is selected
# =============================================================================
# The DE adapter owns the session FILES; the display manager is a separate,
# operator-selected Display Manager Adapter (ADR 0069, superseding ADR 0067's
# "greetd owns the DM"). This curated /usr/local dir holds exactly the good
# sessions so the greeter — greetd via `tuigreet --sessions`, or SDDM via its
# pinned SessionDir — never shows the /usr/share duplicates: our start-hyprland
# session (hyprland.desktop, above) and — on a KDE co-install — Plasma. The
# packaged uwsm session is NOT symlinked in (ADR 0070): its systemd-user
# graphical.target orchestration deadlocks on the first post-boot login under
# impermanence (ADR 0061 pre-starts user@uid, which the target job can't clear),
# black-screening only the uwsm session while start-hyprland and Plasma work.
# start-hyprland is the sole Hyprland session. The check reads the full resolved
# desktop set, so it is independent of adapter execution order.
read -ra _desktops <<< "${ENVIRONMENT_DESKTOP:-}"
_has_kde=false
for _de in "${_desktops[@]}"; do
  [[ "$_de" == "kde" ]] && { _has_kde=true; break; }
done

section "Hyprland curated sessions"
if $_has_kde; then
  # KDE co-installed: also offer Plasma (symlinked into the curated dir).
  ln -sf /usr/share/wayland-sessions/plasma.desktop \
    "${ROOT}${WAYLAND_SESSIONS_DIR}/plasma.desktop"
  info "Curated sessions: Hyprland (start-hyprland) + Plasma."
else
  info "Curated sessions: Hyprland (start-hyprland)."
fi

# =============================================================================
# BLUETOOTH TRAY — blueman, suppressed inside KDE sessions (ADR 0080)
# =============================================================================
# The Bluetooth Service toggle (options.bluetooth.enabled) installs only the
# bluez DAEMON layer, never a GUI — the desktop owns the tray. KDE gets BlueDevil
# free via plasma-meta; Hyprland has no Plasma-independent applet, so the
# Hyprland adapter supplies blueman. On a KDE+Hyprland co-install both are
# present, so the packaged autostart is overwritten with NotShowIn=KDE: the
# applet is suppressed in a KDE session (BlueDevil is the tray there) and shows
# in a Hyprland session — one BT tray per session. On a Hyprland-only box the key
# is harmless (no KDE session exists). blueman coexists with BlueDevil without
# conflict; both are just bluez frontends.
section "Hyprland Bluetooth tray (blueman)"
pacman -S --noconfirm --needed blueman
install -d "${ROOT}/etc/xdg/autostart"
cat > "${ROOT}/etc/xdg/autostart/blueman.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Blueman Applet
Comment=Bluetooth tray applet (managed by the installer — ADR 0080)
Exec=blueman-applet
Icon=blueman
Terminal=false
NotShowIn=KDE;
X-GNOME-Autostart-enabled=true
DESKTOP
info "blueman installed; autostart set NotShowIn=KDE (Hyprland sessions only)."

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

# =============================================================================
# NOCTALIA WORK PRESET (ADR 0097) — wayland_shell=noctalia only
# =============================================================================
# The SAME shared preset the niri adapter runs: under noctalia, hand off to the
# module — map this adapter's seams onto the NOC_* contract, pick the Hyprland
# config file and the Hyprland plugin slice, and let the module install + seed +
# vendor. The seeded config.toml is byte-identical to niri's; only hyprland.conf
# (the Noctalia-wired compositor config) differs. Under `none` nothing is seeded
# — the box is truly bare, symmetric with bare niri.
if [[ "${ENVIRONMENT_WAYLAND_SHELL:-}" == noctalia ]]; then
  # NOC_* are the shared preset module's input contract (read by
  # lib/chroot/noctalia-preset.sh, sourced above); exported so it is explicit.
  export NOC_JSON="$HYPR_JSON"
  export NOC_SEED_ROOT="$SEED_ROOT"
  export NOC_CURATED_DIR="$HYPR_CURATED_DIR"
  export NOC_BAT_GLOB="${HYPR_BAT_GLOB:-/sys/class/power_supply/BAT*}"
  export NOC_SLICE_FN=noctalia_hyprland_plugins
  noctalia_preset_install ".config/hypr/hyprland.conf" ".config/hypr/hyprland.conf"
fi

section "Hyprland installation complete"
