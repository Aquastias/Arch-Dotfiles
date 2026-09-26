#!/usr/bin/env bats
# Indicator store (ADR 0143): every row traceable to a source and campaign,
# refresh is an explicit reviewed step, and vetting never goes online for it.

load ../lib/aur-vet

setup() { aurvet_setup; }
teardown() { aurvet_teardown; }

@test "indicators: every row has a known kind, campaign and source" {
  local bad
  bad="$(awk -F'\t' '
    FILENAME ~ /sources/ {
      if (!/^#/ && !/^\t/ && NF) { k = $1; sub(/\\$/, "", k); src[k] }
      next
    }
    FILENAME ~ /campaigns/ { if (!/^#/ && NF) camp[$1]; next }
    /^#/ || !NF { next }
    /\\$/ { held = substr($0, 1, length($0) - 1); next }
    { r = held; sub(/^\t/, "", $0); r = r $0; held = "" }
    { n = split(r, c, "\t")
      if (c[1] !~ /^(pkgbase|npm|domain|sha256|path)$/ || !(c[3] in camp) \
          || !(c[4] in src) || n != 4) print r }' \
    "$AUR_VET_SRC/sources.tsv" "$AUR_VET_SRC/campaigns.tsv" \
    "$AUR_VET_SRC/indicators.tsv")"
  [[ -z "$bad" ]] || { echo "untraceable rows:"; echo "$bad"; return 1; }
}

@test "indicators: a missing data file fails closed (exit 2)" {
  rm "$AUR_VET_DATA/indicators.tsv"
  aurvet_hook "$(aurvet_clone atomic-arch)"
  [ "$status" -eq 2 ]
}

@test "indicators: vetting never fetches (no curl at hook time)" {
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho curl >> "%s/called"\nexit 1\n' "$T" > "$T/bin/curl"
  chmod +x "$T/bin/curl"
  PATH="$T/bin:$PATH" aurvet_hook "$(aurvet_clone electron-benign)"
  [ ! -e "$T/called" ]
}

_refresh() {
  AUR_VET_ARCH_LIST_URL="file://$AUR_VET_FIXTURES/refresh/arch-list.md" \
  AUR_VET_NPM_LIST_URL="file://$AUR_VET_FIXTURES/refresh/npm-packages.txt" \
    run "$AUR_VET_SRC/aur-vet" refresh-indicators
}

@test "refresh: appends new names tagged with their source, keeps the rest" {
  local before; before="$(wc -l < "$AUR_VET_DATA/indicators.tsv")"
  _refresh
  [ "$status" -eq 0 ]
  grep -qx $'pkgbase\tnew-evil-pkg\tatomic-arch\tarch-md' \
    "$AUR_VET_DATA/indicators.tsv"
  grep -qx $'npm\tfresh-npm-payload\tatomic-arch\tlenucksi' \
    "$AUR_VET_DATA/indicators.tsv"
  [ "$(wc -l < "$AUR_VET_DATA/indicators.tsv")" -eq $((before + 2)) ]
  [[ "$output" == *"added 2"* ]]
}

@test "refresh: drops names outside the AUR charset and is idempotent" {
  _refresh
  ! grep -q 'bad' "$AUR_VET_DATA/indicators.tsv"
  _refresh
  [[ "$output" == *"added 0"* ]]
}

@test "refresh: a failed download changes nothing and exits non-zero" {
  cp "$AUR_VET_DATA/indicators.tsv" "$T/before"
  AUR_VET_ARCH_LIST_URL="file://$T/missing" \
  AUR_VET_NPM_LIST_URL="file://$T/missing" \
    run "$AUR_VET_SRC/aur-vet" refresh-indicators
  [ "$status" -ne 0 ]
  cmp -s "$T/before" "$AUR_VET_DATA/indicators.tsv"
}

@test "data: no record continues with a TAB before the backslash" {
  # `value<TAB>\` + a two-TAB continuation would yield an empty field.
  run grep -nP '\t\\$' "$AUR_VET_SRC"/*.tsv
  [ "$status" -eq 1 ]
}
