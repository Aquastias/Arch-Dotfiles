# shellcheck shell=bash
# Feature Audit probe for claude (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package claude claude-code || return 0
feature_audit_as_user || return 0
feature_audit_check claude-runs "claude --version" claude --version
feature_audit_check claude-settings "seeded settings.json is valid JSON" \
  jq -e . "$FA_HOME/.claude/settings.json"
feature_audit_check claude-md "seeded CLAUDE.md present" \
  test -s "$FA_HOME/.claude/CLAUDE.md"
