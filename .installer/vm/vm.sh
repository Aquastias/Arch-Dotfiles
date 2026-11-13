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
# INSTALLER_DIR (the data root holding hosts/, vm/profiles/, tests/vm/profiles/)
# is
# overridable for tests; the lib modules are always sourced from this script's
# own directory.
# =============================================================================

set -Eeuo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
INSTALLER_DIR="${INSTALLER_DIR:-$(cd "$SELF_DIR/.." && pwd)}"

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
  --local                 Install local HEAD (staged bare clone served to the
                          guest), not the pushed repo. Same as REPO_URL=local.
                          Uncommitted changes are not installed.
  --verify-aur            (test flow) Implies --verify-boot; the first-boot
                          sentinel also runs `aur-vet audit` (ADR 0143) and
                          a finding fails the run (plain boot verify only).
  --verify-boot           After a clean test install, power-cycle to the
                          installed disk and wait for the first-boot sentinel.
  --hold-on-fail          (test flow) On a FAILED cell, skip poweroff and give
                          ttyS0 a root autologin shell so the VM stays
                          inspectable over `virsh console`.
  --rescue                Re-attach the install ISO + access seed to an EXISTING
                          persistent VM and boot the live ISO, to inspect a
                          system that installed but won't boot (does not
                          reinstall). Ignores --testing/--guided.
  --print-config          Dry run: validate and print the resolved
                          install.jsonc to stdout, then exit.
  --help, -h              Show this help.

Profile hardware/timeouts are defaults; matching env vars (VM_RAM_MB,
VM_VCPUS, INSTALL_TIMEOUT_SEC, TIMEOUT_SEC, BOOT_TIMEOUT_SEC, ISO_URL_OVERRIDE,
INSTALL_HARD_TIMEOUT_SEC, REPO_URL) still win at run time.
INSTALL_TIMEOUT_SEC is a stall timeout: a still-growing install log keeps
the wait going, up to INSTALL_HARD_TIMEOUT_SEC (default 3x) in total.
USAGE
}

main() {
  local profile_reference="" testing=0 print_config=0 recreate=0
  local verify_boot=0 guided=0
  local hold_on_fail=0 rescue=0 verify_aur=0
  while (($#)); do
    case "$1" in
      --profile)      profile_reference="${2:-}"; shift 2 ;;
      # the reference after "--profile=" (10 characters)
      --profile=*)    profile_reference="${1:10}"; shift ;;
      --testing)      testing=1; shift ;;
      --guided)       guided=1; shift ;;
      --recreate)     recreate=1; shift ;;
      --local)        export REPO_URL=local; shift ;;
      --verify-boot)  verify_boot=1; shift ;;
      --verify-aur)   verify_aur=1; verify_boot=1; shift ;;
      --hold-on-fail) hold_on_fail=1; shift ;;
      --rescue)       rescue=1; shift ;;
      --print-config) print_config=1; shift ;;
      --help | -h)    usage; return 0 ;;
      *)              usage >&2; die "unknown argument '$1'" ;;
    esac
  done

  [[ -n "$profile_reference" ]] || { usage >&2; die "--profile is required"; }
  local profile_file
  profile_file="$(profile_file_path "$profile_reference" "$testing" "$guided")"
  [[ -f "$profile_file" ]] || die "profile not found: $profile_file"

  local hosts_directory="$INSTALLER_DIR/hosts"
  local profile_json
  # The profile, comments stripped (a parse error fails here).
  profile_json="$(jsonc_strip "$profile_file" | jq '.')" \
    || die "profile is not valid JSONC: $profile_file"

  profile_validate "$profile_json" "$hosts_directory" || exit 1

  if ((print_config)); then
    vm_profile_resolve_config "$profile_json"
    return 0
  fi

  map_profile_contract "$profile_json"
  map_verify_contract "$profile_json" "$verify_boot" "$verify_aur" \
    "$hold_on_fail"
  RECREATE=$( ((recreate)) && echo true || echo false )
  run_flow "$rescue" "$guided" "$testing"
}

