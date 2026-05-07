#!/usr/bin/env bash
# =============================================================================
# lib/config.sh — Configuration management
# =============================================================================
# Sourced by 03-install.sh.
# Requires: lib/common.sh already sourced.
#
# Provides:
#   generate_template  — writes a documented install.json template and exits
#   load_config        — validates the config file exists and is valid JSON
#   detect_mode        — sets INSTALL_MODE from config or auto-detects
#   validate_config    — checks all required fields and disk paths exist
#   print_summary      — prints the installation plan and asks for confirmation
#
# Adding a new mode:
#   1. add an entry to _CONFIG_MODE_SIG below (mode → defining JSON path),
#   2. add a per-mode validator: _validate_<mode>(),
#   3. drop a lib/layout-<mode>.sh implementing the layout interface.
# =============================================================================

# =============================================================================
# RESOLVED GLOBALS — set during validate_config, consumed by configure_system
# =============================================================================
RESOLVED_HOSTNAME=""

# =============================================================================
# MODE SIGNATURES — single source of truth for valid modes
# =============================================================================
# Each mode is defined by a "signature": a JSON path whose presence (and,
# for arrays, non-empty length) marks the config as belonging to that mode.
# detect_mode() picks a mode by signature; validate_config() dispatches to
# _validate_<mode>() for mode-specific checks.

declare -gA _CONFIG_MODE_SIG=(
  [single]=".disk"
  [multi]=".os_pool.disks"
)

# =============================================================================
# TEMPLATE GENERATOR
# =============================================================================
# Called when install.json is missing. Writes a fully commented template to
# the given path, then exits so the user can edit before re-running.

