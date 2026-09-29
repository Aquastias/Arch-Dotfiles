# shellcheck shell=bash
# Feature Audit probe for claude (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg claude claude-code || return 0
fa_as_user || return 0
fa_check claude-runs "claude --version" claude --version
fa_check claude-settings "seeded settings.json is valid JSON" \
  jq -e . "$FA_HOME/.claude/settings.json"
fa_check claude-md "seeded CLAUDE.md present" test -s "$FA_HOME/.claude/CLAUDE.md"
