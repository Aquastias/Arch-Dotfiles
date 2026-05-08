#!/usr/bin/env bash
# lib/chroot/extras.sh — Chroot Configuration Module: optional post-install scripts
# Runs inside arch-chroot. Reads install-state.json; scripts sourced from /root/extras/.
set -Eeuo pipefail
trap 'echo "[chroot:extras] failed at line $LINENO" >&2' ERR

STATE=/root/lib-chroot/install-state.json
DO_KDE="$(     jq -r '.extras.kde'      "$STATE")"
DO_BACKUP="$(  jq -r '.extras.backup'   "$STATE")"
DO_SECURITY="$(jq -r '.extras.security' "$STATE")"

if [[ "$DO_KDE" == "true" ]]; then
    if [[ -f /root/extras/desktop/kde/kde.sh ]]; then
        echo "[INFO] Running KDE installer..."
        bash /root/extras/desktop/kde/kde.sh
    else
        echo "[ERROR] KDE enabled but /root/extras/desktop/kde/kde.sh not found." >&2
        echo "        Ensure extras/desktop/kde/kde.sh exists in your installer directory." >&2
        exit 1
    fi
fi

if [[ "$DO_BACKUP" == "true" ]]; then
    if [[ -f /root/extras/backup.sh ]]; then
        bash /root/extras/backup.sh
    else
        echo "[WARN] backup enabled but /root/extras/backup.sh not found — skipping."
    fi
fi

if [[ "$DO_SECURITY" == "true" ]]; then
    if [[ -f /root/extras/security.sh ]]; then
        bash /root/extras/security.sh
    else
        echo "[WARN] security enabled but /root/extras/security.sh not found — skipping."
    fi
fi
