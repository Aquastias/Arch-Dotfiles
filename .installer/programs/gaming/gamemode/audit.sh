# shellcheck shell=bash
# Feature Audit probe for gamemode (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg gamemode gamemode || return 0
fa_as_user || return 0
fa_check gamemode-run "gamemoderun wraps a process" gamemoderun true
fa_check gamemode-selftest "gamemoded self-test passes" \
  timeout 60 gamemoded -t
