# shellcheck shell=bash
# Feature Audit probe for lazygit (ADR 0152; contract: PROGRAM_SPEC.md).
fa_require_pkg lazygit lazygit || return 0
fa_as_user || return 0
fa_check lazygit-config "curated config applied" \
  test -f "$FA_HOME/.config/lazygit/config.yml"
fa_check lazygit-runs "lazygit starts" lazygit --version
