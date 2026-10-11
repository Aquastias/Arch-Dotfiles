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

feature_audit_pass() { printf 'PASS %s %s\n' "$1" "${*:2}"; }
feature_audit_fail() { printf 'FAIL %s %s\n' "$1" "${*:2}"; }
feature_audit_skip() { printf 'SKIP %s %s\n' "$1" "${*:2}"; }

# feature_audit_check <id> <msg> <cmd…> — PASS when cmd succeeds, else FAIL with the
# command's most telling output line (first error-shaped, else last) as the
# "why" for the fixing agent.
feature_audit_check() {
  local id="$1" msg="$2" out why
  shift 2
  if out="$("$@" 2>&1)"; then feature_audit_pass "$id" "$msg"; return; fi
  why="$(grep -iE -m1 'error|fail|denied|not |cannot|can.t|missing|invalid' \
    <<<"$out")" || why="$(tail -1 <<<"$out")"
  feature_audit_fail "$id" "$msg${why:+: $why}"
}

# feature_audit_installed <pkg> — the package is installed.
feature_audit_installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# feature_audit_require_package <probe> <pkg> — SKIP the whole probe (return 1) when its
# program is not part of this variant; `feature_audit_require_package x y || return 0`.
feature_audit_require_package() {
  feature_audit_installed "$2" && return 0
  feature_audit_skip "$1-installed" "$2 not installed in this variant"
  return 1
}

# feature_audit_as_root / feature_audit_as_user — the probe runs once per account; gate checks.
feature_audit_as_root() { [[ "${FA_IS_ROOT:-0}" == 1 ]]; }
feature_audit_as_user() { [[ "${FA_IS_ROOT:-0}" != 1 ]]; }

# feature_audit_config <jq-filter> — read the variant's Effective Config.
feature_audit_config() { jq -r "$1" "$FA_CONFIG" 2>/dev/null; }

# feature_audit_unit_active <unit> — system unit is active.
feature_audit_unit_active() { systemctl is-active --quiet "$1"; }

# feature_audit_no_stderr <cmd…> — succeeds iff the command exits 0 and writes nothing
# to stderr (startup warnings count as breakage).
feature_audit_no_stderr() {
  local err
  err="$("$@" 2>&1 >/dev/null)" || { printf '%s\n' "$err"; return 1; }
  [[ -z "$err" ]] || { printf '%s\n' "$err"; return 1; }
}

# feature_audit_no_stderr_but <ere> <cmd…> — feature_audit_no_stderr, tolerating stderr lines that
# match <ere> (a known-benign line the variant explains, never a blanket pass).
feature_audit_no_stderr_but() {
  local ere="$1" err rc=0; shift
  err="$("$@" 2>&1 >/dev/null)" || rc=$?
  err="$(grep -vE -- "$ere" <<< "$err")"
  ((rc == 0)) && [[ -z "$err" ]] && return 0
  [[ -z "$err" ]] || printf '%s\n' "$err"
  return 1
}

# ── Probe Gate (ADR 0152): conditions a check needs from the Host Profile ──
# feature_audit_gate <id> <reason> <cmd…> — when cmd fails the variant lacks what the
# check needs: SKIP it with <reason> and return 1, so `feature_audit_gate … || return 0`
# (whole probe) or `if feature_audit_gate …; then feature_audit_check …; fi` (one check).
feature_audit_gate() {
  local id="$1" reason="$2"; shift 2
  "$@" >/dev/null 2>&1 && return 0
  feature_audit_skip "$id" "$reason"
  return 1
}

# feature_audit_stock — the variant is an upstream-stock install (Pure Profiles, ADR
# 0112): our curated desktop config and userland are not deployed.
feature_audit_stock() { [[ "$(feature_audit_config '.environment.stock // false')" == true ]]; }

# feature_audit_curated — our curated desktop config and userland are deployed.
feature_audit_curated() { ! feature_audit_stock; }

# feature_audit_has_shell — a Wayland shell is deployed: not stock, not `none` (absent
# = the product default, noctalia).
feature_audit_has_shell() {
  feature_audit_curated \
    && [[ "$(feature_audit_config '.environment.wayland_shell // "noctalia"')" != none ]]
}

# feature_audit_host_core — the variant inherits Host Core packages (the run stamps
# `_audit.host_core`; absent = the product default, inherited).
feature_audit_host_core() { [[ "$(feature_audit_config '._audit.host_core')" != false ]]; }
