#!/usr/bin/env bash
# =============================================================================
# lib/feature-audit/live-phases.sh — later phases + desktop sessions
# =============================================================================
# Part of the live Audit Run (lib/feature-audit/live.sh, ADR 0152).
#
# Used by: lib/feature-audit/live.sh (sources it).
# =============================================================================

# shellcheck source=../config/install-config.sh
declare -F install_config_use_json >/dev/null 2>&1 \
  || source "${BASH_SOURCE[0]%/*}/../config/install-config.sh"

# ── later phases (feature-audit/07) ──────────────────────────────────────────

# _live_timers_script — start every enabled timer's unit once (bounded), so
# delayed work (reflector, freshclam, snapshots, fwupd) fails now, not later.
_live_timers_script() {
  cat <<'SH'
set -u
for t in $(systemctl list-timers --all --no-legend --plain \
    | awk '{for (i=1;i<=NF;i++) if ($i ~ /\.timer$/) {print $i; break}}'); do
  u="$(systemctl show -p Unit --value "$t")"
  [ -n "$u" ] || continue
  if timeout 900 systemctl start "$u" >/dev/null 2>&1; then
    # a unit Condition* skip also "starts" fine: say it never ran
    if [ "$(systemctl show -p ConditionResult --value "$u")" = no ]; then
      echo "SKIP timer-$t $u skipped: its unit condition is unmet"
    else echo "PASS timer-$t started $u"; fi
  else
    echo "FAIL timer-$t $u failed or timed out"
  fi
done
SH
}

# feature_audit_phase_timers <variant-dir> — force timers, soak, collect.
feature_audit_phase_timers() {
  local directory="$1/timers" since
  mkdir -p "$directory"
  since="$(feature_audit_guest_now)"
  _live_timers_script | feature_audit_agent sudo > \
    "$directory/probe-timers@root.probe" 2>&1 \
    || true
  # soak: delayed work the forced timers queued finishes (or fails) now
  feature_audit_wait_until "${FA_SOAK_SEC:-600}" \
    "$(_live_settled) && $_FA_NONE_ACTIVATING"
  feature_audit_collect "$directory" "$since"
}

# _live_boot2_prep_script <user> — plant rollback/persistence markers and
# record identity that must survive the reboot.
_live_boot2_prep_script() {
  printf 'U=%q\n' "$1"
  cat <<'SH'
set -u
echo fa > /etc/fa-rollback-probe
h="$(getent passwd "$U" | cut -d: -f6)"
if [ -n "$h" ]; then
  echo fa > "$h/.fa-persist-probe"; chown "$U" "$h/.fa-persist-probe"
fi
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
  | awk '{print $2}' > /var/tmp/fa-hostkey
cp /var/tmp/fa-hostkey "$h/.fa-hostkey" 2>/dev/null || true
SH
}

# _live_boot2_check_script <user> <impermanent> <sops> — the reboot proofs.
_live_boot2_check_script() {
  cat "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh"
  printf 'U=%q IMP=%q SOPS=%q\n' "$1" "$2" "$3"
  cat <<'SH'
set -u

h="$(getent passwd "$U" | cut -d: -f6)"
if [ "$IMP" = true ]; then
  [ -e /etc/fa-rollback-probe ] \
    && feature_audit_fail rollback \
      "/etc marker survived reboot (not rolled back)" \
    || feature_audit_pass rollback "/etc rolled back"
fi
[ -e "$h/.fa-persist-probe" ] && feature_audit_pass home-persist "home kept" \
  || feature_audit_fail home-persist "home marker lost on reboot"
now="$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null \
  | awk '{print $2}')"
[ -n "$now" ] && [ "$now" = "$(cat "$h/.fa-hostkey" 2>/dev/null)" ] \
  && feature_audit_pass ssh-hostkey "host key stable" \
  || feature_audit_fail ssh-hostkey "ssh host key changed across reboot"
if [ "$SOPS" = true ]; then
  systemctl is-active --quiet sops-runtime.service \
    && feature_audit_pass sops-runtime "decrypted on boot" \
    || feature_audit_fail sops-runtime \
      "sops-runtime.service not active after reboot"
fi
rm -f "$h/.fa-persist-probe" "$h/.fa-hostkey" /etc/fa-rollback-probe
SH
}

