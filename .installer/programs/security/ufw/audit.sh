# shellcheck shell=bash
# Feature Audit probe for ufw (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg ufw ufw || return 0
fa_as_root || return 0
fa_check ufw-service "ufw.service active" fa_unit_active ufw
fa_check ufw-active "ufw status: active" \
  sh -c 'ufw status | grep -q "Status: active"'
fa_check ufw-ssh "ssh allowed" sh -c 'ufw status | grep -qiE "22|ssh"'
fa_check ufw-nat "libvirt NAT masquerade rules present" \
  grep -q MASQUERADE /etc/ufw/before.rules
