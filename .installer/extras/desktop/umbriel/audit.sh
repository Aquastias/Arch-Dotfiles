# shellcheck shell=bash
# Feature Audit desktop probe for Umbriel (ADR 0152/0159): runs inside the
# live Umbriel session as the desktop user (sessions phase). Shared wlroots
# checks live in ../audit-wlroots.sh (staged as audit-fixtures/audit-wlroots.sh).
if [[ "$FA_SESSION" != umbriel ]]; then
  feature_audit_skip umbriel-session "not the running session"; return 0
fi
# Upstream config keys still move between -git builds (ADR 0159): validating
# the active config (curated, or the packaged one on stock) is the tripwire.
feature_audit_check umbriel-config \
  "umbriel validates the active config" umbriel config validate
feature_audit_check umbriel-ipc "Umbriel IPC answers" \
  umbriel workspaces --json
feature_audit_check umbriel-portal \
  "xdg-desktop-portal-umbriel answers (ScreenCast/Screenshot)" \
  busctl --user call org.freedesktop.impl.portal.desktop.umbriel \
    /org/freedesktop/portal/desktop org.freedesktop.DBus.Peer Ping
# shellcheck source=/dev/null
. "$FA_DIR/audit-fixtures/audit-wlroots.sh"
