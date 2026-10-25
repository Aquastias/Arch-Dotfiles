# shellcheck shell=bash
# Feature Audit shared wlroots-session checks (niri, Hyprland, Umbriel; ADR
# 0152): the Noctalia shell, Qt theming through its templates, xdg user dirs
# (ADR 0131), the clipboard keep-alive (ADR 0147) and the portals.
_probe_qt_env() {
  local pid; pid="$(pgrep -x noctalia | awk 'NR == 1 { print; exit }')"
  grep -qxz QT_QPA_PLATFORMTHEME=qt6ct "/proc/$pid/environ"
}
if feature_audit_gate noctalia \
  "no Wayland shell in this variant" feature_audit_has_shell; then
  feature_audit_check noctalia-running "Noctalia shell running" pgrep \
    -x noctalia
  feature_audit_check noctalia-ipc "Noctalia IPC answers" noctalia msg --help
  feature_audit_check qt6ct-conf "qt6ct config seeded (Qt follows Noctalia)" \
    test -s "$HOME/.config/qt6ct/qt6ct.conf"
  feature_audit_check qt-platformtheme \
    "QT_QPA_PLATFORMTHEME=qt6ct in the session" \
    _probe_qt_env
fi
_probe_xdg_directory() {
  local path; path="$(xdg-user-dir "$1")"
  [[ -d "$path" && "$path" != "$HOME" ]]
}
# xdg user dirs are our userland (ADR 0131), absent from a stock install
if feature_audit_gate xdg-dirs \
  "stock install: no curated userland" feature_audit_curated; then
  for xdg_directory in DESKTOP DOCUMENTS DOWNLOAD MUSIC PICTURES VIDEOS; do
    feature_audit_check "xdg-dir-${xdg_directory,,}" \
      "xdg user dir $xdg_directory exists" _probe_xdg_directory "$xdg_directory"
  done
fi
# ADR 0147: a copy outlives the app that made it
_probe_clip() {
  # wl-copy forks a clipboard server: detach it from our output pipe
  printf 'fa-clip-%s' "$$" | timeout 5 wl-copy >/dev/null 2>&1
  sleep 1
  [[ "$(timeout 5 wl-paste -n)" == "fa-clip-$$" ]]
}
feature_audit_check clipboard-keepalive \
  "clipboard survives its source exiting" _probe_clip
feature_audit_check portal "xdg-desktop-portal answers on the session bus" \
  busctl --user call org.freedesktop.portal.Desktop \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
