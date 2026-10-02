#!/usr/bin/env bash
# =============================================================================
# programs/backup/borg/install.sh
# =============================================================================
# Invoked by .installer/lib/profiles/runner.sh inside arch-chroot, as the owning user, with
# INSTALLER_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo
# granted.
#
# Installs borgbackup + Vorta GUI + borgmatic via paru, ships a starter
# system config as /etc/borgmatic/config.yaml.example, and enables the daily
# borgmatic.timer gated on the real /etc/borgmatic/config.yaml: until the
# operator inits a repo and writes that file, each run is skipped, not failed;
# after it, backups start with no extra step. (The system unit reads /etc,
# and the sources include /etc + /var/log, which need root.)
# =============================================================================

set -Eeuo pipefail
trap 'echo "[borg] error on line $LINENO" >&2' ERR

print_status info "Installing borgbackup, vorta, and borgmatic..."
# borgmatic was renamed from python-borgmatic in the Arch repos; the old name no
# longer resolves ("could not find all required packages").
${AUR_HELPER} -S --noconfirm --needed borgbackup vorta borgmatic

# Current (flat, borgmatic >= 1.8) schema: `borgmatic config validate`.
sudo install -d -o root -g root -m 755 /etc/borgmatic
sudo tee /etc/borgmatic/config.yaml.example >/dev/null <<'BORGCFG'
# borgmatic starter config: edit, init the repo, then save as config.yaml
# (the daily timer skips until /etc/borgmatic/config.yaml exists).
# Documentation: https://torsion.org/borgmatic/
source_directories:
    - /home
    - /etc
    - /var/log
repositories:
    - path: /mnt/backup/borg
      label: local
encryption_passcommand: cat /etc/borg-passphrase
compression: lz4
keep_hourly: 24
keep_daily: 7
keep_weekly: 4
keep_monthly: 6
checks:
    - name: repository
    - name: archives
      frequency: 2 weeks
BORGCFG
print_status info "Starter config: /etc/borgmatic/config.yaml.example"

sudo install -d -o root -g root -m 755 /etc/systemd/system/borgmatic.service.d
sudo tee /etc/systemd/system/borgmatic.service.d/10-require-config.conf \
  >/dev/null <<'DROPIN'
# Skip (not fail) until the operator writes the real config.
[Unit]
ConditionPathExists=/etc/borgmatic/config.yaml
DROPIN

print_status info "Enabling borgmatic daily timer..."
sudo systemctl enable borgmatic.timer

print_status success "Borg staged." \
  "Next steps: init repo, set passphrase, save config.yaml from the example."
