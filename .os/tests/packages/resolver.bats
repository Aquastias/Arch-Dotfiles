#!/usr/bin/env bats
# Tests for .os/lib/packages/resolver.sh — the Package Resolver.
#
# Pure JSON-in/TSV-out: every input is declarative, so the resolver needs no
# pacman query and no network. Assertions are external — given this Effective
# Config, these packages with these sources.

setup() {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  source "$OS_DIR/lib/common.sh"
  source "$OS_DIR/lib/packages/resolver.sh"
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
  OS_DIR="$t" run bash -c "
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
  OS_DIR="$t" run bash -c "
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

# ── display manager derived set (ADR 0069) ──────────────────────────────────

@test "display-manager set: auto on a kde-only box resolves to sddm" {
  local dm
  dm="$(pkgs_of '{"users":[],"environment":{"desktop":["kde"]}}' display-manager)"
  grep -qx "sddm" <<<"$dm"
  ! grep -qx "greetd" <<<"$dm"
}

@test "display-manager set: auto with hyprland resolves to greetd + tuigreet" {
  local dm
  dm="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["kde","hyprland"]}}' display-manager)"
  grep -qx "greetd"          <<<"$dm"
  grep -qx "greetd-tuigreet" <<<"$dm"
  ! grep -qx "sddm" <<<"$dm"
}

@test "display-manager set: an explicit greetd on a kde box wins over auto" {
  local dm
  dm="$(pkgs_of \
    '{"users":[],"environment":{"desktop":["kde"],"display_manager":"greetd"}}' \
    display-manager)"
  grep -qx "greetd" <<<"$dm"
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
  OS_DIR="$t" run bash -c "
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
  OS_DIR="$t" run bash -c "
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
  OS_DIR="$t" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/resolver.sh'
    pkgres_resolve '{\"users\":[\"alice\"],\"system\":{\"hostname\":\"box\"}}' \
      | awk -F'\t' '\$1 == \"sops\"'"
  [ -z "$output" ]

  printf '{}' > "$t/users/alice/secrets.json"
  OS_DIR="$t" run bash -c "
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
  run env PATH="$bin:$PATH" OS_DIR="$OS_DIR" bash -c "
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
  source "$OS_DIR/lib/config/profile.sh"
  local eff; eff="$(load_profile desktop)"
  run pkgres_resolve "$eff"
  [ "$status" -eq 0 ]
  local p; p="$(cut -f3 <<<"$output" | sort -u)"
  grep -qx "steam"       <<<"$p"   # core
  grep -qx "qemu-full"   <<<"$p"   # desktop delta
  grep -qx "plasma-meta" <<<"$p"   # derived, KDE
  grep -qx "base"        <<<"$p"   # derived, base list
}

# The curation's headline number: desktop adds exactly 34 packages over
# laptop, and laptop declares none of its own.
@test "desktop resolves to exactly 34 packages more than laptop" {
  source "$OS_DIR/lib/config/profile.sh"
  local d l
  d="$(pkgres_resolve "$(load_profile desktop)" | cut -f3 | sort -u)"
  l="$(pkgres_resolve "$(load_profile laptop)"  | cut -f3 | sort -u)"
  [ "$(comm -13 <(printf '%s\n' "$l") <(printf '%s\n' "$d") | wc -l)" -eq 34 ]
  # laptop adds nothing desktop lacks
  [ "$(comm -23 <(printf '%s\n' "$l") <(printf '%s\n' "$d") | wc -l)" -eq 0 ]
}
