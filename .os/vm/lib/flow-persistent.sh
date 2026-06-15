#!/usr/bin/env bash
# =============================================================================
# vm/lib/flow-persistent.sh — persistent VM flow (default, no --testing)
# =============================================================================
# Sourced by vm/vm.sh alongside core.sh. Builds a persistent, reusable libvirt
# VM: boots the Arch live ISO, serves the installer over HTTP on the libvirt
# gateway, types `curl …|bash` into the spice console via send-key, waits for
# the installer to power off, then reboots into the installed system for
# interactive use (virt-manager).
#
# Consumes (set by vm.sh): VM_NAME, VM_DISK_SIZES[], VM_RAM_MB, VM_VCPUS,
# INSTALL_CONFIG_CONTENT, VM_FIXTURE_FILES[], VM_SCRIPT_DIR, RECREATE.
# =============================================================================

FLOW_PERSIST_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# core.sh provides the shared host-side functions + defaults; guard-source so
# vm.sh sourcing core first does not double-source.
# shellcheck source=./core.sh
[[ "$(type -t core_resolve_iso)" == function ]] \
  || source "${FLOW_PERSIST_DIR}/core.sh"

# Per-flow virt-install graphics (core._vm_create appends these).
# shellcheck disable=SC2054 # spice,listen=none is one virt-install argument
FLOW_GRAPHICS_ARGS=(--graphics spice,listen=none --video virtio \
                    --channel spicevmc)

# Flow defaults (env overrides win; timeouts also resolved env>profile>here).
: "${CACHE_DIR:=${FLOW_PERSIST_DIR%/lib}/.vm-cache}"
: "${HTTP_PORT:=9876}"
: "${BOOT_TIMEOUT_SEC:=300}"
: "${INSTALL_TIMEOUT_SEC:=3600}"

_HTTP_PID=""

# =============================================================================
# SEED — empty cloud-config (NoCloud datasource only; installer runs via HTTP)
# =============================================================================
_flow_build_seed() {
  local user_data="${CACHE_DIR}/${VM_NAME}-user-data"
  local seed_iso="${CACHE_DIR}/${VM_NAME}-seed.iso"
  printf '#cloud-config\n' > "${user_data}"
  cloud-localds "${seed_iso}" "${user_data}" >/dev/null \
    || error "cloud-localds failed for ${user_data}"
  [[ -s "${seed_iso}" ]] || \
    error "cloud-localds produced empty seed at ${seed_iso}"
  printf '%s\n' "${seed_iso}"
}

# =============================================================================
# INSTALLER SCRIPT (served over HTTP, launched via send-key)
# =============================================================================
_render_installer_script() {
  local repo_url="$1" config_b64
  config_b64="$(printf '%s' "${INSTALL_CONFIG_CONTENT}" | base64 -w 0)"
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -x
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed git
rm -rf /root/dotfiles
git clone ${repo_url} /root/dotfiles
printf '%s' '${config_b64}' | base64 -d > /root/dotfiles/.os/install.jsonc
cd /root/dotfiles/.os
# Test-only preset passphrases so an encrypted/SOPS profile installs unattended
# (no-ops on profiles without encryption or secrets). Disposable VMs only.
export INSTALL_ENC_PASSPHRASE='testtest'
export SECRETS_AGE_PASSPHRASE='test'
./install.sh --unattended install.jsonc
sync
poweroff
EOF
}

# Map a single character to one or more virsh key names.
_char_to_keys() {
  case "$1" in
    [a-z]) printf 'KEY_%s'            "${1^^}" ;;
    [0-9]) printf 'KEY_%s'            "$1"     ;;
    ' ')   printf 'KEY_SPACE'                  ;;
    '.')   printf 'KEY_DOT'                    ;;
    '/')   printf 'KEY_SLASH'                  ;;
    '-')   printf 'KEY_MINUS'                  ;;
    ':')   printf 'KEY_LEFTSHIFT KEY_SEMICOLON' ;;
    '|')   printf 'KEY_LEFTSHIFT KEY_BACKSLASH' ;;
    *)     return 1 ;;
  esac
}

