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
# OS_DIR (the data root holding hosts/, vm/profiles/, tests/vm/profiles/) is
# overridable for tests; the lib modules are always sourced from this script's
# own directory.
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
  --testing               Use the disposable test flow (headless, serial
                          capture, sentinel/exit-code, boot-verify); resolve
                          the profile under tests/vm/profiles/ instead of
                          vm/profiles/. Default is the persistent flow.
  --guided                Like --testing, but drive the Guided Installer
                          headlessly (install.sh --guided): the guest resolves
                          the disk in-guest and replays the menu answers.
  --recreate              Destroy and undefine the existing VM first.
  --verify-boot           After a clean test install, power-cycle to the
                          installed disk and wait for the first-boot sentinel.
  --print-config          Dry run: validate and print the resolved
                          install.jsonc to stdout, then exit.
  --help, -h              Show this help.

Profile hardware/timeouts are defaults; matching env vars (VM_RAM_MB,
VM_VCPUS, INSTALL_TIMEOUT_SEC, TIMEOUT_SEC, BOOT_TIMEOUT_SEC, ISO_URL_OVERRIDE)
still win at run time.
USAGE
}

main() {
  local profile_ref="" testing=0 print_config=0 recreate=0 verify_boot=0 guided=0
  while (($#)); do
    case "$1" in
      --profile)      profile_ref="${2:-}"; shift 2 ;;
      --profile=*)    profile_ref="${1#*=}"; shift ;;
      --testing)      testing=1; shift ;;
      --guided)       guided=1; shift ;;
      --recreate)     recreate=1; shift ;;
      --verify-boot)  verify_boot=1; shift ;;
      --print-config) print_config=1; shift ;;
      --help | -h)    usage; return 0 ;;
      *)              usage >&2; die "unknown argument '$1'" ;;
    esac
  done

  [[ -n "$profile_ref" ]] || { usage >&2; die "--profile is required"; }

  # --guided is a disposable test flow (like --testing) that drives the Guided
  # Installer headlessly; it resolves profiles under tests/vm/profiles/ too.
  local base
  if ((testing || guided)); then base="$OS_DIR/tests/vm/profiles"; else
    base="$OS_DIR/vm/profiles"; fi
  local profile_file="$base/$profile_ref.jsonc"
  [[ -f "$profile_file" ]] || die "profile not found: $profile_file"

  local hosts_dir="$OS_DIR/hosts"
  local profile_json
  profile_json="$(jsonc_strip "$profile_file" | jq '.')" \
    || die "profile is not valid JSONC: $profile_file"

  profile_validate "$profile_json" "$hosts_dir" || exit 1

  if ((print_config)); then
    profile_resolve_config "$profile_json"
    return 0
  fi

  # ── Map the profile into the harness contract (env overrides win) ───────────
  VM_NAME="$(jq -r '.name' <<<"$profile_json")"
  # shellcheck disable=SC2034 # consumed by core.sh _vm_create via the flow
  mapfile -t VM_DISK_SIZES < <(jq -r '.hardware.disks[]' <<<"$profile_json")
  VM_RAM_MB="${VM_RAM_MB:-$(jq -r '.hardware.ram_mb' <<<"$profile_json")}"
  VM_VCPUS="${VM_VCPUS:-$(jq -r '.hardware.vcpus' <<<"$profile_json")}"
  INSTALL_CONFIG_CONTENT="$(profile_resolve_config "$profile_json")"

  # shellcheck disable=SC2034 # both consumed by core.sh _stage_fixture_files
  mapfile -t VM_FIXTURE_FILES < <(jq -r '.fixtures[]?' <<<"$profile_json")
  # shellcheck disable=SC2034
  VM_SCRIPT_DIR="$OS_DIR/vm"

  # Timeouts: env > profile > flow default. An empty profile value leaves the
  # flow's own `: "${VAR:=default}"` to apply.
  INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-$(jq -r '.timeouts.install // empty' <<<"$profile_json")}"
  TIMEOUT_SEC="${TIMEOUT_SEC:-$(jq -r '.timeouts.install // empty' <<<"$profile_json")}"
  BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-$(jq -r '.timeouts.boot // empty' <<<"$profile_json")}"

  # Verify block (test flow): env > profile; --verify-boot forces boot verify.
  VERIFY_BOOT="${VERIFY_BOOT:-$(jq -r '.verify.boot // false' <<<"$profile_json")}"
  ((verify_boot)) && VERIFY_BOOT=true
  DIRTY_CACHE="${DIRTY_CACHE:-$(jq -r '.verify.dirty_cache // false' <<<"$profile_json")}"
  VM_VERIFY_BYID="${VM_VERIFY_BYID:-$(jq -r '.verify.by_id // false' <<<"$profile_json")}"
  VM_REORDER_BOOT_DISKS="${VM_REORDER_BOOT_DISKS:-$(jq -r '.verify.reorder_boot_disks // false' <<<"$profile_json")}"
  mapfile -t VM_VERIFY_POOLS  < <(jq -r '.verify.pools[]?'  <<<"$profile_json")
  mapfile -t VM_VERIFY_MOUNTS < <(jq -r '.verify.mounts[]?' <<<"$profile_json")
  mapfile -t VM_VERIFY_OWNED  < <(jq -r '.verify.owned[]?'  <<<"$profile_json")
  mapfile -t VM_VERIFY_FS_MOUNTS < <(jq -r '.verify.fs_mounts[]?' <<<"$profile_json")
  VM_VERIFY_RESILIENCE="${VM_VERIFY_RESILIENCE:-$(jq -r '.verify.resilience // false' <<<"$profile_json")}"

  RECREATE=$( ((recreate)) && echo true || echo false )

  # ── Dispatch to the selected flow (each guard-sources core.sh) ──────────────
  if ((guided)); then
    # shellcheck source=lib/flow-guided.sh
    source "$SELF_DIR/lib/flow-guided.sh"
  elif ((testing)); then
    # shellcheck source=lib/flow-test.sh
    source "$SELF_DIR/lib/flow-test.sh"
  else
    # shellcheck source=lib/flow-persistent.sh
    source "$SELF_DIR/lib/flow-persistent.sh"
  fi
  flow_run
}

main "$@"
