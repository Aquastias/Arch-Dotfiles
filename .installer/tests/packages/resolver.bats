#!/usr/bin/env bats
# Tests for .installer/lib/packages/resolver.sh — the Package Resolver.
#
# Pure JSON-in/TSV-out: every input is declarative, so the resolver needs no
# pacman query and no network. Assertions are external — given this Effective
# Config, these packages with these sources.

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  source "$INSTALLER_DIR/lib/common.sh"
  source "$INSTALLER_DIR/lib/packages/resolver.sh"
}

# pkgs_of <config> [source] — the resolved package names, optionally one source.
pkgs_of() {
  if [[ -n "${2:-}" ]]; then
    pkgres_resolve "$1" | awk -F'\t' -v s="$2" '$1 == s { print $3 }' | sort -u
  else
    pkgres_resolve "$1" | cut -f3 | sort -u
  fi
}
src_of() { pkgres_resolve "$1" | awk -F'\t' -v p="$3" '$3 == p { print $1 }'; }

MIN='{"users":[],"options":{"kernel":["lts"]}}'

# ── shape: source + layer on every line ─────────────────────────────────────

@test "every resolved package carries a source and a layer" {
  run pkgres_resolve "$MIN"
  [ "$status" -eq 0 ]
  # three tab-separated fields on every line, layer ∈ {authored, derived}
  while IFS=$'\t' read -r s l p; do
    [ -n "$s" ]; [ -n "$p" ]
    [[ "$l" == "authored" || "$l" == "derived" ]]
  done <<<"$output"
}

@test "the Base Package List is always present" {
  local p
  for p in base base-devel linux-firmware networkmanager openssh cronie \
           efibootmgr dosfstools vim git sudo rsync jq pacman-contrib stow; do
    run pkgs_of "$MIN" base
    echo "$output" | grep -qx "$p" || { echo "missing base pkg: $p"; return 1; }
  done
}

# The layer column is provenance, not just authored-vs-derived: an authored
# package Host Core also declares reads `core`, otherwise `host`, so the
# report answers "do I edit Host Core or this host profile?" (PRD story 30).
@test "authored slots carry core-vs-host provenance; derived reads derived" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/hosts/core"
  printf '{"packages":{"repo":{"cli":["htop"]}}}\n' \
    > "$t/hosts/core/profile.jsonc"
  local cfg='{"users":[],"packages":{"repo":{"cli":["htop","ripgrep"]},
                                      "aur":{"misc":["brave-bin"]}}}'
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '$cfg'"
  echo "$output" | grep -qP '^repo\tcore\thtop$'      # core declares it
  echo "$output" | grep -qP '^repo\thost\tripgrep$'   # this profile adds it
  echo "$output" | grep -qP '^aur\thost\tbrave-bin$'
  echo "$output" | grep -qP '^base\tderived\tbase$'
  rm -rf "$t"
}

@test "with no Host Core to compare against, authored slots read authored" {
  local t; t="$(mktemp -d)"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[],\"packages\":{\"repo\":{\"c\":[\"htop\"]}}}'"
  echo "$output" | grep -qP '^repo\tauthored\thtop$'
  rm -rf "$t"
}

# ── each derived set tracks the setting that drives it ──────────────────────

@test "changing the GPU vendor changes the resolved driver set" {
  local amd nvidia intel
  amd="$(pkgs_of '{"users":[],"environment":{"gpu":["amd"]}}' gpu)"
  nvidia="$(pkgs_of '{"users":[],"environment":{"gpu":["nvidia"]}}' gpu)"
  intel="$(pkgs_of '{"users":[],"environment":{"gpu":["intel"]}}' gpu)"

  grep -qx "vulkan-radeon"    <<<"$amd"
  grep -qx "nvidia-open-dkms" <<<"$nvidia"
  grep -qx "intel-media-driver" <<<"$intel"
  [ "$amd" != "$nvidia" ]
  [ "$nvidia" != "$intel" ]
}

