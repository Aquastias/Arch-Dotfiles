# shellcheck shell=bash
# Feature Audit desktop probe for KDE Plasma (ADR 0152): runs inside the live
# Plasma session as the desktop user (sessions phase).
[[ "$FA_SESSION" == kwin_wayland ]] || { fa_skip kde-session "not the running session"; return 0; }
fa_check plasmashell "plasmashell running" pgrep -x plasmashell
fa_check kwin-dbus "KWin answers on D-Bus" \
  qdbus6 org.kde.KWin /KWin org.kde.KWin.currentDesktop
if [[ "$(fa_cfg '.environment.stock // false')" != true ]]; then
  # captured Plasma settings (ADR 0123/0126) survived first login
  fa_check kde-colorscheme "kdeglobals carries the fleet colour scheme" \
    grep -q '^ColorScheme=' "$HOME/.config/kdeglobals"
  # shellcheck disable=SC2016 # expands in the child shell
  fa_check kde-desktops "four virtual desktops (skel kwinrc)" \
    sh -c '[ "$(qdbus6 org.kde.KWin /VirtualDesktopManager org.freedesktop.DBus.Properties.Get org.kde.KWin.VirtualDesktopManager count)" = 4 ]'
  fa_check kde-kickoff-favorites "Kickoff favourites reconstructed" \
    grep -q 'favorites' "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
fi
fa_check kde-portal "xdg-desktop-portal-kde answers" \
  busctl --user status org.freedesktop.portal.Desktop
