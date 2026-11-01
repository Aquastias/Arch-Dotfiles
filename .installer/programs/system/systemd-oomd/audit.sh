# shellcheck shell=bash
# Feature Audit probe for systemd-oomd (ADR 0152; contract: PROGRAM_SPEC.md).
# Inducing real memory pressure is out of scope; the probe proves oomd runs
# and monitors the slices the drop-ins name.
feature_audit_as_root || return 0
feature_audit_check systemd-oomd-active "systemd-oomd.service active" \
  feature_audit_unit_active systemd-oomd.service
feature_audit_check systemd-oomd-system-slice \
  "oomd monitors system.slice memory pressure" \
  sh -c 'oomctl | grep -q "Path: /system.slice"'
