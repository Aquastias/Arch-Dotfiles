#!/usr/bin/env bash
# =============================================================================
# programs/security/sops/scripts/enable-runtime.sh
# =============================================================================
# Sourced by install.sh (and bats). Enables sops-runtime.service via a vendor
# wants-symlink under /usr/lib — the only enablement location that survives ZFS
# impermanence.
#
# `systemctl enable` writes the symlink to
# /etc/systemd/system/sysinit.target.wants/. Under impermanence /etc is a
# Rollback Dataset (rolled back to @blank every boot) AND bind-covered by the
# Persist Dataset, so that symlink is invisible to PID 1 when it computes the
# boot transaction — sops-runtime.service (WantedBy=sysinit.target, an EARLY
# unit) never auto-starts, even though it is `is-enabled` and runs fine on
# demand. /usr/lib/systemd/system/<target>.wants/ is the canonical vendor-enable
# path, lives on the never-rolled-back root dataset, and is always read at the
# earliest boot transaction. Matches the impermanence curated-mount convention
# (imp_link_wants writes /usr/lib/systemd/system/local-fs.target.wants/).
#
# $1 (root) defaults to "" (production writes under /). Idempotent.
sops_enable_runtime() {
  local root="${1:-}"
  local wants="${root}/usr/lib/systemd/system/sysinit.target.wants"
  install -d -m 755 "$wants"
  ln -sf ../sops-runtime.service "$wants/sops-runtime.service"
}