# feature_audit_phase_boot2 <variant-dir> <cfg> — reboot and prove what must
# survive.
feature_audit_phase_boot2() {
  local directory="$1/boot2" config="$2" impermanence sops
  mkdir -p "$directory"
  # get: the authored toggle, as the boot2 check expects it
  impermanence="$(install_config_from_json "$config" \
    get impermanence_enabled)"
  sops="$(jq -r 'if (.options.age_key_url // "") != "" then true
                 else false end' <<<"$config")"
  _live_boot2_prep_script "$FA_USER" \
    | feature_audit_agent sudo >/dev/null 2>&1 || true
  feature_audit_reboot "$directory" || return 1
  _live_boot2_check_script "$FA_USER" "$impermanence" "$sops" \
    | feature_audit_agent sudo > "$directory/probe-boot@root.probe" 2>&1 || true
  feature_audit_collect "$directory"
}

# _live_default_session_script <session-id> <display-manager|detect> — the
# Default Session proof (ADR 0159): the greeter remembers desktop[0]'s session
# entry as its last one. `detect` reads the enabled greeter on the guest.
# FA_ROOT prefixes the guest paths (tests).
_live_default_session_script() {
  cat "$INSTALLER_DIR/lib/feature-audit/probe-lib.sh"
  printf 'ID=%q DM=%q\n' "$1" "$2"
  cat <<'SH'
R="${FA_ROOT:-}"
if [ "$DM" = detect ]; then
  DM="$(readlink "$R/etc/systemd/system/display-manager.service")"
  DM="${DM##*/}"; DM="${DM%.service}"
  [ "$DM" = greetd ] && grep -q noctalia-greeter "$R/etc/greetd/config.toml" \
    && DM=noctalia-greeter
fi
case "$DM" in
  noctalia-greeter)
    grep -qx "last = \"$ID\"" "$R/var/lib/noctalia-greeter/sync.toml" ;;
  greetd) grep -q "/$ID\.desktop\$" "$R/var/cache/tuigreet/lastsession-path" ;;
  sddm) grep -qx "Session=.*/$ID\.desktop" "$R/var/lib/sddm/state.conf" ;;
  *) feature_audit_skip default-session "no display manager"; exit 0 ;;
esac 2>/dev/null \
  && feature_audit_pass default-session "the $DM greeter preselects $ID" \
  || feature_audit_fail default-session "the $DM greeter does not remember $ID"
SH
}

# feature_audit_phase_default_session <variant-dir> <cfg> — on the first boot,
# before the sessions phase logs in (SDDM rewrites its last session on every
# login), prove the greeter preselects the Default Session.
feature_audit_phase_default_session() {
  local directory="$1/boot1" session
  # the same desktop → session-entry map the Display Manager Adapters seed
  # shellcheck source=../chroot/default-session.sh
  source "$INSTALLER_DIR/lib/chroot/default-session.sh"
  session="$(ENVIRONMENT_DESKTOP="$(feature_audit_desktops "$2")" \
    default_session_id)" || return 0
  _live_default_session_script "$session" detect \
    | feature_audit_agent sudo \
    > "$directory/probe-default-session@root.probe" 2>&1 || true
}

# feature_audit_phase_power <variant-dir> — ACPI suspend-to-RAM and wake (the VM
# is created with S3/S4, VM_PM): the guest suspends itself, the host waits for
# `pmsuspended`, wakes it and proves it came back. Hibernation needs a resume
# device the guest may not have; the probe says why when skipped.
feature_audit_phase_power() {
  local directory="$1/power" out since domain_state=""
  out="$directory/probe-power@root.probe"
  mkdir -p "$directory"
  since="$(feature_audit_guest_now)"
  feature_audit_agent sudo "systemd-run --on-active=5 systemctl suspend" \
    >/dev/null 2>&1
  for _ in $(seq 30); do
    domain_state="$(virsh domstate "$VM_NAME" 2>/dev/null)"
    [[ "$domain_state" == pmsuspended ]] && break
    sleep 2
  done
  if [[ "$domain_state" != pmsuspended ]]; then
    echo "FAIL power-suspend guest never reached S3" \
      "(domstate: $domain_state)" >> "$out"
  else
    echo "PASS power-suspend guest entered S3" >> "$out"
    virsh dompmwakeup "$VM_NAME" >/dev/null 2>&1
    if feature_audit_wait_ssh 180; then
      echo "PASS power-resume guest woke and answers SSH" >> "$out"
    else
      echo "FAIL power-resume guest did not come back from S3" >> "$out"
      return 1
    fi
  fi
  feature_audit_agent sudo "sh -c 'swapon --show=NAME --noheadings; \
    cat /sys/power/state /sys/power/disk'" > "$directory/power-state.txt" 2>&1
  if grep -qw disk "$directory/power-state.txt" \
     && feature_audit_agent sudo "sh -c 'grep -q resume= /proc/cmdline'" \
       >/dev/null 2>&1
  then
    _live_hibernate "$directory" "$out" || return 1
  else
    echo "SKIP power-hibernate no resume device configured" \
      "(ZFS swap on a zvol cannot hibernate)" >> "$out"
  fi
  feature_audit_collect "$directory" "$since"
}

