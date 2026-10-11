# shellcheck shell=bash
# Feature Audit probe for pi (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package pi pi-coding-agent-bin || return 0
feature_audit_as_user || return 0
feature_audit_check pi-runs "pi --version" pi --version
for settings_name in settings mcp web-search; do
  feature_audit_check "pi-$settings_name" \
    "seeded $settings_name.json is valid JSON" \
    jq -e . "$FA_HOME/.pi/agent/$settings_name.json"
done
