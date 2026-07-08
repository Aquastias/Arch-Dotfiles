#!/usr/bin/env bash
# =============================================================================
# lib/matrix/synth.sh — Combination Matrix VM-Profile Synthesizer + oracle
# =============================================================================
# Turns a generated cell into a ready-to-run ephemeral VM Profile (ADR 0046) and
# routes it to the right oracle. Pure: cell JSON in, profile JSON out; no TTY,
# no disk writes. The assembled Effective Config (the config seam) is baked in by
# matrix_cell_assemble.
#
#   hardware.disks    Σ disk_count across the root pool + a data pool, each
#                     DISK_GIB (default 20).
#   verify            the oracle table: plain → first-boot sentinel; impermanent
#                     → +rollback (two-boot proof); encrypted boot-verifies via
#                     the Console Answerer (issue 07); only gpu≠auto is
#                     install-only (a virtual GPU can't exercise a real driver).
#   timeouts.install  the light/heavy band — heavy (any desktop or nvidia) gets
#                     the long budget so a real DE/driver install can't false-fail.
#
# Public API:
#   matrix_cell_disk_count  <cell>            → Σ disk_count
#   matrix_cell_verify      <cell>            → the verify block JSON (or "null")
#   matrix_cell_boot_verify <cell>            → "true" | "false"
#   matrix_cell_timeout     <cell>            → install timeout (seconds)
#   matrix_cell_synthesize  <cell> [disk_gib] → the VM Profile JSON
# =============================================================================

# shellcheck source=./assemble.sh
[[ "$(type -t matrix_cell_assemble)" == "function" ]] \
  || source "${BASH_SOURCE[0]%/*}/assemble.sh"

# the light/heavy install-timeout bands, in seconds (45 min / 90 min).
: "${MATRIX_TIMEOUT_LIGHT:=2700}"
: "${MATRIX_TIMEOUT_HEAVY:=5400}"

# Per-disk size (GiB). The PRD's 20 GiB estimate is too small for a real zfs
# root: with the default ~5 GiB swap zvol (refreserved) + the OS + impermanence
# datasets, a ~16 GiB rpool runs out of space (`cannot create rpool/swap: out of
# space`, VM-observed). 40 GiB is the proven-installable size (qcow2 is sparse,
# so unused space costs nothing). Override with MATRIX_DISK_GIB.
: "${MATRIX_DISK_GIB:=40}"

# matrix_cell_disk_count <cell> — Σ disk_count over the root topology and a
# data pool (the cell already carries each group's disk_count).
matrix_cell_disk_count() {
  jq -r '(.axes.disk_count // 1)
         + (.axes.data_pool.disk_count // 0)' <<<"$1"
}

# matrix_cell_is_heavy <cell> — "true" iff the cell pulls a heavy install (any
# desktop or the nvidia driver); AUR is baseline for every cell so it does not
# tip the band.
matrix_cell_is_heavy() {
  jq -r '((.axes.desktop // "none") != "none")
         or ((.axes.gpu // "auto") == "nvidia")' <<<"$1"
}

# matrix_cell_timeout <cell> — the install timeout for the cell's band (seconds).
matrix_cell_timeout() {
  if [[ "$(matrix_cell_is_heavy "$1")" == true ]]; then
    printf '%s\n' "$MATRIX_TIMEOUT_HEAVY"
  else
    printf '%s\n' "$MATRIX_TIMEOUT_LIGHT"
  fi
}

# matrix_cell_boot_verify <cell> — "true" iff the cell boot-verifies. Encrypted
# cells now boot-verify too: the Console Answerer (issue 07) supplies the
# passphrase over serial. Only gpu≠auto stays install-only — a virtual GPU can't
# exercise a real driver.
matrix_cell_boot_verify() {
  jq -r 'if ((.axes.gpu // "auto") != "auto") then false
         else true end' <<<"$1"
}

# matrix_cell_verify <cell> — the profile's verify block per the oracle table,
# or "null" for install-only cells. Encryption no longer forces install-only
# (the Answerer drives the unlock); gpu≠auto still does.
matrix_cell_verify() {
  jq -c 'if ((.axes.gpu // "auto") != "auto") then null         # install-only
         elif (.axes.impermanence == true)
            then {boot:true, rollback:true}                     # two-boot proof
         else {boot:true} end' <<<"$1"                          # first-boot
}

# matrix_cell_synthesize <cell> [disk_gib] — the ephemeral VM Profile JSON.
matrix_cell_synthesize() {
  local cell="$1" gib="${2:-$MATRIX_DISK_GIB}" n verify timeout install
  n="$(matrix_cell_disk_count "$cell")"
  verify="$(matrix_cell_verify "$cell")"
  timeout="$(matrix_cell_timeout "$cell")"
  install="$(matrix_cell_assemble "$cell")"

  jq -n \
    --arg name "matrix-$(jq -r '.id' <<<"$cell")" \
    --argjson n "$n" --argjson gib "$gib" \
    --argjson verify "$verify" --argjson timeout "$timeout" \
    --argjson install "$install" '
    {
      name: $name,
      hardware: { disks: [range(0; $n) | $gib], ram_mb: 8192, vcpus: 2 },
      timeouts: { install: $timeout },
      install: $install
    }
    | if $verify != null then . + { verify: $verify } else . end
  '
}
