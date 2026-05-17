#!/usr/bin/env bash
# lib/chroot/load-state.sh — centralized install-state.json reader
# Source once per chroot sub-script; exports all install-state fields
# as shell vars.
# STATE is injectable for tests; defaults to the production path.
set -Eeuo pipefail

STATE="${STATE:-/root/lib-chroot/install-state.json}"
[[ -f "$STATE" ]] || { echo "[chroot:load-state] missing: $STATE" >&2; exit 1; }

HOSTNAME="$(      jq -r .hostname           "$STATE")"
TIMEZONE="$(      jq -r .timezone           "$STATE")"
LOCALE="$(        jq -r .locale             "$STATE")"
KEYMAP="$(        jq -r .keymap             "$STATE")"
KERNEL="$(        jq -r .kernel             "$STATE")"
BOOTLOADER="$(    jq -r .bootloader         "$STATE")"
RPOOL="$(         jq -r .rpool              "$STATE")"
SWAP="$(          jq -r .swap               "$STATE")"
ESP_COUNT="$(     jq -r .esp_count          "$STATE")"
EXTRAS_BACKUP="$( jq -r '.extras.backup'    "$STATE")"
EXTRAS_SECURITY="$(jq -r '.extras.security' "$STATE")"

# ── Impermanence (defaults: disabled, rpool/persist at /persist) ────────────
IMPERMANENCE_ENABLED="$( jq -r '.impermanence.enabled // false' "$STATE")"
IMPERMANENCE_DATASET="$( jq -r '.impermanence.dataset // "rpool/persist"' \
  "$STATE")"
IMPERMANENCE_MOUNT="$(   jq -r '.impermanence.mount   // "/persist"' \
  "$STATE")"

# ── Persist Extensions (default: empty arrays) ──────────────────────────────
PERSIST_DIRECTORIES=()
PERSIST_FILES=()
mapfile -t PERSIST_DIRECTORIES < <(jq -r \
  '(.persist.directories // [])[]' "$STATE")
mapfile -t PERSIST_FILES < <(jq -r \
  '(.persist.files // [])[]' "$STATE")
