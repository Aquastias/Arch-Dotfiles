# bats `load` helper for the aur-vet suites (ADR 0143). Builds fixture AUR
# clones as real git repos — the shape paru hands PreBuildCommand — and runs
# the real command against an isolated data dir and pin store.

AUR_VET_SRC="$BATS_TEST_DIRNAME/../../aur"
AUR_VET_FIXTURES="$BATS_TEST_DIRNAME/../fixtures/aur"

aurvet_setup() {
  T="$(mktemp -d)"
  export AUR_VET_DATA="$T/data" AUR_VET_STORE="$T/store"
  mkdir -p "$AUR_VET_DATA" "$AUR_VET_STORE"
  cp "$AUR_VET_SRC"/*.tsv "$AUR_VET_DATA/"
  # An empty store: fixtures opt into pins explicitly.
  : > "$AUR_VET_STORE/vetted.tsv"; : > "$AUR_VET_STORE/allow.tsv"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
}

aurvet_teardown() { rm -rf "$T"; }

# Copy fixture <name> into a fresh git clone at $T/clone/<name>; commit it as
# <author> (default fixture-maintainer). Prints the clone dir.
aurvet_clone() {
  local name="$1" author="${2:-fixture-maintainer}" dir="$T/clone/$1"
  mkdir -p "$dir"
  cp -r "$AUR_VET_FIXTURES/$name/." "$dir/"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name="$author" -c user.email="$author@aur" \
    commit -q -m "init"
  printf '%s\n' "$dir"
}

# Run the hook the way paru does: cwd = clone, $PKGBASE set.
aurvet_hook() {
  local dir="$1"
  run bash -c 'cd "$1" && PKGBASE="$2" "$3"' _ \
    "$dir" "${2:-$(basename "$dir")}" \
    "$AUR_VET_SRC/aur-vet"
}

# Inject <text> into a fresh copy of the rulecase fixture per <placement> (see
# fixtures/aur/rule-cases.tsv), commit, and print the clone dir. Text goes via
# ENVIRON so awk never interprets its backslashes.
aurvet_case() {
  local placement="$1" text="$2" dir="$T/clone/${3:-case}"
  text="${text//@BLOB@/$(printf 'QUJD%.0s' {1..30})}"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -r "$AUR_VET_FIXTURES/rulecase/." "$dir/"
  local pb="$dir/PKGBUILD" si="$dir/.SRCINFO" sum
  _aurvet_ins() { # <file> <after-ERE> <line>: insert after first match
    L="$3" awk -v re="$2" \
      '{ print } !d && $0 ~ re { print ENVIRON["L"]; d = 1 }' \
      "$1" > "$1.new" && mv "$1.new" "$1"
  }
  case "$placement" in
    build) _aurvet_ins "$pb" '^  make$' "  $text" ;;
    install)
      _aurvet_ins "$pb" '^license=' 'install=rulecase.install'
      printf 'post_install() {\n  %s\n}\n' "$text" > "$dir/rulecase.install" ;;
    top) _aurvet_ins "$pb" '^license=' "$text" ;;
    file) printf '#!/bin/sh\n%s\n' "$text" > "$dir/helper.sh" ;;
    source | source-skip)
      sum=3333333333333333333333333333333333333333333333333333333333333333
      [[ "$placement" == source-skip ]] && sum=SKIP
      _aurvet_ins "$pb" '^source=' "source+=(\"$text\")"
      _aurvet_ins "$pb" '^sha256sums=' "sha256sums+=('$sum')"
      _aurvet_ins "$si" '^\tsource = ' "	source = $text"
      _aurvet_ins "$si" '^\tsha256sums = ' "	sha256sums = $sum" ;;
    nosrcinfo) rm -f "$si" ;;
    pkgbase) ;;
    *) echo "unknown placement: $placement" >&2; return 1 ;;
  esac
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=m -c user.email=m@aur commit -q -m case
  printf '%s\n' "$dir"
}
