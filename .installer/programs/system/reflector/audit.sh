# shellcheck shell=bash
# Feature Audit probe for reflector (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg reflector reflector || return 0
fa_as_root || return 0
fa_check reflector-timer "reflector.timer enabled" \
  systemctl is-enabled --quiet reflector.timer
fa_check reflector-conf "reflector config present" \
  test -s /etc/xdg/reflector/reflector.conf
fa_check reflector-mirrorlist "mirrorlist has servers" \
  grep -q '^Server' /etc/pacman.d/mirrorlist
