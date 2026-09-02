#!/usr/bin/env bash
# =============================================================================
# vm/lib/flow-test.sh — disposable test VM flow (--testing)
# =============================================================================
# Sourced by vm/vm.sh alongside core.sh. Boots a throwaway libvirt VM headless,
# runs install.sh --unattended via a cloud-init runcmd seed, captures the serial
# console, waits for the ===INSTALLER-EXIT-N=== sentinel, and propagates the
# installer's exit code (0 ok / 124 timeout / 125 boot-fail). Opt-in boot-verify
# (--verify-boot or VERIFY_BOOT) ejects the cdroms, optionally permutes data
# disks (reorder) and corrupts the live zpool.cache (dirty-cache), boots the
# installed disk, and waits for the first-boot sentinel — driven entirely by the
# profile's verify block (boot/by_id/reorder/dirty_cache/pools/mounts/owned).
#
# Consumes (set by vm.sh): VM_NAME, VM_DISK_SIZES[], VM_RAM_MB, VM_VCPUS,
# INSTALL_CONFIG_CONTENT, RECREATE, VERIFY_BOOT, DIRTY_CACHE,
# VM_REORDER_BOOT_DISKS, VM_VERIFY_BYID, VM_VERIFY_POOLS[], VM_VERIFY_MOUNTS[],
# VM_VERIFY_OWNED[].
# =============================================================================

FLOW_TEST_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# core.sh provides the shared host-side functions + defaults; guard-source so
# vm.sh sourcing core first does not double-source.
# shellcheck source=./core.sh
[[ "$(type -t core_resolve_iso)" == function ]] \
  || source "${FLOW_TEST_DIR}/core.sh"
# shellcheck source=./seed-generator.sh
source "${FLOW_TEST_DIR}/seed-generator.sh"
# shellcheck source=./sentinel-watcher.sh
source "${FLOW_TEST_DIR}/sentinel-watcher.sh"
# shellcheck source=./console-answerer.sh
source "${FLOW_TEST_DIR}/console-answerer.sh"

# Per-flow virt-install graphics. Headless by default (fast, no GPU). When the
# profile needs a real Wayland session (VM_GPU — set by verify.sessions), attach
# a virtio-gpu with virgl 3D rendered headlessly through the host's render node,
# so kwin_wayland / Hyprland get a DRM device + GL and can actually start.
if [[ "${VM_GPU:-false}" == "true" ]]; then
  # shellcheck disable=SC2054  # commas are inside single virt-install args, not
  # array-element separators.
  FLOW_GRAPHICS_ARGS=(
    --video model.type=virtio,model.acceleration.accel3d=on
    --graphics type=egl-headless,gl.rendernode=/dev/dri/renderD128
  )
else
  FLOW_GRAPHICS_ARGS=(--graphics none)
fi

# Flow defaults (env overrides win; timeouts also resolved env>profile>here).
: "${TEST_VM_DIR:=${FLOW_TEST_DIR%/vm/lib}/tests/vm}"
: "${CACHE_DIR:=${TEST_VM_DIR}/.vm-test}"
: "${LOG_FILE:=${TEST_VM_DIR}/${VM_NAME}.log}"
: "${BOOT_LOG_FILE:=${TEST_VM_DIR}/${VM_NAME}-boot.log}"
: "${TIMEOUT_SEC:=1800}"
: "${BOOT_TIMEOUT_SEC:=600}"
# Fixture HTTP server (the secure profile's Test Age Key is fetched by the
# Secrets Module at http://<gateway>:<port>/key.age during install). Ported from
# the persistent flow; only stood up when a profile declares fixtures.
: "${HTTP_PORT:=9876}"
_HTTP_PID=""

# Verify-block knobs (default off so a plain install profile behaves vanilla).
: "${VERIFY_BOOT:=false}"
: "${DIRTY_CACHE:=false}"
# Hold-on-fail (ADR 0099): default off so a matrix cell still self-disposes on
# poweroff. When on, a FAILED cell skips poweroff and gives ttyS0 a root
# autologin shell, so the VM stays inspectable over `virsh console`.
: "${HOLD_ON_FAIL:=false}"
: "${VM_REORDER_BOOT_DISKS:=false}"
: "${VM_VERIFY_BYID:=false}"
: "${VM_VERIFY_RESILIENCE:=false}"

