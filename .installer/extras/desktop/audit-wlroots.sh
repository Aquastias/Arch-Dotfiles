# shellcheck shell=bash
# Feature Audit shared wlroots-session checks (niri, Hyprland, Umbriel; ADR
# 0152): the Noctalia shell, Qt theming through its templates, xdg user dirs
# (ADR 0131), the clipboard keep-alive (ADR 0147) and the portals.
_probe_qt_env() {
  local pid; pid="$(pgrep -x noctalia | head -n 1)"
  # The process environment, one variable per line (it is NUL-separated).
  tr '\0' '\n' < "/proc/$pid/environ" | grep -qx QT_QPA_PLATFORMTHEME=qt6ct
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
    lower_name="$(printf '%s\n' "$xdg_directory" | tr '[:upper:]' '[:lower:]')"
    feature_audit_check "xdg-dir-$lower_name" \
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
# ADR 0159/0162: niri and Umbriel run XDG autostart, so on a KDE co-install
# the seeded gates keep Plasma's daemons (and nm-applet) out; the wallet
# unlock still runs
_probe_autostart_gated_session() {
  [[ "$FA_SESSION" == niri || "$FA_SESSION" == umbriel ]] \
    && feature_audit_has_shell \
    && [[ "$(feature_audit_config \
      '.environment.desktop | index("kde") != null')" == true ]]
}
_probe_autostart_gated() {
  ! pgrep -u "$FA_USER" -x "$1" >/dev/null \
    && systemctl --user show -P DropInPaths "$2" \
      | grep -q "/${FA_SESSION}.conf"
}
if feature_audit_gate autostart-gates \
  "not niri/Umbriel on a KDE co-install with a shell" \
  _probe_autostart_gated_session; then
  feature_audit_check autostart-skip-kalendarac "kalendarac does not start" \
    _probe_autostart_gated kalendarac app-org.kde.kalendarac@autostart.service
  feature_audit_check autostart-skip-kdeconnectd "kdeconnectd does not start" \
    _probe_autostart_gated kdeconnectd \
    app-org.kde.kdeconnect.daemon@autostart.service
  feature_audit_check autostart-skip-nm-applet "nm-applet does not start" \
    _probe_autostart_gated nm-applet 'app-nm\x2dapplet@autostart.service'
  feature_audit_check autostart-kwallet-init "pam_kwallet_init still runs" \
    test "$(systemctl --user show -P Result \
      app-pam_kwallet_init@autostart.service)" = success
fi
# ADR 0162: the pcmanfm-qt daemon, not an activated Dolphin, owns "Show in
# folder" (busctl status reads the owner without activating)
_probe_filemanager1_owner() {
  busctl --user status org.freedesktop.FileManager1 2>/dev/null \
    | grep -qx 'Comm=pcmanfm-qt'
}
if feature_audit_gate filemanager1 \
  "no Wayland shell in this variant" feature_audit_has_shell; then
  feature_audit_check filemanager1-pcmanfm-qt \
    "pcmanfm-qt owns org.freedesktop.FileManager1" _probe_filemanager1_owner
fi
