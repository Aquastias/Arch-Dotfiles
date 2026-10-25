#!/usr/bin/env bash
# =============================================================================
# lib/seed-generator.sh — Cloud-init NoCloud seed-ISO builder
# =============================================================================
# Public:
#   vm_seed_generator_build REPO_URL HOSTNAME OUTPUT_DIR
#       Render a cloud-init `user-data` document parameterised by REPO_URL
#       and HOSTNAME, build a NoCloud `seed.iso` from it via cloud-localds,
#       and print the absolute path of the produced ISO on stdout.
#
#       The runcmd inside the user-data:
#         - cd into a clean clone of REPO_URL at /root/dotfiles
#         - patch install.jsonc's hostname to HOSTNAME
#         - run install.sh --unattended
#         - emit `===INSTALLER-EXIT-N===` to /dev/ttyS0
#         - sync and poweroff -f
#
#       The exact line `===INSTALLER-EXIT-N===` is the contract consumed by
#       lib/sentinel-watcher.sh on the host. Do not change the format.
#
#       Returns non-zero if `cloud-localds` is missing — the orchestrator,
#       not this module, is responsible for installing it.
#
# Test seam:
#   _seed_generator_render_user_data REPO_URL HOSTNAME
#       Echo the user-data document text without invoking cloud-localds.
#       Tests use this to assert substitution and runcmd shape without
#       requiring cloud-image-utils on the test host.
# =============================================================================

# ── Internal: render user-data text ───────────────────────────────────────────
#
# Two cloud-init mechanisms work together to make installer output reach the
# host's serial-console capture:
#
# 1. `output: {all: '| tee -a /dev/ttyS0'}` — routes cloud-init's own stdio
#    (including all runcmd output) to /dev/ttyS0 as well as the on-VM log.
#    Without this, runcmd output lands only in
#    /var/log/cloud-init-output.log inside the VM, where the host's
#    `virsh console` cannot see it.
#
# 2. A single multiline runcmd entry — each entry in cloud-init's runcmd list
#    is invoked in its own shell, so a lone `exec > /dev/ttyS0 2>&1` only
#    redirects that one shell. Bundling every step into one `|` block keeps
#    `cd`, `$rc`, and `set -ex` working as a normal script.

# Marker the test-only first-boot unit echoes to /dev/ttyS0 once the installed
# system boots. The host boot-verify phase waits for it via
# vm_sentinel_watcher_wait_marker. A hard contract like INSTALLER-EXIT — keep it
# in sync with vm/lib/flow-test.sh.
SEED_GENERATOR_FIRSTBOOT_MARKER='===FIRSTBOOT-OK==='

# _seed_generator_desktop_marker <de> — the OK sentinel tag for a desktop, the
# single source of truth shared by the sentinel writer (the firstboot check) and
# the host reader (flow-test.sh's per-desktop assertion). Empty for an unknown
# desktop.
_seed_generator_desktop_marker() {
  case "$1" in
  kde)      printf '===KDE-OK===' ;;
  hyprland) printf '===HYPR-OK===' ;;
  niri)     printf '===NIRI-OK===' ;;
  esac
}

# _seed_generator_desktop_check <de>... — a NO-single-quote shell snippet that,
# for each desktop, echoes its OK marker when that desktop's session-launch
# artifacts are present on the booted system, else ===<TAG>-FAIL===. Folded into
# the first-boot sentinel line (like user_check/extras_check), so a KDE+Hyprland
# install is proven to have produced a launchable session for EACH desktop —
# incl. the Hyprland /usr/local session override the extras adapter writes. No
# single quotes: the whole line is a single-quoted printf arg.
_seed_generator_desktop_check() {
  local desktop out="" ok tag
  for desktop in "$@"; do
    ok="$(_seed_generator_desktop_marker "$desktop")"; [[ -n "$ok" ]] \
      || continue
    tag="${ok#===}"; tag="${tag%-OK===}"
    case "$desktop" in
    kde)
      out+="if command -v startplasma-wayland > /dev/null 2>&1 && [ -f /usr/share/wayland-sessions/plasma.desktop ]; then echo ${ok}; else echo ===${tag}-FAIL===; fi; " ;;
    hyprland)
      out+="if command -v Hyprland > /dev/null 2>&1 && [ -f /usr/local/share/wayland-sessions/hyprland.desktop ]; then echo ${ok}; else echo ===${tag}-FAIL===; fi; " ;;
    niri)
      out+="if command -v niri > /dev/null 2>&1 && [ -e /usr/local/share/wayland-sessions/niri.desktop ]; then echo ${ok}; else echo ===${tag}-FAIL===; fi; " ;;
    esac
  done
  printf '%s' "$out"
}

