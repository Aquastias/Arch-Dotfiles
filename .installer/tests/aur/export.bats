#!/usr/bin/env bats
# Booted pin flow (ADR 0143): the root-owned store takes accepts via sudo;
# `aur-vet export` merges it back into the repo pin files for the operator to
# commit; `export --check` flags drift between the two.

load ../lib/aur-vet

setup() {
  aurvet_setup
  REPO="$T/repo"; mkdir -p "$REPO"
  printf '# header\nold-pkg\tc0\tm\t2026-01-01\tkeep\n' > "$REPO/vetted.tsv"
  printf '# header\n' > "$REPO/allow.tsv"
  # A fake sudo that models privilege: the store dir is writable only while
  # it runs.
  mkdir -p "$T/bin"
  cat > "$T/bin/sudo" <<SH
#!/bin/sh
[ "\$1" = -n ] && shift
chmod u+w "$AUR_VET_STORE"; "\$@"; rc=\$?; chmod u-w "$AUR_VET_STORE"
exit \$rc
SH
  chmod +x "$T/bin/sudo"
}
teardown() { chmod -R u+w "$T" 2>/dev/null || true; aurvet_teardown; }

@test "store: an accept without sudo fails cleanly and writes nothing" {
  chmod u-w "$AUR_VET_STORE"
  AUR_VET_SUDO="$T/missing-sudo" \
    aurvet_hook_answer "$(aurvet_clone electron-benign)" y
  [ "$status" -eq 2 ]
  [[ "$output" == *"pin store not writable"* ]]
  [ ! -s "$AUR_VET_STORE/vetted.tsv" ]
}

@test "store: with sudo an accept writes the root-owned store" {
  chmod u-w "$AUR_VET_STORE"
  AUR_VET_SUDO="$T/bin/sudo" \
    aurvet_hook_answer "$(aurvet_clone electron-benign)" y
  [ "$status" -eq 0 ]
  grep -q '^electron-benign' "$AUR_VET_STORE/vetted.tsv"
}

@test "export: merges store rows into the repo, keeping its comments" {
  printf 'electron-benign\tc1\tm\t2026-09-01\treviewed\n' \
    > "$AUR_VET_STORE/vetted.tsv"
  printf 'electron-benign\tc1\tsource-owner\treviewed\n' \
    > "$AUR_VET_STORE/allow.tsv"
  run "$AUR_VET_SRC/aur-vet" export "$REPO"
  [ "$status" -eq 0 ]
  head -1 "$REPO/vetted.tsv" | grep -qx '# header'
  grep -qx $'old-pkg\tc0\tm\t2026-01-01\tkeep' "$REPO/vetted.tsv"
  grep -qx $'electron-benign\tc1\tm\t2026-09-01\treviewed' "$REPO/vetted.tsv"
  grep -qx $'electron-benign\tc1\tsource-owner\treviewed' "$REPO/allow.tsv"
  [[ "$output" == *"+ electron-benign"* ]]
}

@test "export: a changed pin replaces the repo row, not duplicates it" {
  printf 'old-pkg\tc9\tm\t2026-09-01\tbump-only\n' > "$AUR_VET_STORE/vetted.tsv"
  run "$AUR_VET_SRC/aur-vet" export "$REPO"
  [ "$(grep -c '^old-pkg' "$REPO/vetted.tsv")" -eq 1 ]
  grep -q $'^old-pkg\tc9' "$REPO/vetted.tsv"
}

@test "export --check: drift fails, a synced store passes" {
  printf 'electron-benign\tc1\tm\t2026-09-01\treviewed\n' \
    > "$AUR_VET_STORE/vetted.tsv"
  run "$AUR_VET_SRC/aur-vet" export --check "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift"* ]]
  run "$AUR_VET_SRC/aur-vet" export "$REPO"
  run "$AUR_VET_SRC/aur-vet" export --check "$REPO"
  [ "$status" -eq 0 ]
}
