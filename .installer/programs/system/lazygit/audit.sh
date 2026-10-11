# shellcheck shell=bash
# Feature Audit probe for lazygit (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package lazygit lazygit || return 0
feature_audit_as_user || return 0
feature_audit_check lazygit-config "curated config applied" \
  test -f "$FA_HOME/.config/lazygit/config.yml"
feature_audit_check lazygit-runs "lazygit starts" lazygit --version
