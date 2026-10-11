# shellcheck shell=bash
# Feature Audit probe for reflector (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package reflector reflector || return 0
feature_audit_as_root || return 0
feature_audit_check reflector-timer "reflector.timer enabled" \
  systemctl is-enabled --quiet reflector.timer
feature_audit_check reflector-conf "reflector config present" \
  test -s /etc/xdg/reflector/reflector.conf
feature_audit_check reflector-mirrorlist "mirrorlist has servers" \
  grep -q '^Server' /etc/pacman.d/mirrorlist