generate_template() {
  local target="$1"
  cat >"$target" <<'TEMPLATE'
{
  "_readme": "Arch Linux ZFS Installer config. Edit the ACTIVE CONFIG section, then run 03-install.sh.",

  "_MODE_HELP": {
    "single": "One disk — auto-partitioned: ESP + rpool (OS) + dpool (storage).",
    "multi":  "Multiple disks — OS pool (rpool) + optional storage groups (dpool).",
    "auto":   "Omit 'mode' to auto-detect: 'disk' key present → single; 'os_pool.disks' entries → multi."
  },

  "system": {
    "hostname": "",
    "_hostname": "Machine hostname. Leave empty to be prompted during install.",
    "locale":   "en_US.UTF-8",
    "timezone": "UTC",
    "keymap":   "us"
  },

  "_software_help": "Users and programs are declared under .os/hosts/<hostname>/ and .os/users/<name>/. See PRD.md.",

  "options": {
    "encryption":  false,
    "_encryption": "ZFS native AES-256-GCM on all pools. Passphrase prompted at install and at every boot.",
    "swap":        true,
    "swap_size":   "auto",
    "_swap_size":  "'auto' = RAM×2 (recommended). Fixed examples: '8G', '16G', '32G'.",
    "esp_size":    "512M",
    "_esp_size":   "EFI System Partition size per OS disk. 512M is sufficient for systemd-boot."
  },

  "packages": {
    "_help":  "All packages installed via pacstrap alongside the base system. Use exact pacman names.",
    "extra":  [],
    "_extra": "Flat list. Example: ['htop', 'firefox', 'vlc', 'neofetch']",
    "groups": {
      "cli":   [],
      "_cli":  "CLI tools. Example: ['tmux', 'bat', 'ripgrep', 'fzf', 'zsh', 'fish']",
      "dev":   [],
      "_dev":  "Dev tools. Example: ['python', 'nodejs', 'npm', 'docker', 'go', 'rustup']",
      "gui":   [],
      "_gui":  "GUI apps (pair with post_install.kde=true). Example: ['firefox', 'vlc', 'gimp']"
    }
  },

  "post_install": {
    "_help":      "Set true to run the matching extras/ script inside chroot at the end of install.",
    "desktop": {
      "kde": false,
      "_kde":       "extras/kde.sh — KDE Plasma 6, SDDM, PipeWire audio, Bluetooth, Avahi, printing.",
    "backup":     false,
    "_backup":    "extras/backup.sh — zfs-auto-snapshot (scheduled snapshots) + Borg/Vorta backups.",
    "security":   false,
    "_security":  "extras/security.sh — UFW firewall (deny-all-in) + ClamAV weekly scan."
  },

  "_SINGLE_DISK_EXAMPLE": {
    "_info":             "Laptop or single-disk desktop. The disk is split automatically.",
    "mode":              "single",
    "disk":              "/dev/sda",
    "ashift":            12,
    "_ashift":           "12 = 4K sectors (SATA SSD/HDD). 13 = 8K (NVMe, optional).",
    "os_size":           "auto",
    "_os_size":          "'auto' = max(20% of disk, RAM×2+30GiB, 40GiB floor). Fixed: '80G', '120G'.",
    "os_pool_name":      "rpool",
    "storage_pool_name": "dpool",
    "storage_mount":     "/data"
  },

  "_MULTI_MIRROR_EXAMPLE": {
    "_info":   "2 NVMes mirrored for OS. 3 SSDs as raidz1 storage.",
    "mode":    "multi",
    "os_pool": {
      "pool_name": "rpool",
      "topology":  "mirror",
      "_topology": "mirror | stripe | none | (omit → prompted at runtime)",
      "ashift":    13,
      "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
    },
    "storage_groups": [
      {
        "name":      "ssd",
        "mount":     "/data/ssd",
        "ashift":    12,
        "topology":  "raidz1",
        "_topology": "mirror | stripe | raidz1 | raidz2 | independent | (omit → prompted)",
        "disks":     ["/dev/sda", "/dev/sdb", "/dev/sdc"]
      }
    ]
  },

  "_MULTI_NO_RAID_EXAMPLE": {
    "_info":   "2 NVMes listed; topology=none → pick one for OS at runtime, other joins dpool.",
    "mode":    "multi",
    "os_pool": {
      "pool_name": "rpool",
      "topology":  "none",
      "ashift":    13,
      "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
    },
    "storage_groups": [
      { "name": "ssd", "mount": "/data/ssd", "ashift": 12,
        "disks": ["/dev/sda", "/dev/sdb", "/dev/sdc"] }
    ]
  },

  "=== ACTIVE CONFIG — edit below, leave examples above as reference ===": "",

  "mode":  "single",
  "disk":  "/dev/sda",
  "ashift": 12,
  "os_size": "auto",
  "os_pool_name":      "rpool",
  "storage_pool_name": "dpool",
  "storage_mount":     "/data",

  "os_pool": {
    "pool_name": "rpool",
    "ashift":    13,
    "disks":     ["/dev/nvme0n1", "/dev/nvme1n1"]
  },

  "storage_groups": []
}
TEMPLATE
  info "Template written to: ${target}"
}

# =============================================================================
# CONFIG LOADING
# =============================================================================

load_config() {
  section "Loading Configuration"
  if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "Config not found: $CONFIG_FILE"
    generate_template "$CONFIG_FILE"
    echo -e "\n  Edit the config, then re-run:\n" \
      "   ${DIM}vim ${CONFIG_FILE}${NC}\n" \
      "   ${DIM}./03-install.sh${NC}\n"
    exit 0
  fi
  command -v jq &>/dev/null || error "'jq' not found. Run 01-bootstrap-zfs.sh first."
  jsonc "$CONFIG_FILE" | jq empty 2>/dev/null || error "Invalid JSON: $CONFIG_FILE"
  info "Loaded: $CONFIG_FILE"
}

# =============================================================================
# MODE DETECTION
# =============================================================================
# Picks the mode by signature presence in the config. Each mode in
# _CONFIG_MODE_SIG defines a JSON path whose presence (or non-empty length,
# for paths ending in .disks) selects that mode.

# Returns 0 if the given mode's signature is satisfied by the current config.
_config_mode_matches() {
  local mode="$1"
  local sig="${_CONFIG_MODE_SIG[$mode]:-}"
  [[ -n "$sig" ]] || return 1

  if [[ "$sig" == *.disks ]]; then
    local cnt
    cnt="$(jsonc "$CONFIG_FILE" | jq "${sig} | length // 0")"
    ((cnt >= 1))
  else
    local v
    v="$(cfgo "$sig")"
    [[ -n "$v" ]]
  fi
}

detect_mode() {
  section "Detecting Install Mode"

  local cfg_mode
  cfg_mode="$(cfgo '.mode')"

  if [[ -n "$cfg_mode" ]]; then
    [[ -v "_CONFIG_MODE_SIG[$cfg_mode]" ]] ||
      error "Unknown mode '${cfg_mode}'. Valid: ${!_CONFIG_MODE_SIG[*]}."
    INSTALL_MODE="$cfg_mode"
    info "Mode from config: ${INSTALL_MODE}"
    return
  fi

  # Auto-detect: pick the first mode whose signature is satisfied. Order is
  # significant; iterate the keys deterministically (sorted) so single beats
  # multi when both signatures could plausibly match.
  local m
  for m in $(echo "${!_CONFIG_MODE_SIG[@]}" | tr ' ' '\n' | sort); do
    if _config_mode_matches "$m"; then
      INSTALL_MODE="$m"
      info "Auto-detected mode: ${INSTALL_MODE}"
      return
    fi
  done

  error "Cannot auto-detect mode. Set 'mode' to one of: ${!_CONFIG_MODE_SIG[*]}."
}

# =============================================================================
# VALIDATION
# =============================================================================

# System fields required regardless of mode. Prompts for hostname if blank,
# validates it against RFC 1123, and stores it in RESOLVED_HOSTNAME for
# configure_system().
_validate_system_fields() {
  local hostname
  hostname="$(cfgo '.system.hostname')"
  if [[ -z "$hostname" ]]; then
    while true; do
      read -rp "$(echo -e "${YELLOW}[?]${NC} Enter hostname for this machine: ")" hostname </dev/tty
      [[ -n "$hostname" ]] && break
      warn "Hostname cannot be empty."
    done
    info "Hostname: ${hostname}"
  fi
  [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] ||
    error "Invalid hostname '${hostname}'. Use letters, digits, hyphens only (no leading/trailing hyphen)."
  # shellcheck disable=SC2034 # consumed by configure_system() in chroot.sh
  RESOLVED_HOSTNAME="$hostname"
  cfg '.system.locale' 'system.locale'
  cfg '.system.timezone' 'system.timezone'
}

_validate_single() {
  local d
  d="$(cfg '.disk' 'disk')"
  [[ -b "$d" ]] || error "Single disk not found: $d"
}

_validate_multi() {
  local topo
  topo="$(cfgo '.os_pool.topology')"
  if [[ -n "$topo" ]]; then
    case "$topo" in
    mirror | stripe | none) ;;
    *) error "os_pool.topology must be mirror | stripe | none, got: '${topo}'" ;;
    esac
  fi

  local cnt
  cnt="$(jsonc "$CONFIG_FILE" | jq '.os_pool.disks | length')"
  ((cnt >= 1)) || error "os_pool.disks must list at least 1 disk."

  local d
  while IFS= read -r d; do
    [[ -b "$d" ]] || error "OS disk not found: $d"
  done < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')

  local sg gname gdc
  sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
  for ((i = 0; i < sg; i++)); do
    gname="$(cfg ".storage_groups[$i].name")"
    gdc="$(jsonc "$CONFIG_FILE" | jq ".storage_groups[$i].disks | length")"
    ((gdc >= 1)) || error "Storage group '${gname}' has no disks."
    while IFS= read -r d; do
      [[ -b "$d" ]] || error "Group '${gname}' disk not found: $d"
    done < <(jsonc "$CONFIG_FILE" | jq -r ".storage_groups[$i].disks[]")
  done
}