# _live_hibernate <directory> <probe-file> — S4: the VM powers off; starting
# it again must RESUME (same boot id).
_live_hibernate() {
  local directory="$1" out="$2" boot_id
  boot_id="$(feature_audit_agent sudo cat /proc/sys/kernel/random/boot_id)"
  feature_audit_agent sudo "systemd-run --on-active=5 systemctl hibernate" \
    >/dev/null 2>&1
  for _ in $(seq 90); do
    [[ "$(virsh domstate "$VM_NAME" 2>/dev/null)" == "shut off" ]] && break
    sleep 2
  done
  feature_audit_serial_stop \
      # capture ended with the power-off; unlock needs it back
  feature_audit_vm_start "$directory" || return 1
  feature_audit_serial_start "$directory/serial.log"
  if ! feature_audit_wait_ssh "$FA_BOOT_TIMEOUT_SEC"; then
    echo "FAIL power-hibernate no SSH after resume" >> "$out"; return 1
  fi
  if [[ "$(feature_audit_agent sudo cat /proc/sys/kernel/random/boot_id)" \
        == "$boot_id" ]]
  then echo "PASS power-hibernate resumed from S4" >> "$out"
  else echo "FAIL power-hibernate booted fresh instead of resuming" >> "$out"
  fi
}

# feature_audit_phase_upgrade <variant-dir> — full upgrade, reboot, collect.
# feature_audit_upgrade_run <dir> — `pacman -Syu` as a transient unit on the
# guest, so its own post-transaction service restarts (which can drop SSH)
# cannot fake a failure: poll the unit, judge its exit status, keep its journal.
feature_audit_upgrade_run() {
  local directory="$1" unit=fa-upgrade elapsed=0 state rc
  mkdir -p "$directory"
  feature_audit_agent sudo "systemd-run --unit=$unit --collect \
    -p RemainAfterExit=yes \
    pacman -Syu --noconfirm" >/dev/null 2>&1 || true
  while ((elapsed < 3600)); do
    sleep 10; elapsed=$((elapsed + 10))
    rc=0; feature_audit_agent sudo \
      "systemctl is-active --quiet $unit" >/dev/null 2>&1 \
      || rc=$?
    # 255: ssh itself failed (a hook restarting sshd, kernels 20261006) —
    # the unit is not known to be done: keep polling
    ((rc == 255)) && continue
    ((rc == 0)) || break
    state="$(feature_audit_agent sudo \
      "systemctl show -p SubState --value $unit" 2>/dev/null)"
    [[ "$state" == exited ]] && break
  done
  feature_audit_wait_ssh 300 || true
  feature_audit_agent sudo "journalctl -u $unit --no-pager -o cat" > \
    "$directory/pacman.log" 2>&1
  state="$(feature_audit_agent sudo \
    "systemctl show -p ExecMainStatus --value $unit" \
    2>/dev/null)"
  feature_audit_agent sudo "systemctl stop $unit" >/dev/null 2>&1 || true
  [[ "$state" == 0 ]]
}

feature_audit_phase_upgrade() {
  local directory="$1/upgrade"
  mkdir -p "$directory"
  feature_audit_upgrade_run "$directory" \
    || feature_audit_fatal "$directory" "pacman -Syu failed (see pacman.log)"
  feature_audit_reboot "$directory" || return 1
  feature_audit_collect "$directory"
}

# ── sessions (feature-audit/08) ──────────────────────────────────────────────

# feature_audit_desktops <cfg> — the variant's desktop set, one per line.
feature_audit_desktops() {
  jq -r '.environment.desktop // [] | if type == "string" then [.] else . end
    | .[]' <<<"$1"
}

