#!/usr/bin/env bats
# Boot fatals keep host-side evidence (Audit Run 20261003): base and
# niri-pure never reached SSH with an empty serial log, and `virsh start`'s
# own errors were discarded, so nothing said why.

setup() {
  T="$(mktemp -d)"
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  VM_NAME=arch-audit
  # shellcheck source=../../lib/common.sh
  source "$INSTALLER_DIR/lib/common.sh"
  # shellcheck source=../../lib/feature-audit/live.sh
  source "$INSTALLER_DIR/lib/feature-audit/live.sh"
  virsh() {
    case "$1" in
      start) echo "error: failed to start domain" >&2; return 1 ;;
      domstate) echo "running (booted)" ;;
      screenshot) echo img > "$3" ;;
    esac
  }
  _vm_capacity_preflight() { :; }
}

teardown() { rm -rf "$T"; }

@test "fa_vm_start keeps virsh start's error in the phase dir" {
  fa_vm_start "$T/boot1"
  grep -q 'failed to start domain' "$T/boot1/virsh-start.err"
}

@test "fa_boot_evidence saves domain state and a console screenshot" {
  fa_boot_evidence "$T/boot1"
  grep -q 'running (booted)' "$T/boot1/domstate.txt"
  [ -s "$T/boot1/console.png" ]
}

@test "fa_await_new_boot: a reboot wedged in shutdown is reset, recorded" {
  # Audit Run 20261004: virgl stalls left GPU clients in D state, so the
  # guest never finished shutting down and the variant went fatal.
  FA_SHUTDOWN_GRACE_SEC=10
  fa_agent() { echo old-id; }           # still the old boot
  sleep() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_await_new_boot "$T/boot2" old-id
  grep -q 'virsh reset arch-audit' "$T/virsh.log"
  grep -q 'shutdown' "$T/boot2/vm-reset.txt"
}

@test "fa_await_new_boot: a clean reboot is left alone" {
  FA_SHUTDOWN_GRACE_SEC=10
  fa_agent() { echo new-id; }
  sleep() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_await_new_boot "$T/boot2" old-id
  [ ! -e "$T/virsh.log" ]
  [ ! -e "$T/boot2/vm-reset.txt" ]
}

@test "fa_phase_wanted: an undeclared phase is skipped and recorded" {
  FA_VARIANT_PHASES="boot2 upgrade"
  ! fa_phase_wanted "$T/v" keybinds
  grep -qx 'SKIP phase-keybinds not in this variant'"'"'s Variant Phases' \
    "$T/v/keybinds/phase@gate.probe"
  fa_phase_wanted "$T/v" boot2
  [ ! -e "$T/v/boot2" ]
}

@test "fa_phase_wanted: FEATURE_AUDIT_SKIP drops a phase silently" {
  FA_VARIANT_PHASES="boot2 upgrade" FEATURE_AUDIT_SKIP="boot2"
  ! fa_phase_wanted "$T/v" boot2
  [ ! -e "$T/v/boot2" ]
}

# ── readiness waits (cap, not fixed sleeps) ─────────────────────────────────

@test "fa_wait_until: returns once the check holds twice, well before cap" {
  echo 0 > "$T/n"
  fa_agent() { local n; n=$(($(cat "$T/n") + 1)); echo $n > "$T/n"
    ((n >= 3)); }
  sleep() { SECONDS=$((SECONDS + $1)); echo "$1" >> "$T/slept"; }
  fa_wait_until 90 'true'
  [ "$(cat "$T/n")" -eq 4 ]                      # fail, fail, ok, ok
  [ "$(awk "{s+=\$1} END {print s}" "$T/slept")" -lt 90 ]
}

@test "fa_wait_until: never ready → stops at the cap" {
  fa_agent() { return 1; }
  sleep() { SECONDS=$((SECONDS + $1)); echo "$1" >> "$T/slept"; }
  fa_wait_until 30 'false'
  [ "$(awk "{s+=\$1} END {print s}" "$T/slept")" -eq 30 ]
}

