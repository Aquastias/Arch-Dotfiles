# shellcheck shell=bash
# Feature Audit probe for lact (ADR 0152; contract: PROGRAM_SPEC.md). GPU
# tuning needs a real AMD/NVIDIA GPU (unverifiable in a VM).
feature_audit_require_package lact lact || return 0
feature_audit_as_root || return 0
feature_audit_check lactd-enabled "lactd.service enabled" \
  systemctl is-enabled --quiet lactd
feature_audit_check lactd-active "lactd.service active (daemon starts without a GPU)" \
  feature_audit_unit_active lactd
