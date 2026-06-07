#!/usr/bin/env bash
# =============================================================================
# vm/vm.sh — profile-driven VM Harness entry point
# =============================================================================
# Provisions one libvirt VM from a VM Profile:
#     vm.sh --profile <category>/<name> [--testing] [--print-config]
#
# --profile resolves against vm/profiles/ by default, or tests/vm/profiles/
# under --testing. --print-config is a dry run: validate the profile and emit
# the resolved install.jsonc to stdout (no libvirt). The persistent and test
# provisioning flows land in later slices.
#
# OS_DIR (the data root holding hosts/, vm/profiles/, tests/vm/profiles/,
# install.jsonc) is overridable for tests; the lib modules are always sourced
# from this script's own directory.
# =============================================================================

set -Eeuo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
OS_DIR="${OS_DIR:-$(cd "$SELF_DIR/.." && pwd)}"

# shellcheck source=lib/profile.sh
source "$SELF_DIR/lib/profile.sh"
# shellcheck source=lib/profile-validate.sh
source "$SELF_DIR/lib/profile-validate.sh"

die() { echo "vm.sh: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Usage: vm.sh --profile <category>/<name> [options]

Options:
  --profile <cat>/<name>  VM Profile to provision (required).
  --testing               Use the disposable test flow; resolve the profile
                          under tests/vm/profiles/ instead of vm/profiles/.
  --print-config          Dry run: validate and print the resolved
                          install.jsonc to stdout, then exit.
  --help, -h              Show this help.
USAGE
}

main() {
  local profile_ref="" testing=0 print_config=0
  while (($#)); do
    case "$1" in
      --profile)      profile_ref="${2:-}"; shift 2 ;;
      --profile=*)    profile_ref="${1#*=}"; shift ;;
      --testing)      testing=1; shift ;;
      --print-config) print_config=1; shift ;;
      --help | -h)    usage; return 0 ;;
      *)              usage >&2; die "unknown argument '$1'" ;;
    esac
  done

  [[ -n "$profile_ref" ]] || { usage >&2; die "--profile is required"; }

  local base
  if ((testing)); then base="$OS_DIR/tests/vm/profiles"; else
    base="$OS_DIR/vm/profiles"; fi
  local profile_file="$base/$profile_ref.jsonc"
  [[ -f "$profile_file" ]] || die "profile not found: $profile_file"

  local hosts_dir="$OS_DIR/hosts" repo_config="$OS_DIR/install.jsonc"
  local profile_json
  profile_json="$(jsonc_strip "$profile_file" | jq '.')" \
    || die "profile is not valid JSONC: $profile_file"

  profile_validate "$profile_json" "$hosts_dir" || exit 1

  if ((print_config)); then
    profile_resolve_config "$profile_json" "$hosts_dir" "$repo_config"
    return 0
  fi

  die "provisioning flows are not wired yet (see issues 02/03);" \
      "use --print-config for now"
}

main "$@"
