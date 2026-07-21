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
#   validators_verify_unit <file>  — `systemd-analyze verify` on ONE unit,
#                                    isolated (see below). Prints output;
#                                    returns its exit status.
#   validators_verify_user_unit <f> — structural `verify --user` for a service
#                                    unit, tolerating target-only references.
#   validators_skip_unless_hooks_installable <hooks> — skip if a hook is absent.
#   validators_mkinitcpio_build <conf> — build a mkinitcpio.conf to /dev/null.
#   validators_fstab_lint <file>   — structural fstab field/mountpoint lint.
#
# systemd-analyze loads every unit in a file's directory, so a broken sibling
# would otherwise pollute a good unit's verdict; _validators_verify_isolated
# copies the target into a fresh dir (0644 — verify warns on an executable unit
# file) to give a clean per-unit signal.

validators_have() {
  command -v "$1" >/dev/null 2>&1
}

validators_skip_unless() {
  validators_have "$1" || skip "validator '$1' not installed"
}

# Copy <unit> into a fresh isolated dir and run `systemd-analyze verify` with
# any extra args (e.g. --user). Prints output; returns verify's exit status.
_validators_verify_isolated() {
  local unit="$1"; shift
  local base iso status
  base="$(basename "$unit")"
  iso="$(mktemp -d)"
  cp "$unit" "$iso/$base"
  chmod 0644 "$iso/$base"
  systemd-analyze verify "$@" "$iso/$base" 2>&1
  status=$?
  rm -rf "$iso"
  return "$status"
}

validators_verify_unit() {
  _validators_verify_isolated "$1"
}

# Structural `verify --user` for a service unit. A service references things the
# installer only puts on the TARGET system: ExecStart binaries (verify:
# "Command … is not executable") and dependency units from other packages
# ("Unit … not found"). Those are environmental, not unit defects, so both
# classes are tolerated (anchored to systemd's exact phrasings — an arbitrary
# line merely containing "not found" is NOT tolerated). Everything else verify
# emits — unknown keys, bad settings, malformed sections — fails the check.
#
# LIMIT: because a missing dependency unit is indistinguishable here from a
# typo'd Requires=/After= target (both read "Unit X not found"), a dependency-
# NAME typo is not caught by this tier; the VM smoke tier catches it once the
# real deps are present. This tier's job is malformed-unit syntax.
validators_verify_user_unit() {
  local out remainder
  out="$(_validators_verify_isolated "$1" --user)"
  remainder="$(grep -vE ': Command .* is not executable|Unit [^ ]+ not found' \
    <<<"$out" | grep -v '^[[:space:]]*$')"
  if [[ -n "$remainder" ]]; then
    printf '%s\n' "$remainder"
    return 1
  fi
  return 0
}

# mkinitcpio can only build a HOOKS list whose install scripts all exist on the
# host (a non-archzfs host has no `zfs` hook, etc.). Skip when any hook in a
# HOOKS=(...) list — or a bare hook string — is unavailable, so the slice stays
# green everywhere and runs for real where the hooks are present.
validators_skip_unless_hooks_installable() {
  local hooks="${1//HOOKS=(/}"; hooks="${hooks//)/}"
  local h
  for h in $hooks; do
    [[ -f "/usr/lib/initcpio/install/$h" ]] \
      || skip "initcpio hook '$h' not installed on host"
  done
}

# Build the given mkinitcpio.conf to /dev/null (no image kept, no post hooks).
# Prints combined output; returns mkinitcpio's exit status. The caller must
# have skipped when mkinitcpio or a referenced hook is absent.
validators_mkinitcpio_build() {
  mkinitcpio -c "$1" -g /dev/null --nopost 2>&1
}

# Structural fstab lint (no privileged findmnt --verify needed): every
# non-blank, non-comment line must have exactly the 6 fstab fields
# (<device> <mountpoint> <fstype> <options> <dump> <pass>), a mountpoint that is
# absolute or none/swap, an alphanumeric fstype, dump ∈ {0,1}, pass ∈ {0,1,2},
# and no real mountpoint repeated. Prints the first violation; returns non-zero
# on any. Reads the fstab at <file>.
validators_fstab_lint() {
  local file="$1" mp fs dump pass extra line
  local -A seen=()
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" || "$line" == \#* ]] && continue
    # fields: <device> <mountpoint> <fstype> <options> <dump> <pass>; device
    # and options are not linted here, so read them into the throwaway `_`.
    read -r _ mp fs _ dump pass extra <<<"$line"
    if [[ -z "$pass" || -n "$extra" ]]; then
      echo "fstab: line needs exactly 6 fields: $line"; return 1
    fi
    if [[ "$mp" != /* && "$mp" != none && "$mp" != swap ]]; then
      echo "fstab: implausible mountpoint '$mp': $line"; return 1
    fi
    [[ "$fs" == *[!a-zA-Z0-9._-]* || -z "$fs" ]] && {
      echo "fstab: bad fstype '$fs': $line"; return 1; }
    [[ "$dump" == [01] ]] || { echo "fstab: dump not 0/1: $line"; return 1; }
    [[ "$pass" == [012] ]] || { echo "fstab: pass not 0/1/2: $line"; return 1; }
    if [[ "$mp" == /* ]]; then
      [[ -n "${seen[$mp]:-}" ]] && {
        echo "fstab: duplicate mountpoint '$mp'"; return 1; }
      seen[$mp]=1
    fi
  done < "$file"
  return 0
}
