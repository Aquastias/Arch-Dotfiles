# shellcheck shell=bash
# Feature Audit probe for bluetooth (ADR 0152; contract: PROGRAM_SPEC.md).
# No Bluetooth adapter exists in a VM: only the service wiring is provable.
fa_require_pkg bluetooth bluez || return 0
fa_as_root || return 0
fa_check bluetooth-enabled "bluetooth.service enabled" \
  systemctl is-enabled --quiet bluetooth
fa_check bluetoothctl "bluetoothctl runs" bluetoothctl --version
if [[ -d /sys/class/bluetooth ]]; then
  fa_check bluetooth-active "bluetooth.service active" \
    fa_unit_active bluetooth
else
  fa_skip bluetooth-active "no Bluetooth adapter in the VM"
fi
