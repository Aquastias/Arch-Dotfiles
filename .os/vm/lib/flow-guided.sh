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
# picked in-guest. DIRTY_CACHE / VERIFY_BOOT carry through unchanged.
_flow_render_user_data() {
  local repo_url="$1" hostname
  hostname="$(jq -r '.system.hostname // "arch-guided"' \
    <<<"${INSTALL_CONFIG_CONTENT}")"
  _seed_generator_render_guided_user_data \
    "$repo_url" "$hostname" "${DIRTY_CACHE}" "${VERIFY_BOOT}"
}
