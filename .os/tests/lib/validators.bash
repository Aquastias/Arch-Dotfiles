#!/usr/bin/env bash
# tests/lib/validators.bash — shared validator harness (ADR 0048).
#
# The unprivileged validator tier runs the installer's REAL config generators
# and checks their output with REAL validators (systemd-analyze verify,
# mkinitcpio -n, fstab lint) instead of asserting on emitted argv. This helper
# is the one seam every validator slice shares:
#
#   validators_have <bin>          — is a validator binary installed?
#   validators_skip_unless <bin>   — bats `skip` (never fail) when it is not,
#                                    mirroring tests/audit.sh SKIP semantics so
#                                    the suite stays green on a minimal host.
#   validators_verify_unit <file>  — run `systemd-analyze verify` on ONE unit,
#                                    isolated in a fresh dir. systemd-analyze
#                                    loads every unit in the file's directory,
#                                    so a broken sibling would otherwise pollute
#                                    a good unit's verdict; copying the target
#                                    into its own dir gives a clean per-unit
#                                    signal. Prints the verifier output; returns
#                                    its exit status.

validators_have() {
  command -v "$1" >/dev/null 2>&1
}

validators_skip_unless() {
  validators_have "$1" || skip "validator '$1' not installed"
}

validators_verify_unit() {
  local unit="$1"
  local base iso status
  base="$(basename "$unit")"
  iso="$(mktemp -d)"
  cp "$unit" "$iso/$base"
  systemd-analyze verify "$iso/$base" 2>&1
  status=$?
  rm -rf "$iso"
  return "$status"
}
