# shellcheck shell=bash
# Feature Audit desktop probe for KDE Plasma (ADR 0152): runs inside the live
# Plasma session as the desktop user (sessions phase).
if [[ "$FA_SESSION" != kwin_wayland ]]; then
  fa_skip kde-session "not the running session"; return 0
fi
fa_check plasmashell "plasmashell running" pgrep -x plasmashell
fa_check kwin-dbus "KWin answers on D-Bus" \
  qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop
fa_check kde-portal "xdg-desktop-portal-kde answers" \
  busctl --user call org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
[[ "$(fa_cfg '.environment.stock // false')" == true ]] && return 0

_fa_kde_scheme() {
  [[ "$(kreadconfig6 --file kdeglobals --group General \
        --key ColorScheme)" == BreezeDark ]]
}
_fa_kde_desktops() {
  [[ "$(qdbus6 org.kde.KWin /VirtualDesktopManager \
        org.freedesktop.DBus.Properties.Get \
        org.kde.KWin.VirtualDesktopManager count)" == 4 ]]
}
# combined box (ADR 0116/0123): a Plasma login reasserts BreezeDark over any
# Noctalia-coloured kdeglobals a compositor session left behind
if [[ "$(fa_cfg '[.environment.desktop[] | select(. != "kde")] | length')" \
      != 0 ]]; then
  fa_check kde-colorscheme "Plasma login reasserted BreezeDark" _fa_kde_scheme
fi
# captured Plasma settings (ADR 0126) survived first login
fa_check kde-desktops "four virtual desktops (skel kwinrc)" _fa_kde_desktops
fa_check kde-kickoff-favorites "Kickoff favourites reconstructed" \
  grep -q favorites "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
