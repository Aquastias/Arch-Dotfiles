#!/usr/bin/env bash
# =============================================================================
# lib/chroot/greetd-config.sh — the greeter-agnostic greetd config
# =============================================================================
# Both greetd Display Manager Adapters (greetd + tuigreet, noctalia-greeter;
# ADR 0158) run greetd the same way — VT 2, the `greeter` user, tty2's getty
# conflicted — and differ only in the greeter command, which the caller passes.
#
# Caller contract: ROOT (config-write prefix) and GREETD_CONF_DIR set.
# =============================================================================

[[ -n "${_GREETD_CONFIG_SH_SOURCED:-}" ]] && return 0
_GREETD_CONFIG_SH_SOURCED=1

# greetd_config_write <command> — write config.toml launching <command> as the
# greeter user on VT 2, plus the unit drop-in that owns tty2.
greetd_config_write() {
  local command="$1"
  mkdir -p "${ROOT}${GREETD_CONF_DIR}"
  cat > "${ROOT}${GREETD_CONF_DIR}/config.toml" <<TOML
[terminal]
vt = 2

[default_session]
command = "${command}"
user = "greeter"
TOML

  # VT 2, not 1: fbcon defers its takeover until tty1 is first written, and
  # that restarts vconsole-setup, which raced a session grabbing tty1 (EINVAL
  # on the font op). On tty2 it never contends; greetd(5) wants the VT's getty
  # conflicted, as the packaged unit does for tty1.
  mkdir -p "${ROOT}/etc/systemd/system/greetd.service.d"
  cat > "${ROOT}/etc/systemd/system/greetd.service.d/10-vt2.conf" <<'UNIT'
[Unit]
After=getty@tty2.service
Conflicts=getty@tty2.service
UNIT
}