# =============================================================================
# SEED — cloud-init runcmd, install.jsonc injected base64 (all profile types)
# =============================================================================
# Always injects the resolved install.jsonc (the profile resolver is the single
# source of truth). The first-boot verify block is chosen from the profile's
# verify data: pools present → the pool verifier (lib/vm-pool-verify.sh); else a
# plain boot sentinel. DIRTY_CACHE corrupts the live zpool.cache before install.
_flow_render_user_data() {
  local repo_url="$1" config_b64
  config_b64="$(printf '%s' "${INSTALL_CONFIG_CONTENT}" | base64 -w 0)"

  local dirty_step=""
  [[ "${DIRTY_CACHE}" == "true" ]] && \
    dirty_step='mkdir -p /etc/zfs && printf %s garbage-not-an-nvlist > /etc/zfs/zpool.cache && '

  # On failure with HOLD_ON_FAIL, skip poweroff and hand ttyS0 a root autologin
  # shell so a failed cell is inspectable over serial (ADR 0099); otherwise the
  # cell always powers off so the matrix disposes of it.
  local poweroff_step="    poweroff -f"
  if [[ "${HOLD_ON_FAIL}" == "true" ]]; then
    poweroff_step="$(cat <<HOLD
    if [ "\$rc" -eq 0 ]; then
      poweroff -f
    else
$(_serial_autologin_root_lines)
    fi
HOLD
)"
  fi

  local boot_block=""
  if [[ "${VERIFY_BOOT}" == "true" ]]; then
    if [[ "${VM_VERIFY_ROLLBACK:-false}" == "true" ]]; then
      # Impermanence rollback proof (ADR 0044): a stateful two-boot sentinel.
      # VM_ROLLBACK_PROBE_DIR overrides the probe path for the assertion negative
      # control (/persist = a survivor → probe persists → host RED).
      # VM_ROLLBACK_BREAK_BLANK=true is the hook-level fault control: boot1
      # destroys a @blank so boot2's hook fails closed → emergency shell → RED.
      # VM_ROLLBACK_FS selects the rollback mechanics (zfs datasets vs btrfs
      # subvols, ADR 0044); default zfs keeps the existing runs unchanged.
      boot_block="$(_seed_generator_rollback_firstboot_block \
        "${VM_ROLLBACK_PROBE_DIR:-/root}" "${VM_ROLLBACK_BREAK_BLANK:-false}" \
        "${VM_ROLLBACK_FS:-zfs}")"
    elif [[ "${VM_VERIFY_RESILIENCE}" == "true" ]]; then
      boot_block="$(_seed_generator_esp_resilience_firstboot_block)"
    elif [[ -n "${VM_VERIFY_POOLS[*]:-}" ]]; then
      boot_block="$(_seed_generator_multi_firstboot_block \
        "${VM_VERIFY_POOLS[*]:-}" "${VM_VERIFY_MOUNTS[*]:-}" \
        "${VM_VERIFY_BYID:-false}" "${VM_VERIFY_OWNED[*]:-}" \
        "${VM_VERIFY_FS_MOUNTS[*]:-}")"
    elif [[ -n "${VM_VERIFY_SESSIONS[*]:-}" ]]; then
      # Graphical-login proof (ADR 0062): stage the session prober that logs into
      # each desktop in turn and emits its OK marker.
      boot_block="$(_seed_generator_session_firstboot_block \
        "${VM_SESSION_USER:-aquastias}" "${VM_VERIFY_SESSIONS[@]}")"
    else
      boot_block="$(_seed_generator_firstboot_block "" "" \
        "${VM_VERIFY_DESKTOPS[*]:-}" "${VM_VERIFY_DM:-}")"
    fi
  fi

  cat <<EOF
#cloud-config
# Generated by vm/lib/flow-test.sh — do not edit by hand.
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && printf '%s' '${config_b64}' | base64 -d \
  > /root/dotfiles/.installer/install.jsonc \\
        && cd /root/dotfiles/.installer \\
        && export INSTALL_ENC_PASSPHRASE='testtest' \\
        && export SECRETS_AGE_PASSPHRASE='test' \\
        && ${dirty_step}./install.sh --unattended install.jsonc
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
${poweroff_step}
EOF
}

_flow_build_seed() {
  local user_data="${CACHE_DIR}/${VM_NAME}-user-data"
  local seed_iso="${CACHE_DIR}/${VM_NAME}-seed.iso"
  _flow_render_user_data "${REPO_URL}" > "${user_data}"
  cloud-localds "${seed_iso}" "${user_data}" >/dev/null \
    || error "cloud-localds failed for ${user_data}"
  [[ -s "${seed_iso}" ]] || \
    error "cloud-localds produced empty seed at ${seed_iso}"
  printf '%s\n' "${seed_iso}"
}

# Serial console capture (_start_console_capture / _console_capture_loop /
# _stop_console_capture / _wait_for_serial_pty) is shared with the persistent
# flow and lives in core.sh (ADR 0099).

# CONSOLE ANSWERER — supply the disk-unlock passphrase over serial so encrypted
# roots boot-verify unattended. The prompt reads /dev/console (console=ttyS0 is
# injected), so we write to the serial char device (virsh ttyconsole), not
# send-key. Harmless on plaintext boots: the matcher fires only on unlock
# prompts. The pure matcher lives in console-answerer.sh (unit-tested).
CONSOLE_ANSWERER_PID=""

