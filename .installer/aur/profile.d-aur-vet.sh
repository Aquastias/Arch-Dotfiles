# shellcheck shell=sh
# /etc/profile.d/aur-vet.sh — AUR Vetting login check (ADR 0143). Sourced by
# every login shell (zsh via /etc/zsh/zprofile): warns when a paru.conf
# would run AUR builds without the vetting hook. Silent when all is well.
[ -x /usr/local/bin/aur-vet ] && /usr/local/bin/aur-vet doctor || true