# _seed_generator_session_tag <de> — the marker tag for a desktop's login proof
# (kde → KDE, hyprland → HYPR). The single source of truth shared by the writer
# (the state file the prober reads) and the host reader (the OK-marker assertion).
_seed_generator_session_tag() {
  case "$1" in
  kde)      printf 'KDE' ;;
  hyprland) printf 'HYPR' ;;
  niri)     printf 'NIRI' ;;
  umbriel)  printf 'UMBRIEL' ;;
  esac
}

# _seed_generator_session_file <de> — the SDDM Autologin Session= value (the
# wayland-sessions .desktop file) each desktop logs into. Plasma's Wayland
# session is plasma.desktop; the Hyprland adapter ships hyprland.desktop under
# /usr/local (SDDM scans it too).
_seed_generator_session_file() {
  case "$1" in
  kde)      printf 'plasma.desktop' ;;
  hyprland) printf 'hyprland.desktop' ;;
  niri)     printf 'niri.desktop' ;;
  umbriel)  printf 'umbriel.desktop' ;;
  esac
}

# _seed_generator_session_marker <de> — the OK sentinel the prober emits once a
# desktop's compositor is up. The host boot-verify asserts each requested
# desktop's marker on the serial console (login actually succeeded).
_seed_generator_session_marker() {
  local tag; tag="$(_seed_generator_session_tag "$1")"
  [[ -n "$tag" ]] && printf '===%s-SESSION-OK===' "$tag"
}

# _seed_generator_probe_markers <boot-log> — the wlroots polkit/idle (ADR 0100)
# and clipboard (ADR 0147) probe markers the desktop-verify prober emitted, one
# per line in log order. Recorded by the host, not asserted.
_seed_generator_probe_markers() {
  local marker_regex='===(NIRI|HYPR)-(POLKIT|IDLE|CLIPBOARD)-(OK|FAIL)'
  marker_regex+='( [a-z]+=[^ =]*)*==='
  grep -oE "$marker_regex" "$1" 2>/dev/null
  return 0
}

# The first-boot verification blocks.
# shellcheck source=./seed-generator-firstboot.sh
source "${BASH_SOURCE[0]%/*}/seed-generator-firstboot.sh"

_seed_generator_render_user_data() {
  local repo_url="$1" hostname="$2"
  local dirty_cache="${3:-false}" verify_boot="${4:-false}"

  # Optional: corrupt the live ISO's zpool.cache before the installer runs, to
  # reproduce the dirty-ISO condition the per-pool seeding fix must survive.
  # Chained with && so a write failure still short-circuits into the sentinel.
  local dirty_step=""
  [[ "$dirty_cache" == "true" ]] && \
    dirty_step='mkdir -p /etc/zfs && printf %s garbage-not-an-nvlist'
  [[ -n "$dirty_step" ]] && \
    dirty_step="${dirty_step} > /etc/zfs/zpool.cache && "

  # Optional: inject the first-boot sentinel unit after a successful install.
  local boot_block=""
  [[ "$verify_boot" == "true" ]] && \
    boot_block="$(_seed_generator_firstboot_block)"

  cat <<EOF
#cloud-config
# Generated by .installer/lib/seed-generator.sh — do not edit by hand.
# Consumed by archiso's NoCloud datasource on first boot.
# set -e is intentionally OFF: a setup-step failure under it would abort
# this shell before the sentinel + poweroff path runs, leaving the host
# harness to wait the full timeout. The chain below short-circuits on
# first failure; rc captures the failed step's exit code; the sentinel is
# always emitted; the VM always powers off. set -x keeps traceability.
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && cd /root/dotfiles/.installer$(_seed_generator_env_exports chain) \\
        && sed -i \
  's|"hostname"[[:space:]]*:[[:space:]]*"[^"]*"|"hostname": "${hostname}"|' \
  install.jsonc \\
        && ${dirty_step}./install.sh --unattended install.jsonc
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
    poweroff -f
EOF
}