validate_config() {
  section "Validating Config"
  _validate_system_fields

  # Dispatch to the per-mode validator. INSTALL_MODE was already restricted
  # to known modes by detect_mode, so this is exhaustive by construction.
  local validator="_validate_${INSTALL_MODE}"
  if declare -F "$validator" >/dev/null; then
    "$validator"
  else
    error "No validator for mode '${INSTALL_MODE}' (expected function ${validator})."
  fi

  info "Config valid."
}

# =============================================================================
# SUMMARY & CONFIRMATION
# =============================================================================

print_summary() {
  section "Installation Plan"

  if [[ "$INSTALL_MODE" == "single" ]]; then
    local d
    d="$(cfgo '.disk')"
    local sz
    sz="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
    local rp
    rp="$(cfgo '.os_pool_name')"
    rp="${rp:-rpool}"
    local dp
    dp="$(cfgo '.storage_pool_name')"
    dp="${dp:-dpool}"
    local mnt
    mnt="$(cfgo '.storage_mount')"
    mnt="${mnt:-/data}"
    echo -e "\n  ${BOLD}Mode: single-disk${NC}"
    printf "    %-16s %s\n" "Disk:" "$d  ($sz)"
    printf "    %-16s %s\n" "OS pool:" "$rp  (no RAID, single partition)"
    printf "    %-16s %s\n" "Storage:" "$dp → $mnt"

  else # multi
    local op
    op="$(cfg '.os_pool.pool_name')"
    echo -e "\n  ${BOLD}Mode: multi-disk${NC}"
    echo -e "  ${BOLD}OS pool: ${op}${NC}  topology: ${MULTI_OS_TOPOLOGY}"

    if [[ "$MULTI_OS_TOPOLOGY" == "none" ]]; then
      local s
      s="$(lsblk -dno SIZE "$MULTI_OS_DISK" 2>/dev/null || echo '?')"
      printf "    OS disk  : %s  (%s)\n" "$MULTI_OS_DISK" "$s"
      ((${#MULTI_LEFTOVER_DISKS[@]} > 0)) &&
        printf "    → dpool  : %s\n" "${MULTI_LEFTOVER_DISKS[*]}"
    else
      while IFS= read -r d; do
        local s
        s="$(lsblk -dno SIZE "$d" 2>/dev/null || echo '?')"
        printf "    %s  (%s)\n" "$d" "$s"
      done < <(jsonc "$CONFIG_FILE" | jq -r '.os_pool.disks[]')
    fi

    local sg
    sg="$(jsonc "$CONFIG_FILE" | jq '.storage_groups | length')"
    local has_left=false
    [[ -v "STORAGE_PARTS[_leftover]" ]] && has_left=true

    if ((sg > 0)) || $has_left; then
      echo -e "\n  ${BOLD}Data pool: dpool${NC}"
      for ((i = 0; i < sg; i++)); do
        local gn
        gn="$(cfg ".storage_groups[$i].name")"
        local gm
        gm="$(cfg ".storage_groups[$i].mount")"
        local gt="${RESOLVED_TOPOLOGIES[$gn]:-?}"
        printf "    '%-12s  → %-20s  topology: %s\n" "${gn}'" "$gm" "$gt"
      done
      if $has_left; then
        printf "    '%-12s  → %-20s  topology: %s\n" \
          "extra (auto)'" "/data/extra" \
          "${RESOLVED_TOPOLOGIES[_leftover]:-independent}"
      fi
    fi
  fi

  # Packages
  local extras
  extras="$(jsonc "$CONFIG_FILE" | jq -r '(.packages.extra // []) | join(", ")')"
  local cli
  cli="$(jsonc "$CONFIG_FILE" | jq -r '(.packages.groups.cli // []) | join(", ")')"
  local dev
  dev="$(jsonc "$CONFIG_FILE" | jq -r '(.packages.groups.dev // []) | join(", ")')"
  local gui
  gui="$(jsonc "$CONFIG_FILE" | jq -r '(.packages.groups.gui // []) | join(", ")')"
  echo ""
  echo -e "  ${BOLD}Packages:${NC}"
  [[ -n "$extras" ]] && printf "    extra: %s\n" "$extras"
  [[ -n "$cli" ]] && printf "    cli:   %s\n" "$cli"
  [[ -n "$dev" ]] && printf "    dev:   %s\n" "$dev"
  [[ -n "$gui" ]] && printf "    gui:   %s\n" "$gui"

  # Post-install
  local kde
  kde="$(cfgo '.desktop.kde')"
  kde="${kde:-false}"
  local backup
  backup="$(cfgo '.post_install.backup')"
  backup="${backup:-false}"
  local security
  security="$(cfgo '.post_install.security')"
  security="${security:-false}"
  echo ""
  echo -e "  ${BOLD}Post-install scripts:${NC}"
  printf "    %-12s %s\n" "kde:" "$kde"
  printf "    %-12s %s\n" "backup:" "$backup"
  printf "    %-12s %s\n" "security:" "$security"

  echo ""
  local enc
  enc="$(cfgo '.options.encryption')"
  enc="${enc:-false}"
  local swap
  swap="$(cfgo '.options.swap')"
  swap="${swap:-true}"
  local _hn
  _hn="$(cfgo '.system.hostname')"
  _hn="${_hn:-(prompted during install)}"
  printf "  %-16s %s\n" "Hostname:" "$_hn"
  printf "  %-16s %s\n" "Timezone:" "$(cfg '.system.timezone')"
  printf "  %-16s %s\n" "Encryption:" "$enc"
  printf "  %-16s %s\n" "Swap:" "$swap  (auto = RAM × 2)"
  echo ""
  warn "ALL DATA ON THE LISTED DISKS WILL BE PERMANENTLY DESTROYED."
  confirm "Proceed with installation?"
}
