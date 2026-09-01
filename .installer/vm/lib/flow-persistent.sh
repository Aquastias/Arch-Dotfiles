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

# Per-flow virt-install graphics (core._vm_create appends these). niri (and any
# Wayland compositor) REJECTS software EGL — a display-only virtio-gpu renders a
# black screen. So give the guest a virgl 3D device (hardware EGL) via spice-gl
# when the host has a DRM render node; else fall back to display-only (a
# headless/no-GPU host still builds, sans an interactive Wayland desktop).
_persist_render_node() {
  local n
  for n in "${VM_RENDER_NODE:-}" /dev/dri/renderD*; do
    [[ -n "$n" && -e "$n" ]] && { printf '%s\n' "$n"; return 0; }
  done
  return 1
}
if _rnode="$(_persist_render_node)"; then
  # shellcheck disable=SC2054 # each --graphics value is one virt-install arg
  FLOW_GRAPHICS_ARGS=(
    --video model.type=virtio,model.acceleration.accel3d=on
    --graphics "spice,listen=none,gl.enable=on,gl.rendernode=${_rnode}"
    --channel spicevmc)
else
  warn "No DRM render node — VM gets a display-only GPU (no Wayland desktop)."
  # shellcheck disable=SC2054 # spice,listen=none is one virt-install argument
  FLOW_GRAPHICS_ARGS=(--graphics spice,listen=none --video virtio \
                      --channel spicevmc)
fi

# Flow defaults (env overrides win; timeouts also resolved env>profile>here).
: "${CACHE_DIR:=${FLOW_PERSIST_DIR%/lib}/.vm-cache}"
: "${HTTP_PORT:=9876}"
: "${BOOT_TIMEOUT_SEC:=300}"
: "${INSTALL_TIMEOUT_SEC:=3600}"

_HTTP_PID=""

# =============================================================================
# HARNESS SSH KEY — local-only debug key the host uses to enter the guest
# =============================================================================
# Persistent VMs enable sshd + authorize this key so the host (and an agent
# driving it) can SSH in to diagnose the installed desktop. The key lives under
# the git-ignored .vm-cache; generate it on first use so a fresh checkout is
# self-contained. Never a production install artifact.
_harness_key_path() { printf '%s\n' "${CACHE_DIR}/harness_ed25519"; }

_harness_ensure_key() {
  local key; key="$(_harness_key_path)"
  [[ -f "$key" && -f "${key}.pub" ]] && return 0
  command_exists ssh-keygen || error "ssh-keygen not found — install openssh."
  info "Generating harness SSH key at ${key}."
  ssh-keygen -t ed25519 -N '' -C arch-vm-harness -f "$key" >/dev/null
}

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
  local repo_url="$1" pubkey="$2" primary_user="${3:-aquastias}" config_b64
  config_b64="$(printf '%s' "${INSTALL_CONFIG_CONTENT}" | base64 -w 0)"
  cat <<EOF
#!/usr/bin/env bash
set -euo pipefail
set -x
pacman-key --init
pacman-key --populate archlinux
# jq patches the config (below) before the installer's own toolchain preflight.
pacman -Sy --noconfirm --needed git jq
rm -rf /root/dotfiles
git clone ${repo_url} /root/dotfiles
printf '%s' '${config_b64}' | base64 -d > /root/dotfiles/.installer/install.jsonc
cd /root/dotfiles/.installer
# Persistent debug VMs only: enable sshd + authorize the harness key so the host
# can SSH into the installed guest to diagnose the desktop. The clone is
# disposable, so patching the committed profile in place never leaks upstream.
jq '.options.ssh.enabled = true' install.jsonc > install.jsonc.n \\
  && mv install.jsonc.n install.jsonc
source lib/jsonc.sh
_uprof="users/${primary_user}/profile.jsonc"
[[ -f "\$_uprof" ]] || _uprof="users/core/profile.jsonc"
jsonc_strip "\$_uprof" \\
  | jq --arg k '${pubkey}' \\
      '.ssh_authorized_keys = ((.ssh_authorized_keys // []) + [\$k])' \\
  > "\$_uprof.n" && mv "\$_uprof.n" "\$_uprof"
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
  local pubkey; pubkey="$(cat "$(_harness_key_path).pub")"
  _render_installer_script "${REPO_URL}" "$pubkey" "${PRIMARY_USER}" \
    > "${script}"

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
# Current DHCP lease of the domain's first NIC, or empty if none yet.
_vm_ip_now() {
  virsh domifaddr "$VM_NAME" 2>/dev/null \
    | awk 'NR>2 { split($4,a,"/"); if (a[1] ~ /^[0-9]/) print a[1] }' \
    | head -1
}

_get_vm_ip() {
  local elapsed=0 ip
  while true; do
    ip="$(_vm_ip_now)"
    [[ -n "$ip" ]] && { printf '%s\n' "$ip"; return 0; }
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && \
      error "Timed out waiting for VM IP address."
  done
}

# Best-effort: wait for the installed guest's sshd, then print the ready-to-use
# ssh command. Never fatal — a slow boot or a GPU-less host that never reaches a
# lease must not fail an otherwise-successful install; it just prints guidance.
_report_ssh_access() {
  local key ip elapsed=0
  key="$(_harness_key_path)"
  info "Waiting for sshd on the installed guest (best-effort)."
  while :; do
    ip="$(_vm_ip_now)"
    [[ -n "$ip" ]] && nc -z "$ip" 22 >/dev/null 2>&1 && break
    sleep 5; elapsed=$((elapsed + 5))
    ((elapsed >= BOOT_TIMEOUT_SEC)) && {
      warn "Guest SSH not up yet — once it boots:"
      warn "  ssh -i ${key} ${PRIMARY_USER}@<guest-ip>"
      return 0
    }
  done
  section "SSH access"
  info "Guest IP: ${ip}"
  info "Connect:  ssh -i ${key}" \
       "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
       "${PRIMARY_USER}@${ip}"
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
flow_persistent_deps() {
  _harness_ensure_deps nc:openbsd-netcat python3:python ssh-keygen:openssh
}

flow_run() {
  trap '_stop_http_server' EXIT
  flow_persistent_deps
  _ensure_libvirt_group
  _ensure_libvirtd
  mkdir -p "$ISO_DIR" "$CACHE_DIR"
  _harness_ensure_key
  # Primary user (users[0]) owns the authorized harness key + the ssh command.
  PRIMARY_USER="$(jq -r '.users[0] // "aquastias"' \
    <<<"${INSTALL_CONFIG_CONTENT}")"

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

  _report_ssh_access

  section "Done"
  info "VM '${VM_NAME}' is booting into the installed system."
  info "Open virt-manager and connect to '${VM_NAME}'."
  info "Login: ${PRIMARY_USER} / 12345  (or root / 12345)"
}
