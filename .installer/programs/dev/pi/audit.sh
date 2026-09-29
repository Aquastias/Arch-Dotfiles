# shellcheck shell=bash
# Feature Audit probe for pi (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg pi pi-coding-agent-bin || return 0
fa_as_user || return 0
fa_check pi-runs "pi --version" pi --version
for f in settings mcp web-search; do
  fa_check "pi-$f" "seeded $f.json is valid JSON" \
    jq -e . "$FA_HOME/.pi/agent/$f.json"
done
