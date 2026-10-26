#!/usr/bin/env bats
# Tests for the live keybind phase's session-ending judgement (ADR 0152).
# Audit Run 20261025: SDDM's Relogin=true restarted Umbriel within a second
# of a confirmed quit, so "a compositor process exists" read as "the session
# did not end". The judge follows the compositor PID the bind was sent to.

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/feature-audit/live.sh"
  _live_bind_recover() { :; }
  sleep() { :; }
  ROW='{"action":"session-quit"}'
  # the guest's compositor PIDs come from $PIDS
  feature_audit_agent() {
    local command="$2"
    case "$command" in
      "pgrep -ox "*) printf '%s\n' "${PIDS%% *}" ;;
      "test -d /proc/"*)
        [[ " $PIDS " == *" ${command#test -d /proc/} "* ]] ;;
    esac
  }
}

@test "session-end: a relogin's new compositor still counts as ended" {
  PIDS="100"
  pid="$(_live_compositor_pid umbriel)"
  PIDS="200"            # the old session exited, SDDM relogged a new one
  run _live_bind_session_end "$ROW" bind-x Mod+Shift+E umbriel "" "$pid"
  [ "$output" = "PASS bind-x session ended" ]
}

@test "session-end: the same compositor still running fails" {
  PIDS="100"
  pid="$(_live_compositor_pid umbriel)"
  run _live_bind_session_end "$ROW" bind-x Mod+Shift+E umbriel "" "$pid"
  [[ "$output" == "FAIL bind-x (session-quit) did not end the session" ]]
}
