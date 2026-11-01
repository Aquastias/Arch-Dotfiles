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
# ADR 0162: on a KDE co-install the Secret portal routes to kwallet, and that
# backend answers
_probe_kde_installed() {
  [[ "$(feature_audit_config \
    '.environment.desktop | index("kde") != null')" == true ]]
}
_probe_secret_portal_kwallet() {
  grep -qx 'org.freedesktop.impl.portal.Secret=kwallet;' \
    /etc/xdg-desktop-portal/niri-portals.conf \
    && busctl --user call org.freedesktop.impl.portal.desktop.kwallet \
      /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
}
if feature_audit_gate niri-secret-portal "no KDE co-install" _probe_kde_installed
then
  feature_audit_check niri-secret-portal-kwallet \
    "the Secret portal routes to kwallet, which answers" \
    _probe_secret_portal_kwallet
fi
