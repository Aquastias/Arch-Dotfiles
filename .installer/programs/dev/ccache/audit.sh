# shellcheck shell=bash
# Feature Audit probe for ccache (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg ccache ccache || return 0
fa_as_root || return 0
fa_check ccache-makepkg "ccache enabled in makepkg BUILDENV" \
  sh -c 'grep -E "^BUILDENV=" /etc/makepkg.conf | grep -qE "[( ]ccache"'
fa_check ccache-runs "ccache reports stats" ccache -s
