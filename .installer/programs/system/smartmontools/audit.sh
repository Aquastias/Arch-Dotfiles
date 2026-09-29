# shellcheck shell=bash
# Feature Audit probe for smartmontools (ADR 0152; contract:
# PROGRAM_SPEC.md). The audit VM's disks are SATA, so SMART data is real;
# smartd itself is skipped in VMs by its unit (ConditionVirtualization=no).
fa_require_pkg smartmontools smartmontools || return 0
fa_as_root || return 0
fa_check smartd-enabled "smartd.service enabled" \
  systemctl is-enabled --quiet smartd
if systemd-detect-virt -q; then
  fa_skip smartd-active "smartd skips VMs (ConditionVirtualization=no)"
else
  fa_check smartd-active "smartd.service active" fa_unit_active smartd
fi
fa_check smart-health "SMART overall health PASSED on /dev/sda" \
  sh -c 'smartctl -H /dev/sda | grep -q PASSED'
