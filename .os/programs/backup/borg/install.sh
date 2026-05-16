#!/usr/bin/env bash
# =============================================================================
# programs/backup/borg/install.sh
# =============================================================================
# Invoked by .os/lib/profiles.sh inside arch-chroot, as the owning user, with
# OS_DIR, PROGRAMS, SHELL_COMMONS pre-exported and temp NOPASSWD sudo granted.
#
# Installs borgbackup + Vorta GUI + borgmatic via paru, writes a starter
# borgmatic config for the first regular user, and enables the borgmatic
# daily timer. Repo init and passphrase setup must be done post-boot.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[borg] error on line $LINENO" >&2' ERR

print_status info "Installing borgbackup, vorta, and borgmatic..."
paru -S --noconfirm --needed borgbackup vorta python-borgmatic

FIRST_USER="$(awk -F: '$3>=1000 && $3<65534{print $1; exit}' \
  /etc/passwd || true)"

if [[ -n "$FIRST_USER" ]]; then
  cfg_dir="/home/${FIRST_USER}/.config/borgmatic"
  sudo install -d -o "$FIRST_USER" -g "$FIRST_USER" -m 700 "$cfg_dir"
  sudo tee "${cfg_dir}/config.yaml" >/dev/null <<'BORGCFG'
# Borgmatic configuration — edit before first use.
# Documentation: https://torsion.org/borgmatic/

location:
    source_directories:
        - /home
        - /etc
        - /var/log

    repositories:
        - path: /mnt/backup/borg
          label: local

storage:
    encryption_passcommand: cat /etc/borg-passphrase
    compression: lz4

retention:
    keep_hourly: 24
    keep_daily: 7
    keep_weekly: 4
    keep_monthly: 6

consistency:
    checks:
        - name: repository
        - name: archives
          frequency: 2 weeks
BORGCFG
  sudo chown "${FIRST_USER}:${FIRST_USER}" "${cfg_dir}/config.yaml"
  sudo chmod 600 "${cfg_dir}/config.yaml"
  print_status info "Borgmatic config written to ${cfg_dir}/config.yaml"
fi

print_status info "Enabling borgmatic daily timer..."
sudo systemctl enable borgmatic.timer

print_status success "Borg staged." \
  "Next steps: init repo, set passphrase, run borgmatic."
