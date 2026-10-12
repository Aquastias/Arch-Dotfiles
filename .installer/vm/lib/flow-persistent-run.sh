#!/usr/bin/env bash
# =============================================================================
# vm/lib/flow-persistent-run.sh — the persistent flow's entry points
# =============================================================================
# flow_run (install a VM through the live ISO and boot it) and --rescue (boot an
# existing VM back into the live ISO), built on lib/flow-persistent.sh.
#
# Used by: vm/lib/flow-persistent.sh (sources it), vm/vm.sh.
# =============================================================================

vm_flow_persistent_dependencies() {
  _core_ensure_dependencies nc:openbsd-netcat socat:socat ssh-keygen:openssh \
    script:util-linux
}

# _flow_persistent_prepare — the toolchain, libvirt, cache dirs and harness key.
_flow_persistent_prepare() {
  vm_flow_persistent_dependencies
  _core_ensure_libvirt_group
  _core_ensure_libvirtd
  _core_ensure_libvirt_reachable
  mkdir -p "$ISO_DIR" "$CACHE_DIR"
  _flow_persistent_ensure_key
}

flow_run() {
  trap '_core_stop_console_capture; _flow_persistent_stop_http_server' EXIT
  _flow_persistent_prepare
  repo_source_resolve
  # Primary user (users[0]) owns the authorized harness key + the ssh command.
  PRIMARY_USER="$(jq -r '.users[0] // "aquastias"' \
    <<<"${INSTALL_CONFIG_CONTENT}")"

  section "Resolving Arch ISO"
  local iso; iso="$(vm_resolve_iso "$ISO_DIR")"

  section "Building seed CDROM"
  # The seed authorizes this key on the live ISO + sets up serial autologin, so
  # both inspection channels are up at boot regardless of the installer (0099).
  local public_key; public_key="$(cat "$(_flow_persistent_key_path).pub")"
  local seed; seed="$(_flow_build_seed "$public_key")"
  info "Seed: ${seed}"

  _flow_persistent_bring_up_vm "$iso" "$seed"

  section "Waiting for live system"
  local vm_ip; vm_ip="$(_flow_persistent_get_vm_ip)"
  info "VM IP: ${vm_ip}"
  _flow_persistent_wait_for_ssh "$vm_ip"

  local install_rc=0
  _flow_persistent_run_installer "$vm_ip"
  if ((install_rc != 0)); then
    _flow_persistent_hold_failed_install "$install_rc"
    return 0
  fi
  _flow_persistent_boot_installed
}

# _flow_persistent_bring_up_vm <iso> <seed> — (re)create the domain when it is
# missing, recreated on request, or points at a stale ISO; then boot it.
_flow_persistent_bring_up_vm() {
  local iso="$1" seed="$2"
  section "VM lifecycle"
  $RECREATE && _core_vm_destroy_undefine
  if _core_vm_exists; then
    local current_iso; current_iso="$(_core_vm_install_iso_path)"
    if [[ -n "$current_iso" && "$current_iso" != "$iso" ]]; then
      info "Existing VM points at stale ISO (${current_iso}); recreating."
      _core_vm_destroy_undefine
    fi
  fi
  _core_refresh_pool_for_path "$iso"
  _core_refresh_pool_for_path "$seed"
  _core_vm_exists || _core_vm_create "$iso" "$seed"
  _core_vm_boot
}

# _flow_persistent_run_installer <vm-ip> — launch the installer and wait for its
# exit sentinel; sets the caller's install_rc (124 = timeout).
_flow_persistent_run_installer() {
  local vm_ip="$1"
  _core_stage_fixture_files
  section "Launching installer"
  # Capture serial so we can read the exit sentinel: the sentinel is one line
  # (safe on serial); the pacman-heavy install log stays a FILE. This lets us
  # tell a failed install from a hang and hold the VM for inspection (ADR 0099).
  local console_log="${CACHE_DIR}/${VM_NAME}-console.log"
  _core_wait_for_serial_pty
  _core_start_console_capture "$console_log"
  _flow_persistent_launch_installer

  section "Waiting for installer to complete"
  info "Watching for the installer exit sentinel" \
       "(max ${INSTALL_TIMEOUT_SEC}s — install takes 10-30 min)."
  set +e
  vm_sentinel_watcher_wait "$console_log" "$INSTALL_TIMEOUT_SEC"
  install_rc=$?
  set -e
  _core_stop_console_capture
  _flow_persistent_stop_http_server
  [[ -n "${VM_ARTIFACT_DIR:-}" ]] \
    && _flow_persistent_export_install_artifacts "$vm_ip" "$install_rc" \
      "$console_log"
  return 0
}

