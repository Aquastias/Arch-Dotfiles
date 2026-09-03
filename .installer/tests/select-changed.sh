#!/usr/bin/env bash
# =============================================================================
# tests/select-changed.sh — pure change→test-target selection (ADR 0103)
# =============================================================================
# Sourced by run.sh (--changed) and by run-changed.bats. PURE: no git, no bats,
# no filesystem walk. Input is a list of repo-relative changed paths; output on
# stdout is EITHER the single token `--full` (widen the run) OR a newline list
# of test TARGET TOKENS. A token is either a tests/ subdir name (`config`) or a
# tests/-relative `.bats` file (`finalize.bats`, `chroot/fstab-lint.bats`); the
# runner expands dir tokens to files and runs the union.
#
# Rules, in order (ADR 0103): a Broad-Blast Path or any UNMAPPED path widens to
# `--full` (fail-safe); a mirrored source dir maps to its tests/ subdir; a
# root/tools/ script maps via the explicit table; a changed test file maps to
# itself. The result always unions the Install-Correctness Core (the --fast set).
# =============================================================================

[[ -n "${_SELECT_CHANGED_SOURCED:-}" ]] && return 0
_SELECT_CHANGED_SOURCED=1

# Install-Correctness Core tokens — the --fast set (must mirror run.sh's
# collect_fast: config/layout/zfs/wipe dirs + the validator tier + FAST_ROOT).
# Always unioned into a targeted run so no change skips the catalogued guards.
_FAST_CORE_TOKENS=(
  config layout zfs wipe
  chroot/mount-unit-validate.bats chroot/initcpio-validate.bats
  chroot/fstab-lint.bats chroot/chroot-impermanence.bats
  profiles/user-units-validate.bats impermanence-common.bats
  lib/validators.bats sops.bats
  live-medium.bats wipe-probe.bats wipe-live-medium.bats
  wipe-prior-install-state.bats commons-part-name.bats
)

# Source subdirs mirrored 1:1 onto a tests/ subdir (tests/<name>/).
_MIRRORED_DIRS='boot chroot config layout matrix packages profiles shell wipe zfs extras vm'

# Broad-Blast Paths: a change here can affect ~any test — widen to --full.
_changed_is_broad_blast() {
  case "$1" in
    .installer/lib/common.sh) return 0 ;;
    .installer/lib/install-state.sh) return 0 ;;
    .installer/lib/config/accessors.sh) return 0 ;;
    .installer/lib/config/generator.sh) return 0 ;;
    .installer/lib/config/categorized-list.sh) return 0 ;;
    .installer/lib/config/store.sh) return 0 ;;
    .installer/tests/fixtures/*) return 0 ;;
    .installer/tests/run.sh) return 0 ;;
    .installer/tests/select-changed.sh) return 0 ;;
    *) return 1 ;;
  esac
}

# Explicit map for root-level tests (source files with no mirrored test dir).
# Prints space-separated target tokens, or nothing (caller treats as unmapped).
_changed_root_map() {
  case "$1" in
    .installer/lib/finalize.sh)            echo "finalize.bats" ;;
    .installer/lib/grub-common.sh)         echo "grub-common.bats" ;;
    .installer/lib/impermanence-common.sh) echo "impermanence-common.bats" ;;
    .installer/lib/jsonc.sh)               echo "jsonc.bats" ;;
    .installer/lib/live-medium.sh)         echo "live-medium.bats wipe-live-medium.bats" ;;
    .installer/lib/picker.sh)              echo "picker.bats picker-assign.bats" ;;
    .installer/lib/preflight.sh)           echo "preflight.bats" ;;
    .installer/lib/secrets.sh)             echo "secrets.bats" ;;
    .installer/lib/validators.sh)          echo "lib/validators.bats" ;;
    .installer/lib/aur-helper.sh)
      echo "install-pkglist.bats pkglist-profile.bats profiles/profiles-aur.bats \
            profiles/profiles-bootstrap.bats profiles/profiles-helper.bats" ;;
    .installer/tools/explain-packages.sh)  echo "explain-packages.bats" ;;
    .installer/tools/fetch-iso.sh)         echo "fetch-iso.bats" ;;
    .installer/tools/harden-boot.sh)       echo "harden-boot.bats" ;;
    .installer/tools/impermanence.sh)      echo "impermanence-tool.bats" ;;
    .installer/tools/install-pkglist.sh)   echo "install-pkglist.bats pkglist-profile.bats" ;;
    .installer/tools/save-pkglist.sh)      echo "pkglist-profile.bats" ;;
    .installer/02-wipe.sh)
      echo "wipe-live-medium.bats wipe-prior-install-state.bats \
            wipe-probe.bats wipe-select.bats" ;;
    .installer/programs/security/sops*)    echo "sops.bats" ;;
    *) return 1 ;;
  esac
}

# _changed_map_one <path> — print target tokens for one changed path, or return
# non-zero if unmapped (caller then widens to --full).
_changed_map_one() {
  local p="${1#./}" d
  # A changed test file targets itself (path relative to tests/).
  case "$p" in
    .installer/tests/*.bats) printf '%s\n' "${p#.installer/tests/}"; return 0 ;;
  esac
  # Mirrored source subdir: .installer/lib/<d>/… or .installer/<d>/… → tests/<d>.
  for d in $_MIRRORED_DIRS; do
    case "$p" in
      .installer/lib/"$d"/*|.installer/"$d"/*) printf '%s\n' "$d"; return 0 ;;
    esac
  done
  # Root/tools explicit map.
  local tokens; if tokens="$(_changed_root_map "$p")"; then
    printf '%s\n' $tokens; return 0
  fi
  return 1
}

# select_changed_targets <changed-path>... — print `--full` or the sorted-unique
# union of change-derived targets and the Install-Correctness Core.
select_changed_targets() {
  local p tok; local -A want=()
  for p in "$@"; do
    p="${p#./}"
    [[ -n "$p" ]] || continue
    # Only .installer/ paths are test-relevant. Anything else (repo-root
    # dotfiles, docs/, .scratch/, editor dirs — often untracked) is ignored,
    # NOT treated as unmapped, so it never forces a full run.
    [[ "$p" == .installer/* ]] || continue
    if _changed_is_broad_blast "$p"; then echo "--full"; return 0; fi
    local mapped; if mapped="$(_changed_map_one "$p")"; then
      for tok in $mapped; do want[$tok]=1; done
    else
      echo "--full"; return 0   # unmapped → fail-safe
    fi
  done
  for tok in "${_FAST_CORE_TOKENS[@]}"; do want[$tok]=1; done
  printf '%s\n' "${!want[@]}" | sort
}