@test "a hybrid GPU config resolves both vendors' drivers" {
  local both; both="$(pkgs_of '{"users":[],
    "environment":{"gpu":["amd","nvidia"]}}' gpu)"
  grep -qx "vulkan-radeon"    <<<"$both"
  grep -qx "nvidia-open-dkms" <<<"$both"
}

@test "changing the desktop selection changes the audio and Plasma sets" {
  local none kde
  none="$(pkgs_of '{"users":[],"environment":{"desktop":[]}}')"
  kde="$(pkgs_of  '{"users":[],"environment":{"desktop":["kde"]}}')"

  ! grep -qx "pipewire"    <<<"$none"
  ! grep -qx "plasma-meta" <<<"$none"
  grep -qx "pipewire"    <<<"$kde"
  grep -qx "wireplumber" <<<"$kde"
  grep -qx "plasma-meta" <<<"$kde"
  grep -qx "konsole"     <<<"$kde"
}

# ── niri core set (ADR 0090) ────────────────────────────────────────────────

@test "niri-shell set reports the niri core packages" {
  source "$INSTALLER_DIR/lib/packages/niri.sh"
  local got want
  got="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' niri-shell)"
  want="$(niri_core_packages | sort)"
  [ "$(printf '%s\n' "$got" | sort)" = "$want" ]
  grep -qx "niri" <<<"$got"
  grep -qx "seatd" <<<"$got"
}

@test "niri-shell set is empty when niri is not selected" {
  local got
  got="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' niri-shell)"
  [ -z "$got" ]
}

@test "noctalia set reports the work preset when wayland_shell defaults on" {
  local n
  n="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' noctalia)"
  grep -qx "noctalia"      <<<"$n"
  grep -qx "kitty"         <<<"$n"
  grep -qx "brightnessctl" <<<"$n"
  grep -qx "playerctl"     <<<"$n"   # media-key backend (ADR 0096)
}

@test "noctalia set is empty for bare niri (wayland_shell=none)" {
  local n
  n="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["niri"],"wayland_shell":"none"}}' \
    noctalia)"
  [ -z "$n" ]
}

@test "noctalia set reports the shared preset on hyprland too (ADR 0097)" {
  local n
  n="$(pkgs_of '{"users":[],"environment":{"desktop":["hyprland"]}}' noctalia)"
  grep -qx "noctalia"      <<<"$n"
  grep -qx "kitty"         <<<"$n"
  grep -qx "playerctl"     <<<"$n"
  grep -qx "smartmontools" <<<"$n"   # drive-health: a shared-core plugin dep
}

@test "noctalia set is empty for bare hyprland (wayland_shell=none)" {
  local n
  n="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["hyprland"],"wayland_shell":"none"}}' \
    noctalia)"
  [ -z "$n" ]
}

@test "noctalia set omits the dropped bitwarden-cli backend (ADR 0094)" {
  # bitwarden left the default set; its CLI backend must no longer resolve
  local n
  n="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' noctalia)"
  ! grep -qx "bitwarden-cli" <<<"$n"
}

@test "noctalia set reports enriched plugin tool deps (ADR 0093/0094)" {
  # committed install-noctalia.jsonc enables the curated plugin set by default
  local n
  n="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' noctalia)"
  grep -qx "smartmontools" <<<"$n"   # drive-health
  grep -qx "wl-mirror"     <<<"$n"    # wl-screen-mirror
  grep -qx "fzf"           <<<"$n"    # file-search
  grep -qx "ollama"        <<<"$n"    # llamanager
  grep -qx "iw"            <<<"$n"    # hotspot
  grep -qx "bind"          <<<"$n"    # dns-switcher
  ! grep -qx "docker"      <<<"$n"    # mini-docker was dropped (ADR 0094)
}

@test "noctalia set omits battery deps under the laptop:auto default" {
  # the resolver has no hardware, so auto does not report the battery pair
  local n
  n="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' noctalia)"
  ! grep -qx "upower" <<<"$n"
}

@test "noctalia set reports battery deps when laptop is forced true" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/extras/desktop"
  printf '{"laptop":true,"battery-widget":true}\n' \
    > "$t/extras/desktop/install-noctalia.jsonc"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[],\"environment\":{\"desktop\":[\"niri\"]}}'"
  echo "$output" | grep -qP '^noctalia\tderived\tupower$'
  rm -rf "$t"
}

