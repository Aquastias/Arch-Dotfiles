#!/usr/bin/env bash
# =============================================================================
# vm/lib/flow-guided.sh — Guided Installer test VM flow (--guided, issue 01b)
# =============================================================================
# Reuses the disposable test flow (flow-test.sh) verbatim — VM lifecycle, serial
# capture, the ===INSTALLER-EXIT-N=== sentinel, and opt-in boot-verify — and
# swaps ONLY the cloud-init runcmd: instead of injecting an install.jsonc and
# running install.sh positionally, it drives `install.sh --guided` headlessly.
# The guest resolves the install disk in-guest via the Pre-Install Picker,
# writes a replay answers file (hostname / disk / INSTALL), and runs the Guided
# Installer through its replay seam (no fzf, no tty), assembling the same
# single-disk Effective Config the back-end + VM suite already cover.
#
# Selected by `vm.sh --guided`; profiles resolve under tests/vm/profiles/ as
# with --testing.
# =============================================================================

FLOW_GUIDED_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=./flow-test.sh
[[ "$(type -t flow_run)" == function ]] \
  || source "${FLOW_GUIDED_DIR}/flow-test.sh"

# Override the test flow's renderer: drive the Guided Installer rather than the
# positional path. The hostname is taken from the resolved config; the disk is
# picked in-guest. DIRTY_CACHE / VERIFY_BOOT carry through unchanged. The seed's
# options.encryption / options.impermanence.enabled are translated into guided
# answers so the replayed menu exercises the filesystem-first Disks section
# (issue 03 L4) end-to-end.
_flow_render_user_data() {
  local repo_url="$1" hostname encryption impermanence layout n_disks=1
  hostname="$(jq -r '.system.hostname // "arch-guided"' \
    <<<"${INSTALL_CONFIG_CONTENT}")"
  encryption="$(jq -r '.options.encryption // false' \
    <<<"${INSTALL_CONFIG_CONTENT}")"
  impermanence="$(jq -r '.options.impermanence.enabled // false' \
    <<<"${INSTALL_CONFIG_CONTENT}")"
  # guided_layout (issue 04) names a multi-disk ZFS preset for the guided menu to
  # replay; the guest then resolves Σ disk_count disks in-guest. Default single.
  layout="$(jq -r '.guided_layout // "single"' <<<"${INSTALL_CONFIG_CONTENT}")"
  if [[ "$layout" != "single" ]]; then
    [[ "$(type -t skeleton_total_disks)" == function ]] \
      || source "$OS_DIR/lib/config/skeleton.sh"
    n_disks="$(skeleton_total_disks "$(skeleton_preset "$layout")")"
  fi
  # guided_user (issue 07) names an ad-hoc user + passwords the replay authors;
  # the seed appends the create-user form keys + the USER-OK boot check.
  local guided_user
  guided_user="$(jq -c '.guided_user // empty' <<<"${INSTALL_CONFIG_CONTENT}")"
  # guided_extras (issue 04/05) drives the Security & Backup categories: re-pick a
  # minimal committed user, toggle overrides, and the daemons-enabled boot check.
  local guided_extras
  guided_extras="$(jq -c '.guided_extras // empty' <<<"${INSTALL_CONFIG_CONTENT}")"
  _seed_generator_render_guided_user_data \
    "$repo_url" "$hostname" "${DIRTY_CACHE}" "${VERIFY_BOOT}" \
    "$encryption" "$impermanence" "$layout" "$n_disks" "$guided_user" \
    "$guided_extras"
}
