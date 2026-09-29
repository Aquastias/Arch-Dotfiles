# shellcheck shell=bash
# shellcheck disable=SC2016 # sh -c bodies expand in the child shell
# Feature Audit probe for firewalld (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg firewalld firewalld || return 0
fa_as_root || return 0
fa_check firewalld-active "firewalld.service active" fa_unit_active firewalld
fa_check firewalld-state "firewall-cmd --state = running" \
  sh -c '[ "$(firewall-cmd --state 2>&1)" = running ]'
fa_check firewalld-libvirt "libvirt zone present (bridge support)" \
  sh -c 'firewall-cmd --get-zones | grep -qw libvirt'
fa_check firewalld-ssh "ssh allowed in the default zone" \
  sh -c 'firewall-cmd --list-services | grep -qw ssh'