# ── display manager derived set (ADR 0069) ──────────────────────────────────

@test "display-manager set: auto on a kde-only box resolves to sddm" {
  local dm
  dm="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' display-manager)"
  grep -qx "sddm" <<<"$dm"
  ! grep -qx "greetd" <<<"$dm"
}

@test "display-manager set: auto on a hyprland-only box resolves to greetd" {
  local dm
  dm="$(pkgs_of '{"users":[],"environment":{"desktop":["hyprland"]}}' \
    display-manager)"
  grep -qx "greetd"          <<<"$dm"
  grep -qx "greetd-tuigreet" <<<"$dm"
  ! grep -qx "sddm" <<<"$dm"
}

@test "display-manager set: auto on a niri-only box resolves to greetd" {
  local dm
  dm="$(pkgs_of '{"users":[],"environment":{"desktop":["niri"]}}' \
    display-manager)"
  grep -qx "greetd" <<<"$dm"
  ! grep -qx "sddm" <<<"$dm"
}

@test "display-manager set: auto with kde present resolves to sddm" {
  local dm
  dm="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["kde","hyprland"]}}' display-manager)"
  grep -qx "sddm" <<<"$dm"
  ! grep -qx "greetd" <<<"$dm"
}

@test "display-manager set: an explicit greetd on a kde box wins over auto" {
  local dm
  dm="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["kde"],"display_manager":"greetd"}}' \
    display-manager)"
  grep -qx "greetd"          <<<"$dm"
  grep -qx "greetd-tuigreet" <<<"$dm"
  ! grep -qx "sddm" <<<"$dm"
}

@test "display-manager set: empty when no desktop is selected" {
  local dm
  dm="$(pkgs_of '{"users":[],"environment":{"desktop":[]}}' display-manager)"
  [ -z "$dm" ]
}

@test "sddm is no longer reported inside the kde-shell set" {
  local kdeshell
  kdeshell="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' kde-shell)"
  grep -qx "sddm-kcm" <<<"$kdeshell"
  ! grep -qx "sddm" <<<"$kdeshell"
}

# Drift guard (Candidate 5): the KDE adapter installs shell_packages from
# install-kde.jsonc and the resolver reports them — assert the resolver's
# kde-shell set equals the jsonc data, so install and query cannot diverge.
@test "kde-shell source == install-kde.jsonc shell_packages" {
  source "$INSTALLER_DIR/lib/config/categorized-list.sh"
  local json expected got
  json="$(jsonc_strip "$INSTALLER_DIR/extras/desktop/kde/install-kde.jsonc")"
  expected="$(categorized_list_parse \
    "$(jq -c '.shell_packages' <<<"$json")" bool shell_packages | sort -u)"
  got="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' kde-shell)"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got")
}

@test "the derived audio set covers the formerly hand-declared packages" {
  local a; a="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' audio)"
  local p
  for p in gst-plugin-pipewire pipewire-jack libpulse; do
    grep -qx "$p" <<<"$a" || { echo "audio set missing: $p"; return 1; }
  done
}

@test "changing the filesystem changes the filesystem-tool set" {
  local zfs btrfs xfs
  zfs="$(pkgs_of   '{"users":[],"filesystem":"zfs"}')"
  btrfs="$(pkgs_of '{"users":[],"filesystem":"btrfs"}')"
  xfs="$(pkgs_of   '{"users":[],"filesystem":"xfs"}')"

  grep -qx "zfs-dkms"    <<<"$zfs"
  ! grep -qx "zfs-dkms"  <<<"$btrfs"
  grep -qx "btrfs-progs" <<<"$btrfs"
  grep -qx "xfsprogs"    <<<"$xfs"
}

@test "a per-group filesystem contributes its tools too" {
  local p; p="$(pkgs_of '{"users":[],"filesystem":"zfs",
    "data_pools":[{"name":"t","filesystem":"btrfs"}]}')"
  grep -qx "zfs-dkms"    <<<"$p"
  grep -qx "btrfs-progs" <<<"$p"
}

