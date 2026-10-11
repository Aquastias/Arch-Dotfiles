# resolver-helpers.bash — shared setup for the resolver-*.bats parts
# Tests for .installer/lib/packages/package-resolver.sh — the Package Resolver.
#
# Pure JSON-in/TSV-out: every input is declarative, so the resolver needs no
# pacman query and no network. Assertions are external — given this Effective
# Config, these packages with these sources.

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/packages/package-resolver.sh"
}

# packages_of <config> [source] — the resolved package names, optionally one source.
packages_of() {
  if [[ -n "${2:-}" ]]; then
    package_resolver_resolve "$1" | awk -F'\t' -v s="$2" '$1 == s { print $3 }' | sort -u
  else
    package_resolver_resolve "$1" | awk -F'\t' '{ print $3 }' | sort -u
  fi
}
source_of() { package_resolver_resolve "$1" | awk -F'\t' -v p="$3" '$3 == p { print $1 }'; }

# only_in_second <lines> <lines> — how many lines of the second list are
# absent from the first.
only_in_second() {
  awk 'NR == FNR { seen[$0]; next } !($0 in seen) { count++ }
       END { print count + 0 }' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}

MIN='{"users":[],"options":{"kernel":["lts"]}}'

