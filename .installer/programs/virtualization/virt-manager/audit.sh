# shellcheck shell=bash
# Feature Audit probe for virt-manager (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg virt-manager virt-manager || return 0
if fa_as_root; then
  fa_check libvirtd "libvirtd enabled" systemctl is-enabled --quiet libvirtd
  fa_check kvm-device "/dev/kvm present (nested virt)" test -e /dev/kvm
  return 0
fi
if ! id -nG | grep -qw libvirt; then
  fa_skip libvirt-user "$FA_USER not in libvirt"; return 0
fi
fa_check virsh-system "qemu:///system reachable as a libvirt user" \
  virsh -c qemu:///system list --all
fa_check virsh-net "a default network is defined" \
  sh -c 'virsh -c qemu:///system net-list --all | grep -q default'
