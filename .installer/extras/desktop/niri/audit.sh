# shellcheck shell=bash
# Feature Audit desktop probe for niri (ADR 0152): runs inside the live niri
# session as the desktop user (sessions phase). Shared wlroots checks live in
# ../audit-wlroots.sh (staged as audit-fixtures/audit-wlroots.sh).
if [[ "$FA_SESSION" != niri ]]; then
  feature_audit_skip niri-session "not the running session"; return 0
fi
feature_audit_check niri-config \
  "niri validates the shipped config" niri validate
feature_audit_check niri-ipc "niri IPC answers" niri msg -j version
# shellcheck source=/dev/null
. "$FA_DIR/audit-fixtures/audit-wlroots.sh"
# ADR 0162: on a KDE co-install, Plasma's background apps skip niri; the
# wallet unlock still runs
_probe_kde_box() {
  feature_audit_has_shell \
    && feature_audit_config '.environment.desktop | index("kde") != null' \
      | grep -qx true
}
_probe_autostart_skipped() {
  ! pgrep -u "$FA_USER" -x "$1" >/dev/null \
    && [[ "$(systemctl --user show -P ConditionResult "$2")" == no ]]
}
if feature_audit_gate niri-kde-autostart \
  "no KDE co-install with a shell" _probe_kde_box; then
  feature_audit_check niri-skip-kalendarac "kalendarac does not start" \
    _probe_autostart_skipped kalendarac app-org.kde.kalendarac@autostart.service
  feature_audit_check niri-skip-kdeconnectd "kdeconnectd does not start" \
    _probe_autostart_skipped kdeconnectd \
    app-org.kde.kdeconnect.daemon@autostart.service
  feature_audit_check niri-skip-nm-applet "nm-applet does not start" \
    _probe_autostart_skipped nm-applet 'app-nm\x2dapplet@autostart.service'
  feature_audit_check niri-kwallet-init "pam_kwallet_init still runs" \
    test "$(systemctl --user show -P ConditionResult \
      app-pam_kwallet_init@autostart.service)" = yes
fi