_start_console_answerer() {
  local dev; dev="$(virsh ttyconsole "$VM_NAME" 2>/dev/null)" || return 0
  [[ -n "$dev" ]] || return 0
  console_answerer_watch "$BOOT_LOG_FILE" "$dev" &
  CONSOLE_ANSWERER_PID=$!
  info "Console Answerer watching for unlock prompts → ${dev}."
}

# shellcheck disable=SC2329
_stop_console_answerer() {
  [[ -n "$CONSOLE_ANSWERER_PID" ]] || return 0
  kill "$CONSOLE_ANSWERER_PID" 2>/dev/null || true
  wait "$CONSOLE_ANSWERER_PID" 2>/dev/null || true
  CONSOLE_ANSWERER_PID=""
}

# Stage declared fixtures into CACHE_DIR and serve it over HTTP on the libvirt
# gateway, so the in-guest Secrets Module can fetch the Test Age Key
# (http://<gateway>:<port>/key.age) during a secure install. No-op when the
# profile declares no fixtures. Smoke-only (live python http.server).
_start_fixture_http_server() {
  _fixture_http_should_serve || return 0
  _stage_fixture_files
  python3 -m http.server "${HTTP_PORT}" \
    --directory "${CACHE_DIR}" \
    --bind "${LIBVIRT_GATEWAY}" \
    >/dev/null 2>&1 &
  _HTTP_PID=$!
  info "Serving fixtures at http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/ (pid ${_HTTP_PID})."
}

# shellcheck disable=SC2329
_stop_fixture_http_server() {
  [[ -n "${_HTTP_PID}" ]] || return 0
  kill "${_HTTP_PID}" 2>/dev/null || true
  _HTTP_PID=""
}

# shellcheck disable=SC2329
_on_signal() { _stop_console_answerer; _stop_console_capture; \
  _stop_fixture_http_server; exit "$((128 + ${1:-2}))"; }

# =============================================================================
# BOOT VERIFY (opt-in)
# =============================================================================
# Permute data-disk backing files on the (shut-off) domain so the installed
# system boots with a different /dev/sdX order than it installed under. The OS
# disk stays put. reorder-disks.py is pure + unit-tested (vm-reorder-disks.bats).
_reorder_boot_disks() {
  command -v python3 >/dev/null 2>&1 \
    || { warn "python3 missing — skipping disk reorder."; return 1; }
  local reordered="${CACHE_DIR}/${VM_NAME}-reordered.xml"
  info "Reordering data disks before boot (multi-disk reorder repro)."
  virsh dumpxml --inactive "$VM_NAME" \
    | python3 "${FLOW_TEST_DIR}/reorder-disks.py" > "$reordered" \
    || { warn "Could not render reordered domain XML."; return 1; }
  virsh define "$reordered" >/dev/null \
    || { warn "Could not define reordered domain."; return 1; }
}

# Boots the installed disk and waits for SEED_GENERATOR_FIRSTBOOT_MARKER on the
# serial console. Returns 0 if the marker appears within BOOT_TIMEOUT_SEC, 125
# otherwise (distinct from installer exit codes and the 124 timeout).
_run_boot_verify() {
  section "Verifying installed system boots (timeout: ${BOOT_TIMEOUT_SEC}s)"
  _vm_eject_cdroms
  _vm_running && virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
  if [[ "${VM_REORDER_BOOT_DISKS}" == "true" ]]; then
    _reorder_boot_disks \
      || warn "Disk reorder failed — boot uses the original disk order."
  fi

  info "Booting installed disk → ${BOOT_LOG_FILE}"
  virsh start "$VM_NAME" >/dev/null
  _wait_for_serial_pty
  _start_console_capture "$BOOT_LOG_FILE"
  _start_console_answerer

  # Session-login profiles self-reboot through each desktop and finish on
  # ===SESSION-VERIFY-DONE===; plain profiles finish on the first-boot sentinel.
  local wait_marker="$SEED_GENERATOR_FIRSTBOOT_MARKER"
  [[ -n "${VM_VERIFY_SESSIONS[*]:-}" ]] && wait_marker="===SESSION-VERIFY-DONE==="

  local brc=0
  set +e
  sentinel_watcher_wait_marker \
    "$BOOT_LOG_FILE" "$wait_marker" "$BOOT_TIMEOUT_SEC"
  brc=$?
  set -e

  _stop_console_answerer
  _stop_console_capture
  _vm_running && virsh destroy "$VM_NAME" >/dev/null 2>&1 || true

  ((brc == 0)) || return 125

  # Per-desktop LOGIN assertion (ADR 0062): the prober logged into each session
  # and emitted its OK marker before DONE. A missing/FAIL marker means a desktop
  # could not be logged into — fail with a distinct code (126).
  local _sde _sok
  for _sde in "${VM_VERIFY_SESSIONS[@]:-}"; do
    [[ -n "$_sde" ]] || continue
    _sok="$(_seed_generator_session_marker "$_sde")"
    if [[ -z "$_sok" ]] || ! grep -Fq -- "$_sok" "$BOOT_LOG_FILE"; then
      warn "Session login verify FAILED: '${_sde}' (${_sok:-?}) — did not log in."
      return 126
    fi
    info "Session login verify OK: '${_sde}' (${_sok})."
  done

  # Per-desktop assertion (ADR 0062): the first-boot sentinel echoed each
  # requested desktop's OK/FAIL marker before FIRSTBOOT-OK. Require every one's
  # OK marker on the captured console — a missing/FAIL marker fails boot-verify
  # with a distinct code (126) so a desktop regression is never a silent pass.
  local _de _ok
  for _de in "${VM_VERIFY_DESKTOPS[@]:-}"; do
    [[ -n "$_de" ]] || continue
    _ok="$(_seed_generator_desktop_marker "$_de")"
    if [[ -z "$_ok" ]] || ! grep -Fq -- "$_ok" "$BOOT_LOG_FILE"; then
      warn "Desktop verify FAILED: '${_de}' (${_ok:-unknown marker}) absent."
      return 126
    fi
    info "Desktop verify OK: '${_de}' (${_ok})."
  done
  return 0
}

