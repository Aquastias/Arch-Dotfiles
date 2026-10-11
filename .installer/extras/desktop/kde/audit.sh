# shellcheck shell=bash
# Feature Audit desktop probe for KDE Plasma (ADR 0152): runs inside the live
# Plasma session as the desktop user (sessions phase).
if [[ "$FA_SESSION" != kwin_wayland ]]; then
  feature_audit_skip kde-session "not the running session"; return 0
fi
feature_audit_check plasmashell "plasmashell running" pgrep -x plasmashell
feature_audit_check kwin-dbus "KWin answers on D-Bus" \
  qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop
feature_audit_check kde-portal "xdg-desktop-portal-kde answers" \
  busctl --user call org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
[[ "$(feature_audit_config '.environment.stock // false')" == true ]] && return 0

# the palette Plasma renders, not the ColorScheme key: Noctalia leaves that key
# at BreezeDark while rewriting the colours, and a fresh Plasma writes neither
# (Breeze defaults apply)
_probe_kde_scheme() {
  local want got
  want="$(kreadconfig6 --file /usr/share/color-schemes/BreezeDark.colors \
    --group Colors:Window --key BackgroundNormal)"
  got="$(kreadconfig6 --file kdeglobals --group Colors:Window \
    --key BackgroundNormal)"
  [[ -z "$got" || "$got" == "$want" ]]
}
_probe_kde_desktops() {
  [[ "$(qdbus6 org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get \
        org.kde.KWin.VirtualDesktopManager count)" == 4 ]]
}
# combined box (ADR 0116/0123): a Plasma login reasserts BreezeDark over any
# Noctalia-coloured kdeglobals a compositor session left behind
if [[ "$(feature_audit_config '[.environment.desktop[] | select(. != "kde")] | length')" \
      != 0 ]]; then
  feature_audit_check kde-colorscheme "Plasma login reasserted BreezeDark" _probe_kde_scheme
fi
# captured Plasma settings (ADR 0126) survived first login
feature_audit_check kde-desktops "four virtual desktops (skel kwinrc)" _probe_kde_desktops
feature_audit_check kde-kickoff-favorites "Kickoff favourites reconstructed" \
  grep -q favorites "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
