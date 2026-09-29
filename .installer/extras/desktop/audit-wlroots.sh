# shellcheck shell=bash
# Feature Audit shared wlroots-session checks (niri + Hyprland; ADR 0152):
# the Noctalia shell, Qt/GTK theming through its templates, xdg user dirs
# (ADR 0131), the clipboard keep-alive (ADR 0147) and the portals.
if [[ "$(fa_cfg '.environment.wayland_shell // "noctalia"')" != none \
      && "$(fa_cfg '.environment.stock // false')" != true ]]; then
  fa_check noctalia-running "Noctalia shell running" pgrep -x noctalia
  fa_check noctalia-ipc "Noctalia IPC answers" noctalia msg --help
  fa_check qt6ct-conf "qt6ct config seeded (Qt follows Noctalia)" \
    test -s "$HOME/.config/qt6ct/qt6ct.conf"
  fa_check qt-platformtheme "QT_QPA_PLATFORMTHEME=qt6ct in the session" \
    sh -c "tr '\\0' '\\n' < /proc/$(pgrep -x noctalia | head -1)/environ | grep -qx QT_QPA_PLATFORMTHEME=qt6ct"
fi
for d in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS; do
  fa_check "xdg-dir-${d,,}" "xdg user dir $d exists" \
    sh -c "test -d \"\$(xdg-user-dir $d)\" && [ \"\$(xdg-user-dir $d)\" != \"$HOME\" ]"
done
# ADR 0147: a copy outlives the app that made it
_fa_clip() {
  printf 'fa-clip-%s' "$$" | timeout 5 wl-copy
  sleep 1
  [[ "$(timeout 5 wl-paste -n)" == "fa-clip-$$" ]]
}
fa_check clipboard-keepalive "clipboard survives its source exiting" _fa_clip
fa_check portal "xdg-desktop-portal answers on the session bus" \
  busctl --user status org.freedesktop.portal.Desktop
