# shellcheck shell=bash
# Feature Audit probe for bluetooth (ADR 0152; contract: PROGRAM_SPEC.md).
# No Bluetooth adapter exists in a VM: only the service wiring is provable.
feature_audit_require_package bluetooth bluez || return 0
feature_audit_as_root || return 0
feature_audit_check bluetooth-enabled "bluetooth.service enabled" \
  systemctl is-enabled --quiet bluetooth
feature_audit_check bluetoothctl "bluetoothctl runs" bluetoothctl --version
if [[ -d /sys/class/bluetooth ]]; then
  feature_audit_check bluetooth-active "bluetooth.service active" \
    feature_audit_unit_active bluetooth
else
  feature_audit_skip bluetooth-active "no Bluetooth adapter in the VM"
fi
