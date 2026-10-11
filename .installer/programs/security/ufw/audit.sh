# shellcheck shell=bash
# Feature Audit probe for ufw (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package ufw ufw || return 0
feature_audit_as_root || return 0
feature_audit_check ufw-service \
  "ufw.service active" feature_audit_unit_active ufw
feature_audit_check ufw-active "ufw status: active" \
  sh -c 'ufw status | grep -q "Status: active"'
feature_audit_check ufw-ssh "ssh allowed" sh \
  -c 'ufw status | grep -qiE "22|ssh"'
feature_audit_check ufw-nat "libvirt NAT masquerade rules present" \
  grep -q MASQUERADE /etc/ufw/before.rules
