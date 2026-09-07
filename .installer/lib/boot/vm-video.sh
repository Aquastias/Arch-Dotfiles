#!/usr/bin/env bash
# =============================================================================
# lib/boot/vm-video.sh — VM Full-HD video kernel-cmdline fragment (deep, pure)
# =============================================================================
# A VM's virtual panel can advertise a sub-Full-HD default surface, so a fresh
# VM install comes up small until someone resizes it. This maps the install's
# detected virtualization to a `video=` kernel command-line fragment that pins a
# Full-HD floor — but ONLY inside a VM (ADR 0119). Bare metal gets an empty
# fragment, so its resolution stays autodetected (ADR 0110) and no monitor is
# ever black-screened by a hardcoded mode.
#
# Pure: the detected virt type in, a (possibly empty) string out — no TTY, no
# globals, no package. The caller runs the detector (systemd-detect-virt) and
# feeds its result here, so the decision is unit-testable without a VM. Staged
# into the chroot lib dir and sourced by the Bootloader Adapters, like zswap.sh.
#
# Public API:
#   vm_video_cmdline_params <virt-type>  → cmdline fragment (or empty)
# =============================================================================

# vm_video_cmdline_params <virt-type> — the Full-HD `video=` fragment when
# <virt-type> names any hypervisor (a non-empty, non-"none" systemd-detect-virt
# result), otherwise empty. "none"/empty (bare metal, or detection unavailable)
# emits nothing — the safe default. The virtio-gpu connector is "Virtual-1".
vm_video_cmdline_params() {
  local virt="${1:-none}"
  [[ -n "$virt" && "$virt" != "none" ]] \
    && printf 'video=Virtual-1:1920x1080'
  return 0
}
