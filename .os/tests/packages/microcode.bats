#!/usr/bin/env bats
# Tests for lib/packages/microcode.sh — per-vendor CPU microcode resolution.
#
# Strategy: override _microcode_cpuinfo() as an injectable seam so tests
# control the detected CPU vendor without real hardware (mirrors the GPU
# resolution _gpu_lspci_output seam in lib/config/environment.sh).

setup() {
  error() { echo "ERROR: $*" >&2; exit 1; }
  # shellcheck source=../../lib/packages/microcode.sh
  source "$BATS_TEST_DIRNAME/../../lib/packages/microcode.sh"
}

# ── microcode_vendor_package ──────────────────────────────────────────────

@test "microcode_vendor_package: intel → intel-ucode" {
  run microcode_vendor_package intel
  [ "$status" -eq 0 ]
  [ "$output" = "intel-ucode" ]
}

@test "microcode_vendor_package: amd → amd-ucode" {
  run microcode_vendor_package amd
  [ "$status" -eq 0 ]
  [ "$output" = "amd-ucode" ]
}

@test "microcode_vendor_package: unknown vendor → empty (no package)" {
  run microcode_vendor_package ""
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── microcode_detect_vendor (mocked cpuinfo seam) ─────────────────────────

@test "microcode_detect_vendor: GenuineIntel → intel" {
  _microcode_cpuinfo() { printf 'vendor_id\t: GenuineIntel\n'; }
  run microcode_detect_vendor
  [ "$status" -eq 0 ]
  [ "$output" = "intel" ]
}

@test "microcode_detect_vendor: AuthenticAMD → amd" {
  _microcode_cpuinfo() { printf 'vendor_id\t: AuthenticAMD\n'; }
  run microcode_detect_vendor
  [ "$status" -eq 0 ]
  [ "$output" = "amd" ]
}

@test "microcode_detect_vendor: VM/unknown vendor → empty" {
  _microcode_cpuinfo() { printf 'vendor_id\t: KVMKVMKVM\n'; }
  run microcode_detect_vendor
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── microcode_present_initrds (only existing *-ucode.img → entry lines) ────

@test "microcode_present_initrds: only intel present → single intel line" {
  d="$(mktemp -d)"; : >"$d/intel-ucode.img"
  run microcode_present_initrds "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "initrd  /intel-ucode.img" ]
  rm -rf "$d"
}

@test "microcode_present_initrds: empty dir → no lines (no dangling initrd)" {
  d="$(mktemp -d)"
  run microcode_present_initrds "$d"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  rm -rf "$d"
}

@test "microcode_present_initrds: both present → intel then amd" {
  d="$(mktemp -d)"; : >"$d/intel-ucode.img"; : >"$d/amd-ucode.img"
  run microcode_present_initrds "$d"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "initrd  /intel-ucode.img" ]
  [ "${lines[1]}" = "initrd  /amd-ucode.img" ]
  rm -rf "$d"
}
