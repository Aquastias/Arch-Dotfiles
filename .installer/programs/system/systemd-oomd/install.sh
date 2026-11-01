#!/usr/bin/env bash
# =============================================================================
# programs/system/systemd-oomd/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as root.
# Env vars provided by the runner: INSTALLER_DIR, PROGRAMS, SHELL_COMMONS.
#
# Writes the drop-ins that make systemd-oomd act, mirroring Fedora's
# systemd-oomd-defaults: every system slice and every user-manager slice is
# killed after 20 s above 80% memory pressure. The Arch Wiki only lists oomd
# (Improving performance); the units are per systemd-oomd(8) and
# systemd.resource-control(5). The runner enables systemd-oomd.service.
# OOMD_ROOT prefixes every path (tests); empty in the chroot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[systemd-oomd] error on line $LINENO" >&2' ERR

root="${OOMD_ROOT:-}"

print_status info "Writing systemd-oomd drop-ins..."
install -d "${root}/etc/systemd/oomd.conf.d" \
  "${root}/etc/systemd/system/system.slice.d" "${root}/etc/systemd/user/slice.d"
tee "${root}/etc/systemd/oomd.conf.d/10-oomd-defaults.conf" >/dev/null <<'CONF'
[OOM]
DefaultMemoryPressureDurationSec=20s
CONF
for slice_directory in "${root}/etc/systemd/system/system.slice.d" \
                       "${root}/etc/systemd/user/slice.d"; do
  tee "${slice_directory}/10-oomd-per-slice-defaults.conf" >/dev/null <<'CONF'
[Slice]
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=80%
CONF
done
chmod 644 "${root}/etc/systemd/oomd.conf.d/10-oomd-defaults.conf" \
  "${root}/etc/systemd/system/system.slice.d/10-oomd-per-slice-defaults.conf" \
  "${root}/etc/systemd/user/slice.d/10-oomd-per-slice-defaults.conf"

print_status success "systemd-oomd staged." \
  "oomctl lists the monitored cgroups."
