#!/usr/bin/env bats
# tools/aur-trust.sh — the reviewed fast path for a trust-adopted package
# (ADR 0149): show the takeover (server-side RPC), the commits and diff since
# the newest author took over and whether sources/checksums/install scripts
# changed, then on an explicit "y" add the allowlist row. Fixture AUR repos
# and RPC answers; never the network.

load ../lib/aur-vet

setup() {
  aur_vet_setup
  TOOL="$BATS_TEST_DIRNAME/../../tools/aur-trust.sh"
  export AUR_TRUST_GIT_URL="$T/remote" AUR_TRUST_ALLOW="$T/allow.tsv"
  printf '# allowlist\n' > "$AUR_TRUST_ALLOW"
}
teardown() { aur_vet_teardown; }

_days_ago() { echo $(($(date +%s) - $1 * 86400)); }

# _commit_package <base> <source> <author> [line] — commit a PKGBUILD (+ an extra line)
# and .SRCINFO to the fixture AUR repo for <base> as <author>.
_commit_package() {
  local repo="$T/remote/$1.git"
  [[ -d "$repo" ]] || git init -q "$repo"
  printf 'pkgname=%s\npkgver=1.0\nsource=("%s")\n%s\n' "$1" "$2" "${4:-}" \
    > "$repo/PKGBUILD"
  printf 'pkgbase = %s\n\tsource = %s\n\tb2sums = abc123\n' "$1" "$2" \
    > "$repo/.SRCINFO"
  git -C "$repo" add -A
  git -C "$repo" -c user.name="$3" -c user.email="$3@aur" \
    commit -q --allow-empty -m "update by $3"
}

# _adopted <base> — RPC: <base> adopted by "newbie" from "oldie" 2 days ago.
_adopted() {
  aur_vet_rpc "$1" Maintainer='"newbie"' Submitter='"oldie"' \
    LastModified="$(_days_ago 2)"
}

@test "an adoption with unchanged sources: y writes a reviewed row" {
  _commit_package foo https://example.org/foo-1.0.tar.gz oldie
  _commit_package foo https://example.org/foo-1.0.tar.gz newbie "# restyle"
  _adopted foo
  run bash -c 'printf "y\n\n" | "$1" foo' _ "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"oldie -> newbie"* ]]
  [[ "$output" == *"sources, checksums, install: unchanged"* ]]
  [[ "$output" == *"+# restyle"* ]]                 # the diff is shown
  local row='^foo\ttrust-adopted\treviewed \d{4}-\d\d-\d\d '
  row+='\(newbie adopted from oldie; [0-9a-f]{7,} sources\+sums unchanged\)$'
  grep -qP "$row" \
    "$AUR_TRUST_ALLOW"
}

@test "a changed source is flagged, and the default note says so" {
  _commit_package bar https://example.org/bar-1.0.tar.gz oldie
  _commit_package bar https://evil.example/bar-1.0.tar.gz newbie
  _adopted bar
  run bash -c 'printf "y\n\n" | "$1" bar' _ "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CHANGED"*"evil.example"* ]]
  grep -qF 'SOURCES CHANGED' "$AUR_TRUST_ALLOW"
}

@test "a typed note replaces the default" {
  _commit_package baz https://example.org/baz.tar.gz oldie
  _commit_package baz https://example.org/baz.tar.gz newbie
  _adopted baz
  run bash -c 'printf "y\nchecked upstream\n" | "$1" baz' _ "$TOOL"
  [ "$status" -eq 0 ]
  grep -qF 'newbie adopted from oldie; checked upstream)' "$AUR_TRUST_ALLOW"
}

@test "no, or no answer at all, writes nothing" {
  _commit_package foo https://example.org/foo.tar.gz oldie
  _commit_package foo https://example.org/foo.tar.gz newbie
  _adopted foo
  run bash -c 'printf "n\n" | "$1" foo' _ "$TOOL"
  [ "$status" -eq 1 ]
  run bash -c '"$1" foo < /dev/null' _ "$TOOL"
  [ "$status" -eq 1 ]
  ! grep -q '^foo' "$AUR_TRUST_ALLOW"
}

@test "a package that did not change hands has nothing to trust" {
  _commit_package foo https://example.org/foo.tar.gz oldie
  aur_vet_rpc foo Maintainer='"oldie"' Submitter='"oldie"'
  run bash -c 'printf "y\n\n" | "$1" foo' _ "$TOOL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not adopted"* ]]
  ! grep -q '^foo' "$AUR_TRUST_ALLOW"
}

@test "an already-trusted package is left alone" {
  _commit_package foo https://example.org/foo.tar.gz oldie
  _commit_package foo https://example.org/foo.tar.gz newbie
  _adopted foo
  printf 'foo\ttrust-adopted\treviewed earlier\n' >> "$AUR_TRUST_ALLOW"
  run bash -c 'printf "y\n\n" | "$1" foo' _ "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already trusted"* ]]
  [ "$(grep -c '^foo' "$AUR_TRUST_ALLOW")" -eq 1 ]
}

@test "a name that is not an AUR package base is refused" {
  run "$TOOL" '../etc'
  [ "$status" -eq 2 ]
  run "$TOOL"
  [ "$status" -eq 2 ]
}