# =============================================================================
# ENTRY POINT
# =============================================================================
flow_test_deps() { _harness_ensure_deps script:util-linux; }

flow_run() {
  trap '_stop_console_answerer; _stop_console_capture; \
    _stop_fixture_http_server' EXIT
  trap '_on_signal 2'  INT
  trap '_on_signal 15' TERM

  flow_test_deps
  _ensure_libvirt_group
  _ensure_libvirtd
  _ensure_libvirt_reachable
  mkdir -p "$ISO_DIR" "$CACHE_DIR"

  # Secure profiles fetch the Test Age Key over HTTP during install; stand the
  # server up before the VM boots (no-op when no fixtures are declared).
  _start_fixture_http_server

  section "Resolving Arch ISO"
  local iso; iso="$(core_resolve_iso "$ISO_DIR")"

  section "Building cloud-init seed"
  local seed; seed="$(_flow_build_seed)"
  info "Seed: ${seed}"

  section "VM lifecycle"
  $RECREATE && _vm_destroy_undefine
  if _vm_exists; then
    local current_iso; current_iso="$(_vm_install_iso_path)"
    if [[ -n "$current_iso" && "$current_iso" != "$iso" ]]; then
      info "Existing VM points at stale ISO (${current_iso}); recreating."
      _vm_destroy_undefine
    fi
  fi
  _vm_exists || _vm_create "$iso" "$seed"
  _vm_boot

  section "Capturing installer log → ${LOG_FILE}"
  _wait_for_serial_pty
  _start_console_capture

  section "Waiting for installer (timeout: ${TIMEOUT_SEC}s)"
  local rc=0
  set +e
  sentinel_watcher_wait "$LOG_FILE" "$TIMEOUT_SEC"
  rc=$?
  set -e
  _stop_console_capture

  if   ((rc == 124)); then warn "Installer timed out after ${TIMEOUT_SEC}s."
  elif ((rc == 0));   then info "Installer completed successfully (exit 0)."
  else                     warn "Installer finished with exit code ${rc}."
  fi
  info "Log: ${LOG_FILE}"

  if ((rc == 0)) && [[ "$VERIFY_BOOT" == "true" ]]; then
    if _run_boot_verify; then
      info "Installed system reached the first-boot sentinel — boot OK."
    else
      warn "Installed system did NOT reach the first-boot sentinel" \
           "(boot failed or timed out after ${BOOT_TIMEOUT_SEC}s)."
      info "Boot log: ${BOOT_LOG_FILE}"
      rc=125
    fi
  fi

  # Hold-on-fail (ADR 0099): a failed cell skipped its poweroff and gave ttyS0 a
  # root autologin shell, so it is left running for inspection over serial. Never
  # auto-destroyed — it IS the evidence; the user reaps it when done.
  if ((rc != 0)) && [[ "$HOLD_ON_FAIL" == "true" ]] && _vm_running; then
    section "Inspect the failed cell (VM held up)"
    info "Cell failed (exit ${rc}) — the VM is left running for inspection."
    info "Serial console:  virsh console ${VM_NAME}" \
         "  (root autologin; Ctrl-] to exit)"
    info "Install log (host copy): ${LOG_FILE}"
    info "Clean up when done:  virsh destroy ${VM_NAME} &&" \
         "virsh undefine --nvram ${VM_NAME}"
  fi

  exit "$rc"
}
