#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/probe-lib.sh — guest-side helpers for audit probes
# =============================================================================
# Staged into the guest and sourced before every program's `audit.sh` (ADR
# 0152). A probe prints one line per check: `PASS|FAIL|SKIP <check-id> <msg>`;
# its exit code is ignored, its stderr is a Finding. Env from the runner:
#   FA_USER FA_HOME FA_IS_ROOT(0|1) FA_ONLINE(0|1) FA_PHASE
#   FA_SESSION (niri|Hyprland|kwin_wayland|none) FA_DIR (this probe's staged
#   dir: audit.sh, audit-binds.jsonc, audit-fixtures/) FA_CONFIG (the
#   variant's Effective Config, JSON)
# =============================================================================

fa_pass() { printf 'PASS %s %s\n' "$1" "${*:2}"; }
fa_fail() { printf 'FAIL %s %s\n' "$1" "${*:2}"; }
fa_skip() { printf 'SKIP %s %s\n' "$1" "${*:2}"; }

# fa_check <id> <msg> <cmd…> — PASS when cmd succeeds, else FAIL with the
# command's first output line appended (the "why" for the fixing agent).
fa_check() {
  local id="$1" msg="$2" out
  shift 2
  if out="$("$@" 2>&1)"; then fa_pass "$id" "$msg"
  else fa_fail "$id" "$msg: $(head -1 <<<"$out")"; fi
}

# fa_installed <pkg> — the package is installed.
fa_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# fa_require_pkg <probe> <pkg> — SKIP the whole probe (return 1) when its
# program is not part of this variant; `fa_require_pkg x y || return 0`.
fa_require_pkg() {
  fa_installed "$2" && return 0
  fa_skip "$1-installed" "$2 not installed in this variant"
  return 1
}

# fa_as_root / fa_as_user — the probe runs once per account; gate checks.
fa_as_root() { [[ "${FA_IS_ROOT:-0}" == 1 ]]; }
fa_as_user() { [[ "${FA_IS_ROOT:-0}" != 1 ]]; }

# fa_cfg <jq-filter> — read the variant's Effective Config.
fa_cfg() { jq -r "$1" "$FA_CONFIG" 2>/dev/null; }

# fa_unit_active <unit> — system unit is active.
fa_unit_active() { systemctl is-active --quiet "$1"; }

# fa_no_stderr <cmd…> — succeeds iff the command exits 0 and writes nothing
# to stderr (startup warnings count as breakage).
fa_no_stderr() {
  local err
  err="$("$@" 2>&1 >/dev/null)" || { printf '%s\n' "$err"; return 1; }
  [[ -z "$err" ]] || { printf '%s\n' "$err"; return 1; }
}
