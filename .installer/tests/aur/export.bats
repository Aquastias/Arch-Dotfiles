#!/usr/bin/env bats
# Booted allowlist flow (ADR 0149): an "always" answer lands in the
# root-owned store via sudo; `aur-vet export` merges it back into the repo
# allowlist for the operator to commit; `export --check` flags drift.

load ../lib/aur-vet

setup() {
  aurvet_setup
  REPO="$T/repo"; mkdir -p "$REPO"
  printf '# header\nold-pkg\tskip-checksum\tkeep\n' > "$REPO/allow.tsv"
  # A fake sudo that models privilege: the store dir is writable only while
  # it runs.
  mkdir -p "$T/bin"
  cat > "$T/bin/sudo" <<SH
#!/bin/sh
chmod u+w "$AUR_VET_STORE"; "\$@"; rc=\$?; chmod u-w "$AUR_VET_STORE"
exit \$rc
SH
  chmod +x "$T/bin/sudo"
}
teardown() { chmod -R u+w "$T" 2>/dev/null || true; aurvet_teardown; }

@test "store: an always-answer without sudo fails cleanly, writes nothing" {
  chmod u-w "$AUR_VET_STORE"
  AUR_VET_SUDO="$T/missing-sudo" \
    aurvet_hook_answer "$(aurvet_clone chaos-rat)" a
  [ "$status" -eq 2 ]
  [[ "$output" == *"allowlist not writable"* ]]
  [ ! -s "$AUR_VET_STORE/allow.tsv" ]
}

@test "store: with sudo an always-answer writes the root-owned store" {
  chmod u-w "$AUR_VET_STORE"
  AUR_VET_SUDO="$T/bin/sudo" \
    aurvet_hook_answer "$(aurvet_clone chaos-rat)" a
  [ "$status" -eq 0 ]
  grep -q $'^chaos-rat\tinstall-interp\t' "$AUR_VET_STORE/allow.tsv"
}

@test "export: store rows merge into the repo, comments and old rows stay" {
  printf 'chaos-rat\tinstall-interp\treviewed 2026-09-28\n' \
    > "$AUR_VET_STORE/allow.tsv"
  run "$AUR_VET_SRC/aur-vet" export "$REPO"
  [ "$status" -eq 0 ]
  head -1 "$REPO/allow.tsv" | grep -qx '# header'
  grep -qx $'old-pkg\tskip-checksum\tkeep' "$REPO/allow.tsv"
  grep -qx $'chaos-rat\tinstall-interp\treviewed 2026-09-28' "$REPO/allow.tsv"
}

@test "export: a row already in the repo is not duplicated" {
  printf 'old-pkg\tskip-checksum\tkeep\n' > "$AUR_VET_STORE/allow.tsv"
  run "$AUR_VET_SRC/aur-vet" export "$REPO"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^old-pkg' "$REPO/allow.tsv")" -eq 1 ]
}

@test "export --check reports drift and changes nothing" {
  printf 'new-pkg\ttoplevel-code\tr\n' > "$AUR_VET_STORE/allow.tsv"
  local before; before="$(cat "$REPO/allow.tsv")"
  run "$AUR_VET_SRC/aur-vet" export --check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"+ new-pkg"* ]]
  [ "$(cat "$REPO/allow.tsv")" = "$before" ]
}

@test "export --check passes when in sync" {
  printf 'old-pkg\tskip-checksum\tkeep\n' > "$AUR_VET_STORE/allow.tsv"
  run "$AUR_VET_SRC/aur-vet" export --check "$REPO"
  [ "$status" -eq 0 ]
}
