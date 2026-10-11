# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for firewalld (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package firewalld firewalld || return 0
feature_audit_as_root || return 0
feature_audit_check firewalld-active \
  "firewalld.service active" feature_audit_unit_active firewalld
feature_audit_check firewalld-state "firewall-cmd --state = running" \
  sh -c '[ "$(firewall-cmd --state 2>&1)" = running ]'
feature_audit_check firewalld-libvirt "libvirt zone present (bridge support)" \
  sh -c 'firewall-cmd --get-zones | grep -qw libvirt'
feature_audit_check firewalld-ssh "ssh allowed in the default zone" \
  sh -c 'firewall-cmd --list-services | grep -qw ssh'
