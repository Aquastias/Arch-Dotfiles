# shellcheck shell=bash
# Feature Audit probe for virt-manager (ADR 0152; contract: PROGRAM_SPEC.md).
feature_audit_require_package virt-manager virt-manager || return 0
if feature_audit_as_root; then
  feature_audit_check libvirtd "libvirtd enabled" systemctl is-enabled \
    --quiet libvirtd
  feature_audit_check kvm-device "/dev/kvm present (nested virt)" test \
    -e /dev/kvm
  return 0
fi
if ! id -nG | grep -qw libvirt; then
  feature_audit_skip libvirt-user "$FA_USER not in libvirt"; return 0
fi
feature_audit_check virsh-system "qemu:///system reachable as a libvirt user" \
  virsh -c qemu:///system list --all
feature_audit_check virsh-net "a default network is defined" \
  sh -c 'virsh -c qemu:///system net-list --all | grep -q default'
