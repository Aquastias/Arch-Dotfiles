# shellcheck shell=bash
# Feature Audit shared wlroots-session checks (niri + Hyprland; ADR 0152):
# the Noctalia shell, Qt theming through its templates, xdg user dirs (ADR
# 0131), the clipboard keep-alive (ADR 0147) and the portals.
_fa_qt_env() {
  local p; p="$(pgrep -x noctalia | head -1)"
  tr '\0' '\n' < "/proc/$p/environ" | grep -qx QT_QPA_PLATFORMTHEME=qt6ct
}
if [[ "$(fa_cfg '.environment.wayland_shell // "noctalia"')" != none \
      && "$(fa_cfg '.environment.stock // false')" != true ]]; then
  fa_check noctalia-running "Noctalia shell running" pgrep -x noctalia
  fa_check noctalia-ipc "Noctalia IPC answers" noctalia msg --help
  fa_check qt6ct-conf "qt6ct config seeded (Qt follows Noctalia)" \
    test -s "$HOME/.config/qt6ct/qt6ct.conf"
  fa_check qt-platformtheme "QT_QPA_PLATFORMTHEME=qt6ct in the session" \
    _fa_qt_env
fi
_fa_xdg_dir() {
  local p; p="$(xdg-user-dir "$1")"
  [[ -d "$p" && "$p" != "$HOME" ]]
}
for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS; do
  fa_check "xdg-dir-${d,,}" "xdg user dir $d exists" _fa_xdg_dir "$d"
done
# ADR 0147: a copy outlives the app that made it
_fa_clip() {
  # wl-copy forks a clipboard server: detach it from our output pipe
  printf 'fa-clip-%s' "$$" | timeout 5 wl-copy >/dev/null 2>&1
  sleep 1
  [[ "$(timeout 5 wl-paste -n)" == "fa-clip-$$" ]]
}
fa_check clipboard-keepalive "clipboard survives its source exiting" _fa_clip
fa_check portal "xdg-desktop-portal answers on the session bus" \
  busctl --user call org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