# Render the GUIDED Installer cloud-init runcmd (issue 01b). Instead of
# injecting an install.jsonc and running install.sh positionally, this drives
# the Guided Installer headlessly: it resolves the install disk in-guest via
# the Pre-Install Picker (picker_enum_disks — pure bash, no jq, so it works
# before 01-bootstrap), writes a replay answers file (hostname / disk /
# INSTALL), and runs `install.sh --guided`. The shell replays the answers
# through guided_select/guided_prompt — no fzf, no tty — and assembles the same
# single-disk Effective Config. The firstboot block + sentinel + poweroff are
# shared with the non-guided renderer. Test-only — never production.
# Args: <repo_url> <hostname> [dirty_cache] [verify_boot] [encryption]
#       [impermanence]. encryption/impermanence "true" append the matching guided
# answer (so the replayed menu sets them). Unlike the non-guided renderer, this
# does NOT preset INSTALL_ENC_PASSPHRASE (ADR 0059): the guided menu authors the
# Secrets Manifest itself, and presetting it would shadow that path and leave it
# untested. The encrypted pool is created from the menu's own passphrase.
_seed_generator_render_guided_user_data() {
  local repo_url="$1" hostname="$2"
  local dirty_cache="${3:-false}" verify_boot="${4:-false}"
  local encryption="${5:-false}" impermanence="${6:-false}"
  local layout="${7:-single}" disk_count="${8:-1}" guided_user="${9:-}"
  local guided_extras="${10:-}" bind_devices="${11:-false}"
  local manual="${12:-false}"

  local dirty_step=""
  [[ "$dirty_cache" == "true" ]] && \
    dirty_step='mkdir -p /etc/zfs && printf %s garbage-not-an-nvlist'
  [[ -n "$dirty_step" ]] && \
    dirty_step="${dirty_step} > /etc/zfs/zpool.cache && "

  # Extra guided answers replayed before INSTALL. NB: unlike the non-guided
  # flow, the guided run does NOT preset INSTALL_ENC_PASSPHRASE (ADR 0059). That
  # preset is the highest precedence tier, so it would shadow the Secrets
  # Manifest and leave the menu's own passphrase path (manifest →
  # zfs_collect_encryption_passphrase → zpool create) untested. The guided menu authors the
  # manifest itself (unset → the 8-char default), so the encrypted pool is
  # created from the value the menu produces — the point of a guided smoke run.
  # Single backslash: these are substituted into the heredoc as-is (heredoc
  # backslash processing applies only to its literal text), so the guest's
  # printf sees `\n` and writes one answer per line.
  local extra_answers=""
  [[ "$encryption" == "true" ]] && extra_answers+='encryption=true\n'
  [[ "$impermanence" == "true" ]] && extra_answers+='impermanence=true\n'

  local verify_user="" verify_extras="" disk_step
  _seed_generator_guided_user_answers "$guided_user"
  _seed_generator_guided_extras_answers "$guided_extras"
  # A blank guided session presets no user and refuses to install without one
  # (ADR 0157): a replay naming none picks the neutral committed `stock` user.
  [[ "$extra_answers" == *new_user_name=* || "$extra_answers" == *users=* ]] \
    || extra_answers+='users=stock\n'
  _seed_generator_guided_disk_step

  local boot_block=""
  [[ "$verify_boot" == "true" ]] && \
    boot_block="$(_seed_generator_firstboot_block "$verify_user" "$verify_extras")"

  cat <<EOF
#cloud-config
# Generated by .installer/lib/seed-generator.sh (guided) — do not edit by hand.
# Drives the Guided Installer headlessly: resolve the install disk(s) in-guest
# via the Pre-Install Picker, write a replay answers file, run install.sh
# --guided. set -e is intentionally OFF (see the non-guided renderer for why).
output: {all: '| tee -a /dev/ttyS0'}
runcmd:
  - |
    set +e
    set -x
    {
      pacman -Sy --noconfirm --needed git \\
        && rm -rf /root/dotfiles \\
        && git clone ${repo_url} /root/dotfiles \\
        && cd /root/dotfiles/.installer$(_seed_generator_env_exports chain) \\
        ${disk_step} \\
        && cat /root/guided-answers \\
        && ${dirty_step}./install.sh --guided /root/guided-answers
    }
    rc=\$?
${boot_block}
    printf '===INSTALLER-EXIT-%d===\n' "\$rc" > /dev/ttyS0
    sync
    poweroff -f
EOF
}

