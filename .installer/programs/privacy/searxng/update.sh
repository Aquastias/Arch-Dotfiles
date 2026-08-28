#!/usr/bin/env bash
# =============================================================================
# programs/privacy/searxng/update.sh
# =============================================================================
# Re-runnable post-boot helper. Pulls new images and restarts quadlet units.
# Run manually or via the searxng-update@.timer.
# =============================================================================

set -Eeuo pipefail
trap 'echo "[searxng:update] error on line $LINENO" >&2' ERR

if ! command -v podman &>/dev/null; then
  echo "[searxng:update] error: podman not found" >&2
  exit 1
fi

podman pull docker.io/searxng/searxng:latest
podman pull docker.io/valkey/valkey:alpine

systemctl --user restart valkey.service searxng.service