@test "changing the bootloader changes the bootloader package" {
  local sd grub
  sd="$(pkgs_of   '{"users":[],"options":{"bootloader":"systemd-boot"}}')"
  grub="$(pkgs_of '{"users":[],"options":{"bootloader":"grub"}}')"
  ! grep -qx "grub" <<<"$sd"
  grep -qx "grub"   <<<"$grub"
}

@test "new loaders resolve their manifest package (ADR 0077)" {
  local limine refind efistub
  limine="$(pkgs_of  '{"users":[],"options":{"bootloader":"limine"}}')"
  refind="$(pkgs_of  '{"users":[],"options":{"bootloader":"refind"}}')"
  efistub="$(pkgs_of '{"users":[],"options":{"bootloader":"efistub"}}')"
  grep -qx "limine" <<<"$limine"
  grep -qx "refind" <<<"$refind"
  # efistub needs no extra package beyond efibootmgr (already in base)
  ! grep -qx "grub"   <<<"$efistub"
  ! grep -qx "limine" <<<"$efistub"
  ! grep -qx "refind" <<<"$efistub"
}

@test "changing the kernel selection changes the kernel packages" {
  local lts zen multi
  lts="$(pkgs_of   '{"users":[],"options":{"kernel":["lts"]}}' kernel)"
  zen="$(pkgs_of   '{"users":[],"options":{"kernel":["zen"]}}' kernel)"
  multi="$(pkgs_of '{"users":[],"options":{"kernel":["lts","zen"]}}' kernel)"
  [ "$lts" = "$(printf 'linux-lts\nlinux-lts-headers')" ]
  grep -qx "linux-zen" <<<"$zen"
  [ "$(wc -l <<<"$multi")" -eq 4 ]
}

@test "changing a user's login shell changes the shell package" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/users/core" "$t/users/alice"
  printf '{"shell":"/bin/zsh"}\n'  > "$t/users/core/profile.jsonc"
  printf '{"shell":"/bin/fish"}\n' > "$t/users/alice/profile.jsonc"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[\"alice\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "fish" ]
  rm -rf "$t"
}

@test "a user with no profile falls back to User Core's shell" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/users/core"
  printf '{"shell":"/bin/zsh"}\n' > "$t/users/core/profile.jsonc"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[\"bob\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "zsh" ]
  rm -rf "$t"
}

@test "Security and Backup Extras resolve from post_install" {
  local cfg='{"users":["a"],"post_install":{
    "security":{"firewall":"firewalld","antivirus":true,"rootkit":true,
                "apparmor":true},
    "backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  local sec bak
  sec="$(pkgs_of "$cfg" security)"; bak="$(pkgs_of "$cfg" backup)"
  grep -qx "firewalld" <<<"$sec"
  grep -qx "clamav"    <<<"$sec"
  grep -qx "borg"      <<<"$bak"
  grep -qx "zfs-auto-snapshot" <<<"$bak"
}

@test "toggling a security tool changes the resolved set" {
  local on off
  on="$(pkgs_of  '{"users":["a"],"post_install":{"security":
    {"firewall":"firewalld","apparmor":true}}}' security)"
  off="$(pkgs_of '{"users":["a"],"post_install":{"security":
    {"firewall":"none","apparmor":false}}}' security)"
  grep -qx "firewalld" <<<"$on"
  [ -z "$off" ]
}

@test "sops resolves only when the host or a user ships secrets" {
  local t; t="$(mktemp -d)"
  mkdir -p "$t/users/alice" "$t/hosts/box"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[\"alice\"],\"system\":{\"hostname\":\"box\"}}' \
      | awk -F'\t' '\$1 == \"sops\"'"
  [ -z "$output" ]

  printf '{}' > "$t/users/alice/secrets.json"
  INSTALLER_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[\"alice\"],\"system\":{\"hostname\":\"box\"}}' \
      | awk -F'\t' '\$1 == \"sops\" { print \$3 }'"
  echo "$output" | grep -qx sops
  rm -rf "$t"
}

# ── exclusions are reported separately ──────────────────────────────────────

@test "excluded packages are reported separately and are not installed" {
  local cfg='{"users":[],"packages":{"repo":{"cli":["htop"]},
                                      "exclude":["fzf","btop"]}}'
  run pkgres_excluded "$cfg"
  [ "$output" = "$(printf 'btop\nfzf')" ]
  # and they are absent from the installed set
  local p; p="$(pkgs_of "$cfg")"
  ! grep -qx "fzf"  <<<"$p"
  ! grep -qx "btop" <<<"$p"
}