@test "_fa_session_client: the shell process a session should bring up" {
  [ "$(_fa_session_client kde '{}')" = plasmashell ]
  [ "$(_fa_session_client niri '{}')" = noctalia ]
  [ "$(_fa_session_client niri \
    '{"environment":{"wayland_shell":"waybar"}}')" = waybar ]
  [ -z "$(_fa_session_client hyprland \
    '{"environment":{"wayland_shell":"none"}}')" ]
  [ -z "$(_fa_session_client niri '{"environment":{"stock":true}}')" ]
}

# ── Audit Cache (ADR 0152) ───────────────────────────────────────────────────

@test "fa_cache_install_env: base keeps its packages; others use the cache" {
  CACHE_DIR="$T/c"; LIBVIRT_GATEWAY=gw HTTP_PORT=1
  [ "$(fa_cache_install_env base)" = "INSTALL_PKG_CACHE_KEEP=1" ]
  [ -z "$(fa_cache_install_env limine)" ]          # no cache harvested yet
  mkdir -p "$T/c/audit-cache/pkg" "$T/c/audit-cache/aur"
  touch "$T/c/audit-cache/pkg/a-1-1-x86_64.pkg.tar.zst"
  [ "$(fa_cache_install_env limine)" \
    = "INSTALL_PKG_CACHE_SERVER=http://gw:1/audit-cache/pkg" ]
  touch "$T/c/audit-cache/aur/audit-aur.db"
  [[ "$(fa_cache_install_env limine)" \
    == *" INSTALL_AUDIT_AUR_URL=http://gw:1/audit-cache/aur" ]]
}

@test "fa_wait_until: a slow guest check still counts toward the cap" {
  # each check eats 20s of wall clock; a sleep-only count would allow ~6
  fa_agent() { SECONDS=$((SECONDS + 20)); echo x >> "$T/calls"; return 1; }
  sleep() { :; }
  fa_wait_until 30 'false'
  [ "$(wc -l < "$T/calls")" -le 2 ]
}

@test "fa_await_new_boot: unknown old id waits for the guest to go down" {
  # review: with old="" the old boot's own id counted as "new"
  FA_SHUTDOWN_GRACE_SEC=100
  echo 0 > "$T/n"
  fa_agent() { local n; n=$(($(cat "$T/n") + 1)); echo $n > "$T/n"
    case $n in 1) echo oldboot ;; 2) return 1 ;; *) echo newboot ;; esac; }
  sleep() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_await_new_boot "$T/b" ""
  [ "$(cat "$T/n")" -eq 3 ]        # not done at call 1: waited for down
  [ ! -e "$T/virsh.log" ]
}

@test "fa_boot: a silent boot (empty serial) is retried once, recorded" {
  # Audit Run 20261003: base and niri-pure never printed a byte, not even
  # firmware, while identical variants booted fine
  echo 0 > "$T/n"
  fa_vm_start() { :; }
  fa_serial_start() { printf 'Connected to domain\n' > "$1"; }
  fa_serial_stop() { :; }
  fa_wait_ssh() { local n; n=$(($(cat "$T/n") + 1)); echo $n > "$T/n"
    ((n >= 2)); }
  fa_wait_until() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  fa_boot "$T/boot1"
  grep -q 'virsh destroy' "$T/virsh.log"
  grep -q 'silent' "$T/boot1/vm-retry.txt"
  [ ! -e "$T/boot1/fatal.lines" ]
}

@test "fa_boot: a boot that printed but never reached SSH is not retried" {
  fa_vm_start() { :; }
  fa_serial_start() { printf 'BdsDxe: loading Boot0003\n' > "$1"; }
  fa_wait_ssh() { return 1; }
  fa_boot_evidence() { :; }
  virsh() { echo "virsh $*" >> "$T/virsh.log"; }
  ! fa_boot "$T/boot1"
  [ ! -e "$T/boot1/vm-retry.txt" ]
  grep -q 'never reached SSH' "$T/boot1/fatal.lines"
}

@test "_fa_settled: also waits on the audit user's manager (linger jobs)" {
  # kde-pure 20261004: searxng's first image pull (a linger user job) was
  # still running when probes-offline cut the network
  FA_USER=alice
  [[ "$(_fa_settled)" == *"systemctl --user -M alice@ list-jobs"* ]]
  [[ "$(_fa_settled)" == *"systemctl list-jobs"* ]]
}
