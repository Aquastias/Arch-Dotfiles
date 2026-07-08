#!/usr/bin/env bats
# Tests for the VM-Profile Synthesizer + oracle dispatch (combination-matrix/05,
# ADR 0046). Pure: a generated cell → its disk count (Σ disk_count), verify
# block (the oracle table), and install-timeout band (light/heavy). Behaviour
# under test is the derived profile fields, never how they're computed.

setup() {
  OS_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export OS_DIR
  # shellcheck source=../../lib/matrix/synth.sh
  source "$OS_DIR/lib/matrix/synth.sh"
}

# a minimal cell fixture: only the axes the synthesizer reads.
_cell() { printf '{"id":"c","tier":1,"axes":%s}' "$1"; }

# ── AC1: disk count = Σ disk_count (root topology + data pool) ───────────────

@test "disk_count: single→1, mirror→2, raidz1→3, raidz2→4, + data pool" {
  [ "$(matrix_cell_disk_count "$(_cell '{"disk_count":1}')")" -eq 1 ]
  [ "$(matrix_cell_disk_count "$(_cell '{"disk_count":2}')")" -eq 2 ]
  [ "$(matrix_cell_disk_count "$(_cell '{"disk_count":3}')")" -eq 3 ]
  [ "$(matrix_cell_disk_count "$(_cell '{"disk_count":4}')")" -eq 4 ]
  # a data pool adds its own disks
  [ "$(matrix_cell_disk_count \
    "$(_cell '{"disk_count":2,"data_pool":{"disk_count":1}}')")" -eq 3 ]
}

# ── AC2: the verify block matches the oracle table ──────────────────────────

@test "verify: plain cell → first-boot sentinel only" {
  local v; v="$(matrix_cell_verify \
    "$(_cell '{"encryption":false,"impermanence":false}')")"
  echo "$v" | jq -e '.boot == true and (has("rollback") | not)'
  [ "$(matrix_cell_boot_verify \
    "$(_cell '{"encryption":false,"impermanence":false}')")" = true ]
}

@test "verify: impermanent cell → boot + rollback (two-boot proof)" {
  local v; v="$(matrix_cell_verify \
    "$(_cell '{"encryption":false,"impermanence":true}')")"
  echo "$v" | jq -e '.boot == true and .rollback == true'
}

@test "verify: encrypted cell boot-verifies (issue 07 oracle flip)" {
  # The Console Answerer supplies the passphrase over serial, so encrypted is
  # no longer install-only — it gets the first-boot sentinel like its peer.
  local c='{"encryption":true,"impermanence":false}'
  echo "$(matrix_cell_verify "$(_cell "$c")")" \
    | jq -e '.boot == true and (has("rollback") | not)'
  [ "$(matrix_cell_boot_verify "$(_cell "$c")")" = true ]
}

@test "verify: encrypted impermanent → boot + rollback (two-boot proof)" {
  local c='{"encryption":true,"impermanence":true}'
  echo "$(matrix_cell_verify "$(_cell "$c")")" \
    | jq -e '.boot == true and .rollback == true'
  [ "$(matrix_cell_boot_verify "$(_cell "$c")")" = true ]
}

@test "verify: gpu≠auto cell → install-only (driver install, no boot-verify)" {
  [ "$(matrix_cell_verify \
    "$(_cell '{"encryption":false,"gpu":"nvidia"}')")" = null ]
  [ "$(matrix_cell_boot_verify \
    "$(_cell '{"encryption":false,"gpu":"amd"}')")" = false ]
}

# ── AC3: install timeout band (light / heavy) ───────────────────────────────

@test "timeout: storage-only cell is light; desktop or nvidia is heavy" {
  [ "$(matrix_cell_timeout "$(_cell '{"disk_count":1}')")" -eq 2700 ]
  [ "$(matrix_cell_timeout "$(_cell '{"desktop":"kde"}')")" -eq 5400 ]
  [ "$(matrix_cell_timeout "$(_cell '{"desktop":"none","gpu":"nvidia"}')")" \
    -eq 5400 ]
  [ "$(matrix_cell_timeout "$(_cell '{"desktop":"none","gpu":"auto"}')")" \
    -eq 2700 ]
}

# ── the synthesized profile carries disks/verify/timeout/install ────────────

@test "synthesize: a mirror impermanent cell → 2 disks, rollback, install cfg" {
  local cell
  cell="$(_cell '{"filesystem":"zfs","mode":"single","topology":"single",
    "disk_count":2,"encryption":false,"impermanence":true,"data_pool":null}')"
  local p; p="$(matrix_cell_synthesize "$cell")"
  echo "$p" | jq -e '(.hardware.disks | length) == 2'
  echo "$p" | jq -e '.hardware.disks | all(. == 40)'  # proven-installable size
  echo "$p" | jq -e '.verify.rollback == true'
  echo "$p" | jq -e '.timeouts.install == 2700'
  echo "$p" | jq -e '.install | type == "object"'
}
