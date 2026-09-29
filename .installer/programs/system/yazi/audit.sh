# shellcheck shell=bash
# Feature Audit probe for yazi (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg yazi yazi || return 0
fa_as_user || return 0
fa_check yazi-theme "ANSI-16 theme applied" \
  test -f "$FA_HOME/.config/yazi/theme.toml"
fa_check yazi-runs "yazi starts" yazi --version