# _live_session_logs_script <user> — compositor/session logs the journal lacks
# (Hyprland's own log, the DM's wayland-session log) into /tmp/fa-logs.
_live_session_logs_script() {
  printf 'U=%q\n' "$1"
  cat <<'SH'
set -u
o=/tmp/fa-logs; rm -rf "$o"; mkdir -p "$o"
uid="$(id -u "$U")"; h="$(getent passwd "$U" | cut -d: -f6)"
for f in /run/user/"$uid"/hypr/*/hyprland.log; do
  [ -f "$f" ] && cp "$f" "$o/hyprland.log"
done
[ -f "$h/.local/share/sddm/wayland-session.log" ] \
  && cp "$h/.local/share/sddm/wayland-session.log" "$o/wayland-session.log"
[ -f "$h/.local/share/sddm/xorg-session.log" ] \
  && cp "$h/.local/share/sddm/xorg-session.log" "$o/xorg-session.log"
chmod -R a+rX "$o"
SH
}

# _live_session_client <desktop> <cfg> — the shell process a session brings up
# (empty: none expected, a stock or shell-less wlroots session).
_live_session_client() {
  [[ "$1" == kde ]] && { echo plasmashell; return; }
  (
    install_config_use_json "$2"
    [[ "$(install_config_stock)" == true ]] && exit 0
    local client; client="$(install_config_wayland_shell)"
    [[ "$client" == none ]] || printf '%s\n' "$client"
  )
}

# _live_session_settled <user> <client> — guest check: the shell client (if
# any) runs and the user manager has no job queued.
_live_session_settled() {
  local user="$1" client="$2"
  printf '%s' "${client:+pgrep -user $user -x $client >/dev/null && }"
  # shellcheck disable=SC2016 # guest-side shell, expanded there
  printf '[ -z "$(runuser -u %s -- env XDG_RUNTIME_DIR=/run/user/$(id -u %s)' \
    "$user" "$user"
  printf ' systemctl --user list-jobs --no-legend)" ]'
}

# feature_audit_phase_sessions <variant-dir> <cfg> — log into each compositor of
# the set (one phase dir per desktop), collect its window, screenshot it.
feature_audit_phase_sessions() {
  local variant_directory="$1" config="$2" desktop directory since app
  while IFS= read -r desktop; do
    [[ -n "$desktop" ]] || continue
    directory="$variant_directory/sessions-$desktop"
    mkdir -p "$directory/screens"
    since="$(feature_audit_guest_now)"
    if ! feature_audit_agent session "$desktop" > \
      "$directory/agent.txt" 2>&1; then
      echo "session $desktop did not become ready (see agent.txt)" \
        >> "$directory/session-start.lines"
      feature_audit_collect "$directory" "$since"
      continue
    fi
    feature_audit_agent idle off >/dev/null 2>&1 || true
    feature_audit_wait_until "${FA_SESSION_SETTLE_SEC:-45}" \
      "$(_live_session_settled \
      "$FA_USER" "$(_live_session_client "$desktop" "$config")")"
    feature_audit_agent shot "$directory/screens/session-$desktop.png" >> \
      "$directory/agent.txt" 2>&1 \
      || echo "session $desktop: screenshot failed" >> \
      "$directory/session-start.lines"
    feature_audit_collect "$directory" "$since"
    _live_session_logs_script "$FA_USER" \
      | feature_audit_agent sudo >/dev/null 2>&1 \
      && feature_audit_pull_into /tmp/fa-logs "$directory" || true
    # desktop probes (extras/desktop/<de>/audit.sh) in this very session
    if [[ -f "$INSTALLER_DIR/extras/desktop/$desktop/audit.sh" ]] \
       && feature_audit_stage_probes "$config" \
       "$INSTALLER_DIR/extras/desktop/$desktop"; then
      feature_audit_run_probes "$directory" "sessions-$desktop" 1 "$config" \
        "$FA_USER"
    fi
    # toolkit screenshots for visual review (ADR 0117: Qt → Dolphin, GTK →
    # nm-connection-editor)
    for app in dolphin nm-connection-editor; do
      feature_audit_agent launch "$app" >/dev/null 2>&1 || continue
      sleep 5
      feature_audit_agent shot "$directory/screens/$desktop-$app.png" >> \
        "$directory/agent.txt" 2>&1
      feature_audit_agent sudo "pkill -x $app" >/dev/null 2>&1 || true
    done
  done < <(feature_audit_desktops "$config")
}
