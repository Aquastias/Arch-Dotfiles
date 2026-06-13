#!/usr/bin/env bash
# =============================================================================
# lib/packages/microcode.sh — per-vendor CPU microcode resolution (ADR 0038)
# =============================================================================
# Replaces the old "install both intel-ucode and amd-ucode" default. The CPU
# vendor is detected at install time and only the matching microcode is
# installed; loader entries are rendered from the *-ucode.img files that
# actually exist, so an entry never references a missing initrd.
#
# Pure helpers + one injectable seam (_microcode_cpuinfo) mirroring the GPU
# resolution pattern in lib/config/environment.sh.
# =============================================================================

# Map a CPU vendor token to its microcode package. Unknown / empty (e.g. a VM)
# resolves to nothing — no microcode is installed.
microcode_vendor_package() {
  case "$1" in
  intel) echo "intel-ucode" ;;
  amd)   echo "amd-ucode" ;;
  *)     echo "" ;;
  esac
}

# Injectable seam: the raw CPU vendor source. Override in tests to control the
# detected vendor without real hardware. On a bare-metal install the live ISO
# runs on the target CPU, so /proc/cpuinfo is the target's vendor.
_microcode_cpuinfo() { cat /proc/cpuinfo 2>/dev/null; }

# Detect the CPU vendor → "intel" | "amd" | "" (empty for a VM / unknown CPU,
# which then installs no microcode).
microcode_detect_vendor() {
  local info
  info="$(_microcode_cpuinfo)"
  if grep -q 'GenuineIntel' <<<"$info"; then
    echo "intel"
  elif grep -q 'AuthenticAMD' <<<"$info"; then
    echo "amd"
  else
    echo ""
  fi
}

# Emit the loader-entry `initrd` line for each *-ucode.img present in <dir>, in
# a deterministic order (intel, then amd). A microcode file that does not exist
# produces no line, so a generated entry never references a missing initrd
# (the dangling-reference class that panicked systemd-boot — ADR 0038).
microcode_present_initrds() {
  local dir="$1" img
  for img in intel-ucode.img amd-ucode.img; do
    [[ -f "$dir/$img" ]] && echo "initrd  /$img"
  done
  return 0
}
