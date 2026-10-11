# shellcheck shell=bash
# Feature Audit probe for ccache (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package ccache ccache || return 0
feature_audit_as_root || return 0
feature_audit_check ccache-makepkg "ccache enabled in makepkg BUILDENV" \
  sh -c 'grep -E "^BUILDENV=" /etc/makepkg.conf | grep -qE "[( ]ccache"'
feature_audit_check ccache-runs "ccache reports stats" ccache -s