# profile_file_path <reference> <testing> <guided> — --guided is a disposable
# test flow (like --testing) that drives the Guided Installer headlessly; it
# resolves profiles under tests/vm/profiles/ too. An absolute path to an
# existing profile file is used verbatim — the seam the Combination Matrix uses
# to run an ephemeral, tmpfs-materialized cell profile (matrix.sh emit) without
# staging it under the profiles tree (ADR 0046).
profile_file_path() {
  local profile_reference="$1" testing="$2" guided="$3" base
  if [[ "$profile_reference" == /* && -f "$profile_reference" ]]; then
    printf '%s\n' "$profile_reference"
    return 0
  fi
  if ((testing || guided)); then base="$INSTALLER_DIR/tests/vm/profiles"; else
    base="$INSTALLER_DIR/vm/profiles"; fi
  printf '%s\n' "$base/$profile_reference.jsonc"
}

# profile_field <profile-json> <filter> — one field of the profile, as text.
profile_field() {
  # The filter's value in the profile.
  printf '%s\n' "$1" | jq -r "$2"
}

# map_profile_contract <profile-json> — map the profile into the harness
# contract (env overrides win): VM shape, Install Config, fixtures, timeouts.
map_profile_contract() {
  local profile_json="$1"
  VM_NAME="$(profile_field "$profile_json" '.name')"
  # shellcheck disable=SC2034 # consumed by core.sh _core_vm_create via the flow
  mapfile -t VM_DISK_SIZES < <(profile_field "$profile_json" \
    '.hardware.disks[]')
  VM_RAM_MB="${VM_RAM_MB:-$(profile_field "$profile_json" '.hardware.ram_mb')}"
  VM_VCPUS="${VM_VCPUS:-$(profile_field "$profile_json" '.hardware.vcpus')}"
  INSTALL_CONFIG_CONTENT="$(vm_profile_resolve_config "$profile_json")"

  # Both consumed by core.sh _core_stage_fixture_files.
  # shellcheck disable=SC2034
  mapfile -t VM_FIXTURE_FILES < <(profile_field "$profile_json" '.fixtures[]?')
  # shellcheck disable=SC2034
  VM_SCRIPT_DIR="$INSTALLER_DIR/vm"

  # Timeouts: env > profile > flow default. An empty profile value leaves the
  # flow's own `: "${VAR:=default}"` to apply.
  local install_timeout
  install_timeout="$(profile_field "$profile_json" \
    '.timeouts.install // empty')"
  INSTALL_TIMEOUT_SEC="${INSTALL_TIMEOUT_SEC:-$install_timeout}"
  TIMEOUT_SEC="${TIMEOUT_SEC:-$install_timeout}"
  BOOT_TIMEOUT_SEC="${BOOT_TIMEOUT_SEC:-$(
    profile_field "$profile_json" '.timeouts.boot // empty')}"
}

# map_verify_contract <profile-json> <verify-boot> <verify-aur> <hold-on-fail>
# — the verify block (test flow): env > profile; flags force their checks.
map_verify_contract() {
  local profile_json="$1" verify_boot="$2" verify_aur="$3" hold_on_fail="$4"
  VERIFY_BOOT="${VERIFY_BOOT:-$(
    profile_field "$profile_json" '.verify.boot // false')}"
  ((verify_boot)) && VERIFY_BOOT=true
  # verify.aur_audit (ADR 0143): the booted VM audits itself; needs boot verify.
  VM_VERIFY_AUR_AUDIT="${VM_VERIFY_AUR_AUDIT:-$(
    profile_field "$profile_json" '.verify.aur_audit // false')}"
  ((verify_aur)) && VM_VERIFY_AUR_AUDIT=true
  [[ "$VM_VERIFY_AUR_AUDIT" == true ]] && VERIFY_BOOT=true
  DIRTY_CACHE="${DIRTY_CACHE:-$(
    profile_field "$profile_json" '.verify.dirty_cache // false')}"
  # Hold-on-fail (ADR 0099): env > profile > flag. When on, a failed test
  # cell is left running with a serial autologin shell instead of powering
  # off.
  HOLD_ON_FAIL="${HOLD_ON_FAIL:-$(
    profile_field "$profile_json" '.verify.hold_on_fail // false')}"
  ((hold_on_fail)) && HOLD_ON_FAIL=true
  VM_VERIFY_BYID="${VM_VERIFY_BYID:-$(
    profile_field "$profile_json" '.verify.by_id // false')}"
  VM_REORDER_BOOT_DISKS="${VM_REORDER_BOOT_DISKS:-$(
    profile_field "$profile_json" '.verify.reorder_boot_disks // false')}"
  mapfile -t VM_VERIFY_POOLS < <(profile_field "$profile_json" \
    '.verify.pools[]?')
  mapfile -t VM_VERIFY_MOUNTS < <(profile_field "$profile_json" \
    '.verify.mounts[]?')
  mapfile -t VM_VERIFY_OWNED < <(profile_field "$profile_json" \
    '.verify.owned[]?')
  mapfile -t VM_VERIFY_FS_MOUNTS < <(profile_field "$profile_json" \
    '.verify.fs_mounts[]?')
  # Per-desktop session verification (ADR 0062): each name here has its
  # session-launch artifacts asserted on the booted system (===<TAG>-OK===).
  mapfile -t VM_VERIFY_DESKTOPS < <(profile_field "$profile_json" \
    '.verify.desktops[]?')
  map_session_contract "$profile_json"
}

# map_session_contract <profile-json> — the Display Manager, session logins,
# virtual GPU and rollback checks of the verify block.
map_session_contract() {
  local profile_json="$1"
  local session_user='.verify.session_user'
  session_user+=' // (.install.users[0]? // "aquastias")'
  # `install` may be the string "repo" (install the repo default host profile)
  # rather than an inline object, so the index is guarded — indexing a string
  # aborts jq (exit 5) and, under set -e, the whole harness.
  local root_filesystem='if (.install | type) == "object"'
  root_filesystem+=' then (.install.filesystem // "zfs") else "zfs" end'
  # Display Manager (ADR 0069/0091): the systemd service boot-verify checks for
  # the greeter, resolved as the installer does (see the .jq file).
  VM_VERIFY_DM="$(printf '%s\n' "$profile_json" \
    | jq -r -f "$SELF_DIR/lib/verify-display-manager.jq")"
  [[ "$VM_VERIFY_DM" == "none" ]] && VM_VERIFY_DM=""
  # Per-desktop LOGIN verification (ADR 0062): each name here is actually logged
  # into (SDDM Autologin, one per boot) and its compositor confirmed up
  # (===<TAG>-SESSION-OK===). Needs a GPU (below) and a login user.
  mapfile -t VM_VERIFY_SESSIONS < <(profile_field "$profile_json" \
    '.verify.sessions[]?')
  VM_SESSION_USER="${VM_SESSION_USER:-$(
    profile_field "$profile_json" "$session_user")}"
  # A virtual GPU (virtio-gpu + virgl, headless) — required for a real Wayland
  # session to start. Implied by verify.sessions, else the profile's
  # hardware.gpu.
  if ((${#VM_VERIFY_SESSIONS[@]})); then
    VM_GPU=true
  else
    VM_GPU="${VM_GPU:-$(
      profile_field "$profile_json" '.hardware.gpu // false')}"
  fi
  VM_VERIFY_RESILIENCE="${VM_VERIFY_RESILIENCE:-$(
    profile_field "$profile_json" '.verify.resilience // false')}"
  VM_VERIFY_ROLLBACK="${VM_VERIFY_ROLLBACK:-$(
    profile_field "$profile_json" '.verify.rollback // false')}"
  # The rollback proof's mechanics follow the root filesystem (zfs datasets vs
  # btrfs subvols, ADR 0044); derived from the config so a btrfs impermanence
  # profile needs no env override.
  VM_ROLLBACK_FS="${VM_ROLLBACK_FS:-$(
    profile_field "$profile_json" "$root_filesystem")}"
}

# run_flow <rescue> <guided> <testing> — dispatch to the selected flow (each
# guard-sources core.sh).
run_flow() {
  local rescue="$1" guided="$2" testing="$3"
  # --rescue is a persistent-flow-only operation on an existing VM: re-attach
  # the ISO + seed and boot the live env to inspect a broken install
  # (ADR 0099).
  if ((rescue)); then
    # shellcheck source=lib/flow-persistent.sh
    source "$SELF_DIR/lib/flow-persistent.sh"
    vm_flow_persistent_rescue
    return
  fi
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