# _seed_generator_guided_user_answers <guided-user-json> — append the
# create-user answers to the caller's extra_answers; set its verify_user.
_seed_generator_guided_user_answers() {
  local guided_user="$1"
  # Ad-hoc user + passwords (issue 07): when the profile names a guided_user,
  # replay the create-user form keys + the root password so the guided menu
  # authors the user and the no-SOPS injector sets both passwords. verify_user
  # drives the USER-OK boot check below.
  if [[ -n "$guided_user" && "$guided_user" != "null" ]]; then
    local user_name user_password user_sudo user_shell root_password
    user_name="$(jq -r '.name // empty' <<<"$guided_user")"
    user_password="$(jq -r '.password // "12345"' <<<"$guided_user")"
    user_sudo="$(jq -r '.sudo // false' <<<"$guided_user")"
    user_shell="$(jq -r '.shell // "/bin/bash"' <<<"$guided_user")"
    root_password="$(jq -r '.root_password // empty' <<<"$guided_user")"
    extra_answers+="new_user_name=${user_name}\\n"
    extra_answers+="new_user_shell=${user_shell}\\n"
    extra_answers+="new_user_sudo=${user_sudo}\\n"
    extra_answers+="new_user_password=${user_password}\\n"
    [[ -n "$root_password" ]] \
      && extra_answers+="root_password=${root_password}\\n"
    verify_user="$user_name"
  fi
}

# _seed_generator_guided_extras_answers <guided-extras-json> — append the
# Security & Backup Extras answers to the caller's extra_answers; set its
# verify_extras.
_seed_generator_guided_extras_answers() {
  local guided_extras="$1"
  # Security & Backup Extras smoke (issue 04/05): guided_extras re-picks a
  # minimal committed user (users=…, so users[0] is light, not aquastias's full
  # set), replays toggle overrides (answers: e.g. borg=false), and names the
  # daemons the boot-verify must find enabled (verify[] → EXTRAS-OK/FAIL).
  if [[ -n "$guided_extras" && "$guided_extras" != "null" ]]; then
    local extras_users extras_verify
    extras_users="$(jq -r '.users // empty' <<<"$guided_extras")"
    [[ -n "$extras_users" ]] && extra_answers+="users=${extras_users}\\n"
    while IFS= read -r _kv; do
      [[ -n "$_kv" ]] && extra_answers+="${_kv}\\n"
    done < <(jq -r '(.answers // {}) | to_entries[] | "\(.key)=\(.value)"' \
      <<<"$guided_extras")
    extras_verify="$(jq -r '(.verify // []) | join(" ")' <<<"$guided_extras")"
    verify_extras="$extras_verify"
  fi
}

# _seed_generator_guided_disk_step — set the caller's disk_step from its
# manual/layout/bind_devices/disk_count/hostname/extra_answers.
_seed_generator_guided_disk_step() {
  # The disk-resolution + answers-file step differs by layout. Built in its own
  # heredoc so the \$ / \\n / \\ escapes are processed identically to the outer
  # one, then embedded verbatim. single resolves one disk (disk=); a multi
  # preset resolves N disks (head -N), replays the layout + a whitespace device
  # list (disks=), and gates on a typed ACCEPT.
  local picker='source lib/picker.sh; source lib/live-medium.sh; set +e'
  if [[ "$manual" == "true" ]]; then
    # Manual Partitioning case (ADR 0073): script the table the operator would
    # draw in cfdisk — ESP, swap, root (partlabel `root`, which the boot-verify
    # block mounts) — then replay manual_disk so the menu scans and assigns it.
    disk_step="$(cat <<EOF
&& GUIDED_DISK="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" \\
             | head -1)" \\
        && sgdisk --zap-all "\$GUIDED_DISK" \\
        && sgdisk -n1:0:+1G -t1:ef00 -c1:esp -n2:0:+2G -t2:8200 -c2:swap \\
             -n3:0:0 -t3:8300 -c3:root "\$GUIDED_DISK" \\
        && udevadm settle \\
        && printf 'hostname=%s\\nmanual_disk=%s\\n' \\
             '${hostname}' "\$GUIDED_DISK" > /root/guided-answers \\
        && printf '${extra_answers}confirm=INSTALL\\n' >> /root/guided-answers