@test "a config with no exclusions reports none" {
  run pkgres_excluded "$MIN"
  [ -z "$output" ]
}

# ── purity + determinism ────────────────────────────────────────────────────

@test "the resolver is deterministic for a given config" {
  local a b
  a="$(pkgres_resolve "$MIN")"
  b="$(pkgres_resolve "$MIN")"
  [ "$a" = "$b" ]
}

# The resolver must stay usable headless: every input is declarative, so it
# needs no package database and no network. Shadowing pacman and the network
# tools with stubs that ABORT proves it — if the resolver reached for any of
# them the run would fail loudly rather than silently degrade.
@test "the resolver makes no pacman or network call" {
  local bin; bin="$(mktemp -d)"
  local c
  for c in pacman pacman-key paru yay curl wget ping lspci pactree expac; do
    printf '#!/bin/sh\necho "FORBIDDEN: %s" >&2\nexit 127\n' "$c" > "$bin/$c"
    chmod +x "$bin/$c"
  done
  run env PATH="$bin:$PATH" INSTALLER_DIR="$INSTALLER_DIR" bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '$MIN'"
  rm -rf "$bin"
  [ "$status" -eq 0 ]
  [[ "$output" != *FORBIDDEN* ]]
  [ -n "$output" ]
}

@test "pkgres_sources lists every source the resolver can emit" {
  local declared emitted
  declared="$(pkgres_sources | sort)"
  emitted="$(pkgres_resolve '{"users":["a"],"environment":
    {"desktop":["kde"],"gpu":["amd"]},"options":{"bootloader":"grub"},
     "filesystem":"btrfs","packages":{"repo":{"c":["htop"]},
     "aur":{"m":["x"]}},"post_install":{"security":{"firewall":"ufw"},
     "backup":{"borg":true}}}' | cut -f1 | sort -u)"
  # everything emitted must be declared
  local s
  while IFS= read -r s; do
    grep -qx "$s" <<<"$declared" || { echo "undeclared source: $s"; return 1; }
  done <<<"$emitted"
}

# ── the real committed profiles ─────────────────────────────────────────────

@test "the real desktop profile resolves through the resolver" {
  source "$INSTALLER_DIR/lib/config/profile.sh"
  local eff; eff="$(load_profile desktop)"
  run pkgres_resolve "$eff"
  [ "$status" -eq 0 ]
  local p; p="$(cut -f3 <<<"$output" | sort -u)"
  grep -qx "steam"       <<<"$p"   # core
  grep -qx "qemu-full"   <<<"$p"   # desktop delta
  grep -qx "plasma-meta" <<<"$p"   # derived, KDE
  grep -qx "base"        <<<"$p"   # derived, base list
}

# The curation's headline number: desktop adds exactly 25 packages over
# laptop, and laptop declares none of its own. (Was 31 before the dev
# toolchain moved to Host Core — both hosts are dev boxes.)
@test "desktop resolves to exactly 25 packages more than laptop" {
  source "$INSTALLER_DIR/lib/config/profile.sh"
  local d l
  d="$(pkgres_resolve "$(load_profile desktop)" | cut -f3 | sort -u)"
  l="$(pkgres_resolve "$(load_profile laptop)"  | cut -f3 | sort -u)"
  [ "$(comm -13 <(printf '%s\n' "$l") <(printf '%s\n' "$d") | wc -l)" -eq 25 ]
  # laptop adds nothing desktop lacks
  [ "$(comm -23 <(printf '%s\n' "$l") <(printf '%s\n' "$d") | wc -l)" -eq 0 ]
}