_type_into_console() {
  local vm="$1" text="$2" i char keys
  for ((i = 0; i < ${#text}; i++)); do
    char="${text:i:1}"
    if keys="$(_char_to_keys "$char")"; then
      # shellcheck disable=SC2086
      virsh send-key "$vm" $keys >/dev/null 2>&1
    else
      warn "virsh send-key: skipping unmapped character '${char}'"
    fi
    sleep 0.05
  done
  virsh send-key "$vm" KEY_ENTER >/dev/null 2>&1
}

_stop_http_server() {
  [[ -n "${_HTTP_PID}" ]] || return 0
  kill "${_HTTP_PID}" 2>/dev/null || true
  _HTTP_PID=""
}

_launch_installer() {
  local script="${CACHE_DIR}/run"
  _render_installer_script "${REPO_URL}" > "${script}"

  python3 -m http.server "${HTTP_PORT}" \
    --directory "${CACHE_DIR}" \
    --bind "${LIBVIRT_GATEWAY}" \
    >/dev/null 2>&1 &
  _HTTP_PID=$!

  local url="http://${LIBVIRT_GATEWAY}:${HTTP_PORT}/run"
  local cmd="curl -s ${url}|bash"
  info "Sending to console: ${cmd}"
  _type_into_console "${VM_NAME}" "${cmd}"
  info "Installer command sent — running inside VM."
}

# =============================================================================
# NETWORK / COMPLETION WAITS
# =============================================================================
_get_vm_ip() {
  local elapsed=0 ip
  while true; do
    ip="$(virsh domifaddr "$VM_NAME" 2>/dev/null \
          | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' \
          | head -1)"
    [[ -n "$ip" ]] && { printf '%s\n' "$ip"; return 0; }
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && \
      error "Timed out waiting for VM IP address."
  done
}

_wait_for_ssh() {
  local ip="$1" elapsed=0
  info "Waiting for live system to finish booting (SSH port on ${ip})."
  while ! nc -z "$ip" 22 >/dev/null 2>&1; do
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && \
      error "Timed out waiting for SSH on ${ip}."
  done
  sleep 5  # let tty1 auto-login settle
}

_wait_for_poweroff() {
  local elapsed=0
  info "Waiting for installer to finish" \
       "(max ${INSTALL_TIMEOUT_SEC}s — takes 10-30 min)."
  while _vm_running; do
    sleep 15; elapsed=$((elapsed + 15))
    ((elapsed >= INSTALL_TIMEOUT_SEC)) && \
      error "Installer timed out after ${INSTALL_TIMEOUT_SEC}s."
  done
  info "VM powered off — installer complete."
}

# =============================================================================
# ENTRY POINT
# =============================================================================
flow_persistent_deps() { _harness_ensure_deps nc:openbsd-netcat python3:python; }

flow_run() {
  trap '_stop_http_server' EXIT
  flow_persistent_deps
  _ensure_libvirt_group
  _ensure_libvirtd
  mkdir -p "$ISO_DIR" "$CACHE_DIR"

  section "Resolving Arch ISO"
  local iso; iso="$(core_resolve_iso "$ISO_DIR")"

  section "Building seed CDROM"
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
  _refresh_pool_for_path "$iso"
  _refresh_pool_for_path "$seed"
  _vm_exists || _vm_create "$iso" "$seed"
  _vm_boot

  section "Waiting for live system"
  local vm_ip; vm_ip="$(_get_vm_ip)"
  info "VM IP: ${vm_ip}"
  _wait_for_ssh "$vm_ip"

  _stage_fixture_files
  section "Launching installer"
  _launch_installer

  section "Waiting for installer to complete"
  _wait_for_poweroff
  _stop_http_server

  section "Starting installed system"
  # Eject the install ISO + seed so the reboot lands on the installed disk's
  # systemd-boot entry, not the live ISO (the domain boots --boot cdrom,hd).
  _vm_eject_cdroms
  _vm_boot

  section "Done"
  info "VM '${VM_NAME}' is booting into the installed system."
  info "Open virt-manager and connect to '${VM_NAME}'."
  info "Login: aquastias / 12345  (or root / 12345)"
}