EOF
)"
  elif [[ "$layout" != "single" && "$bind_devices" == "true" ]]; then
    # In-Menu Disk Binding replay (ADR 0047, issue 07): bind ALL resolved disks
    # to the OS pool via os_pool_devices — the bound assignment path (issue 04)
    # runs with no summed flat pick and no ACCEPT. Representative bound cell:
    # os-mirror (both disks in the OS pool).
    disk_step="$(cat <<EOF
&& GUIDED_DISKS="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" | head -${disk_count} | tr '\\n' ' ')" \\
        && printf 'hostname=%s\\nlayout=${layout}\\nos_pool_devices=%s\\n${extra_answers}confirm=INSTALL\\n' '${hostname}' "\$GUIDED_DISKS" > /root/guided-answers
EOF
)"
  elif [[ "$layout" != "single" ]]; then
    disk_step="$(cat <<EOF
&& GUIDED_DISKS="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" | head -${disk_count} | tr '\\n' ' ')" \\
        && printf 'hostname=%s\\nlayout=${layout}\\ndisks=%s\\naccept_layout=ACCEPT\\n${extra_answers}confirm=INSTALL\\n' '${hostname}' "\$GUIDED_DISKS" > /root/guided-answers
EOF
)"
  else
    disk_step="$(cat <<EOF
&& GUIDED_DISK="\$(${picker}; picker_enum_disks "\$(live_medium_disks)" | head -1)" \\
        && printf 'hostname=%s\\ndisk=%s\\n${extra_answers}confirm=INSTALL\\n' '${hostname}' "\$GUIDED_DISK" > /root/guided-answers
EOF
)"
  fi
}

# ── Public API ────────────────────────────────────────────────────────────────

vm_seed_generator_build() {
  local repo_url="$1" hostname="$2" output_directory="$3"

  [[ -n "$repo_url" ]] || {
    echo "seed-generator: REPO_URL is empty" >&2
    return 1
  }
  [[ -n "$hostname" ]] || {
    echo "seed-generator: HOSTNAME is empty" >&2
    return 1
  }
  [[ -d "$output_directory" ]] || {
    echo \
      "seed-generator: output directory does not exist: $output_directory" >&2
    return 1
  }

  command -v cloud-localds >/dev/null 2>&1 || {
    echo "seed-generator: cloud-localds not found —" \
         "install cloud-image-utils" >&2
    return 1
  }

  local user_data="${output_directory%/}/user-data"
  local seed_iso="${output_directory%/}/seed.iso"

  _seed_generator_render_user_data "$repo_url" "$hostname" > "$user_data"

  cloud-localds "$seed_iso" "$user_data" >/dev/null || {
    echo "seed-generator: cloud-localds failed for $user_data" >&2
    return 1
  }

  [[ -s "$seed_iso" ]] || {
    echo "seed-generator: cloud-localds produced no output at $seed_iso" >&2
    return 1
  }

  printf '%s\n' "$seed_iso"
}

# _seed_generator_env_exports <plain|chain> — the harness's extra test-only
# install env (VM_INSTALL_ENV, space-separated K=V; e.g. the Feature Audit's
# Audit Cache, ADR 0152) as the generated script's exports: `plain` lines,
# or inline ` && export` links appended to an `&&` install chain.
_seed_generator_env_exports() {
  local assignment
  for assignment in ${VM_INSTALL_ENV:-}; do
    case "$1" in
      plain) printf "export %s='%s'\n" "${assignment%%=*}" "${assignment#*=}" ;;
      chain) printf " && export %s='%s'" "${assignment%%=*}" \
        "${assignment#*=}" ;;
    esac
  done
}
