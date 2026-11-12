# resolver-helpers.bash — shared setup for the resolver-*.bats parts
# Tests for .installer/lib/packages/package-resolver.sh — the Package Resolver.
#
# Pure JSON-in/TSV-out: every input is declarative, so the resolver needs no
# pacman query and no network. Assertions are external — given this Effective
# Config, these packages with these sources.

load ../lib/text-helpers

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
}

# packages_of <config> [source] — the resolved package names, optionally one
# source. Resolver rows are source<TAB>layer<TAB>package.
packages_of() {
  local source_name package _layer
  while IFS=$'\t' read -r source_name _layer package; do
    [[ -z "${2:-}" || "$source_name" == "$2" ]] && printf '%s\n' "$package"
  done < <(package_resolver_resolve "$1") | sort -u
}

# only_in_second <lines> <lines> — how many lines of the second list are
# absent from the first.
only_in_second() {
  local line count=0
  while IFS= read -r line; do
    text_has_line "$1" "$line" || count=$((count + 1))
  done < <(printf '%s\n' "$2")
  printf '%s\n' "$count"
}

MIN='{"users":[],"options":{"kernel":["lts"]}}'

