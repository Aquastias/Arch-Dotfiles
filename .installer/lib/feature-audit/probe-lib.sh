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
# command's most telling output line (first error-shaped, else last) as the
# "why" for the fixing agent.
fa_check() {
  local id="$1" msg="$2" out why
  shift 2
  if out="$("$@" 2>&1)"; then fa_pass "$id" "$msg"; return; fi
  why="$(grep -iE -m1 'error|fail|denied|not |cannot|can.t|missing|invalid' \
    <<<"$out")" || why="$(tail -1 <<<"$out")"
  fa_fail "$id" "$msg${why:+: $why}"
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

# fa_no_stderr_but <ere> <cmd…> — fa_no_stderr, tolerating stderr lines that
# match <ere> (a known-benign line the variant explains, never a blanket pass).
fa_no_stderr_but() {
  local ere="$1" err rc=0; shift
  err="$("$@" 2>&1 >/dev/null)" || rc=$?
  err="$(grep -vE -- "$ere" <<< "$err")"
  ((rc == 0)) && [[ -z "$err" ]] && return 0
  [[ -z "$err" ]] || printf '%s\n' "$err"
  return 1
}

# ── Probe Gate (ADR 0152): conditions a check needs from the Host Profile ──
# fa_gate <id> <reason> <cmd…> — when cmd fails the variant lacks what the
# check needs: SKIP it with <reason> and return 1, so `fa_gate … || return 0`
# (whole probe) or `if fa_gate …; then fa_check …; fi` (one check).
fa_gate() {
  local id="$1" reason="$2"; shift 2
  "$@" >/dev/null 2>&1 && return 0
  fa_skip "$id" "$reason"
  return 1
}

# fa_stock — the variant is an upstream-stock install (Pure Profiles, ADR
# 0112): our curated desktop config and userland are not deployed.
fa_stock() { [[ "$(fa_cfg '.environment.stock // false')" == true ]]; }

# fa_curated — our curated desktop config and userland are deployed.
fa_curated() { ! fa_stock; }

# fa_has_shell — a Wayland shell is deployed: not stock, not `none` (absent
# = the product default, noctalia).
fa_has_shell() {
  fa_curated \
    && [[ "$(fa_cfg '.environment.wayland_shell // "noctalia"')" != none ]]
}

# fa_host_core — the variant inherits Host Core packages (the run stamps
# `_audit.host_core`; absent = the product default, inherited).
fa_host_core() { [[ "$(fa_cfg '._audit.host_core')" != false ]]; }
