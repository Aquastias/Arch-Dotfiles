# shellcheck shell=bash
# Feature Audit probe for pi (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package pi pi-coding-agent-bin || return 0
feature_audit_as_user || return 0
feature_audit_check pi-runs "pi --version" pi --version
for f in settings mcp web-search; do
  feature_audit_check "pi-$f" "seeded $f.json is valid JSON" \
    jq -e . "$FA_HOME/.pi/agent/$f.json"
done
