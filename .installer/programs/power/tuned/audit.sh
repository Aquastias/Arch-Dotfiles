# shellcheck shell=bash
# Feature Audit probe for tuned (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg tuned tuned || return 0
fa_as_root || return 0
fa_check tuned-active "tuned.service active" fa_unit_active tuned
fa_check tuned-profile "a tuned profile is active" \
  sh -c 'tuned-adm active | grep -q "Current active profile"'
fa_check tuned-ppd "tuned-ppd provides the ppd D-Bus API" \
  fa_unit_active tuned-ppd
