# shellcheck shell=bash
# Feature Audit probe for yazi (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package yazi yazi || return 0
feature_audit_as_user || return 0
feature_audit_check yazi-theme "ANSI-16 theme applied" \
  test -f "$FA_HOME/.config/yazi/theme.toml"
feature_audit_check yazi-runs "yazi starts" yazi --version