# _flow_persistent_hold_failed_install <rc> — failure (installer exit N) or
# timeout (124): HOLD the live ISO up. Never eject/reboot — that would discard
# the evidence — and never auto-destroy.
_flow_persistent_hold_failed_install() {
  local rc="$1"
  if ((rc == 124)); then
    warn "Installer did not finish within ${INSTALL_TIMEOUT_SEC}s" \
         "— holding the VM for inspection."
  else
    warn "Installer FAILED (exit ${rc}) — holding the VM for inspection."
  fi
  _flow_persistent_report_failure_access
}

# _flow_persistent_boot_installed — after the success sentinel: wait for the
# payload's power-off, eject the media and boot the installed disk.
_flow_persistent_boot_installed() {
  info "Installer completed successfully (exit 0)."
  # The payload powers off after the success sentinel; wait for it so the reboot
  # lands cleanly on the installed disk.
  _flow_persistent_wait_for_poweroff

  section "Starting installed system"
  # Eject the install ISO + seed so the reboot lands on the installed disk's
  # systemd-boot entry, not the live ISO (the domain boots --boot cdrom,hd).
  _core_vm_eject_cdroms
  # Feature Audit boots the installed system itself, with its own serial
  # capture + unlock answerer, so the first boot is observed (ADR 0152).
  [[ -n "${VM_SKIP_FINAL_BOOT:-}" ]] && return 0
  _core_vm_boot

  _flow_persistent_report_ssh_access

  section "Done"
  info "VM '${VM_NAME}' is booting into the installed system."
  info "Open virt-manager and connect to '${VM_NAME}'."
  info "Login: ${PRIMARY_USER} / 12345  (or root / 12345)"
}

# --rescue: re-attach the install ISO + a fresh access seed to an EXISTING VM
# and boot it back into the live ISO, so a system that installed but won't boot
# can be inspected — SSH/serial reach the live env (ticket 01's channels) and
# the half-installed pool can be imported (ADR 0099). Does not reinstall or
# touch the installed disk.
vm_flow_persistent_rescue() {
  trap '_core_stop_console_capture; _flow_persistent_stop_http_server' EXIT
  _flow_persistent_prepare
  _core_vm_exists || error "No VM '${VM_NAME}' to rescue — create one first."

  section "Resolving Arch ISO"
  local iso; iso="$(vm_resolve_iso "$ISO_DIR")"

  section "Rebuilding live-ISO access seed"
  local public_key; public_key="$(cat "$(_flow_persistent_key_path).pub")"
  local seed; seed="$(_flow_build_seed "$public_key")"
  _core_refresh_pool_for_path "$iso"
  _core_refresh_pool_for_path "$seed"

  section "Re-attaching install ISO + seed (rescue boot into live ISO)"
  _core_vm_insert_cdroms "$iso" "$seed"
  _core_vm_boot

  section "Waiting for live system"
  local vm_ip; vm_ip="$(_flow_persistent_get_vm_ip)"
  info "VM IP: ${vm_ip}"
  _flow_persistent_wait_for_ssh "$vm_ip"

  local key; key="$(_flow_persistent_key_path)"
  section "Rescue live ISO ready"
  info "SSH (live ISO):  ssh -i ${key}" \
       "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
       "root@${vm_ip}"
  info "Serial console:  virsh console ${VM_NAME}" \
       "  (root autologin; Ctrl-] to exit)"
  info "Inspect the half-installed pool, e.g.:" \
       "zpool import -f -N -R /mnt rpool && zfs mount rpool/ROOT/arch"
  info "When done, eject the ISO to boot the disk again:  vm.sh … (normal run)"
}
