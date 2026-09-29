# shellcheck shell=bash
# Feature Audit probe for lact (ADR 0152; contract: PROGRAM_SPEC.md). GPU
# tuning needs a real AMD/NVIDIA GPU (unverifiable in a VM).
fa_require_pkg lact lact || return 0
fa_as_root || return 0
fa_check lactd-enabled "lactd.service enabled" \
  systemctl is-enabled --quiet lactd
fa_check lactd-active "lactd.service active (daemon starts without a GPU)" \
  fa_unit_active lactd
