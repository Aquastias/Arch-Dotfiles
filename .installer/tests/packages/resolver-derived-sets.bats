#!/usr/bin/env bats
# Tests: derived sets (split from resolver.bats;
# shared setup in resolver-helpers.bash)

load resolver-helpers


# ── shape: source + layer on every line ─────────────────────────────────────

@test "every resolved package carries a source and a layer" {
  run package_resolver_resolve "$MIN"
  [ "$status" -eq 0 ]
  # three tab-separated fields on every line, layer ∈ {authored, derived}
  while IFS=$'\t' read -r s l p; do
    [ -n "$s" ]; [ -n "$p" ]
    [[ "$l" == "authored" || "$l" == "derived" ]]
  done <<<"$output"
}

@test "the Base Package List is always present" {
  local package
  for package in base base-devel linux-firmware networkmanager openssh cronie \
           efibootmgr dosfstools vim git sudo rsync jq pacman-contrib stow; do
    run packages_of "$MIN" base
    echo "$output" | grep -qx "$package" || { echo "missing base pkg: $package"; return 1; }
  done
}

# The layer column is provenance, not just authored-vs-derived: an authored
# package Host Core also declares reads `core`, otherwise `host`, so the
# report answers "do I edit Host Core or this host profile?" (PRD story 30).
@test "authored slots carry core-vs-host provenance; derived reads derived" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/hosts/core"
  printf '{"packages":{"repo":{"cli":["htop"]}}}\n' \
    > "$test_directory/hosts/core/profile.jsonc"
  local config='{"users":[],"packages":{"repo":{"cli":["htop","ripgrep"]},
                                      "aur":{"misc":["brave-bin"]}}}'
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '$config'"
  echo "$output" | grep -qP '^repo\tcore\thtop$'      # core declares it
  echo "$output" | grep -qP '^repo\thost\tripgrep$'   # this profile adds it
  echo "$output" | grep -qP '^aur\thost\tbrave-bin$'
  echo "$output" | grep -qP '^base\tderived\tbase$'
  rm -rf "$test_directory"
}

@test "with no Host Core to compare against, authored slots read authored" {
  local test_directory; test_directory="$(mktemp -d)"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[],\"packages\":{\"repo\":{\"c\":[\"htop\"]}}}'"
  echo "$output" | grep -qP '^repo\tauthored\thtop$'
  rm -rf "$test_directory"
}


# ── each derived set tracks the setting that drives it ──────────────────────

@test "changing the GPU vendor changes the resolved driver set" {
  local amd nvidia intel
  amd="$(packages_of '{"users":[],"environment":{"gpu":["amd"]}}' gpu)"
  nvidia="$(packages_of '{"users":[],"environment":{"gpu":["nvidia"]}}' gpu)"
  intel="$(packages_of '{"users":[],"environment":{"gpu":["intel"]}}' gpu)"

  grep -qx "vulkan-radeon"    <<<"$amd"
  grep -qx "nvidia-open-dkms" <<<"$nvidia"
  grep -qx "intel-media-driver" <<<"$intel"
  [ "$amd" != "$nvidia" ]
  [ "$nvidia" != "$intel" ]
}

@test "a hybrid GPU config resolves both vendors' drivers" {
  local both; both="$(packages_of '{"users":[],
    "environment":{"gpu":["amd","nvidia"]}}' gpu)"
  grep -qx "vulkan-radeon"    <<<"$both"
  grep -qx "nvidia-open-dkms" <<<"$both"
}

@test "changing the desktop selection changes the audio and Plasma sets" {
  local none kde
  none="$(packages_of '{"users":[],"environment":{"desktop":[]}}')"
  kde="$(packages_of  '{"users":[],"environment":{"desktop":["kde"],"stock":false}}')"

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
  got="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' niri-shell)"
  want="$(niri_core_packages | sort)"
  [ "$(printf '%s\n' "$got" | sort)" = "$want" ]
  grep -qx "niri" <<<"$got"
  grep -qx "seatd" <<<"$got"
}

@test "niri-shell set is empty when niri is not selected" {
  local got
  got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' niri-shell)"
  [ -z "$got" ]
}

@test "noctalia set reports the work preset when wayland_shell defaults on" {
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  grep -qx "noctalia"      <<<"$noctalia_packages"
  grep -qx "kitty"         <<<"$noctalia_packages"
  grep -qx "brightnessctl" <<<"$noctalia_packages"
  grep -qx "playerctl"     <<<"$noctalia_packages"   # media-key backend (ADR 0096)
}

@test "noctalia set is empty for bare niri (wayland_shell=none)" {
  local noctalia_packages
  noctalia_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["niri"],"stock":false,"wayland_shell":"none"}}' \
    noctalia)"
  [ -z "$noctalia_packages" ]
}

@test "noctalia set reports the shared preset on hyprland too (ADR 0097)" {
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["hyprland"],"stock":false}}' noctalia)"
  grep -qx "noctalia"      <<<"$noctalia_packages"
  grep -qx "kitty"         <<<"$noctalia_packages"
  grep -qx "playerctl"     <<<"$noctalia_packages"
  grep -qx "smartmontools" <<<"$noctalia_packages"   # drive-health: a shared-core plugin dep
  grep -qx "socat"         <<<"$noctalia_packages"   # hypr-submap/screen-mirror: hypr-slice dep
}

@test "noctalia set is empty for bare hyprland (wayland_shell=none)" {
  local noctalia_packages
  noctalia_packages="$(packages_of \
  '{"users":[],"environment":{"desktop":["hyprland"],"stock":false,"wayland_shell":"none"}}' \
    noctalia)"
  [ -z "$noctalia_packages" ]
}


# ── stock (pure) reduction (ADR 0112) ────────────────────────────────────────

@test "stock KDE reports the shell but no apps" {
  local shell apps
  shell="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde"],"stock":true}}' kde-shell)"
  apps="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde"],"stock":true}}' kde-apps)"
  grep -qx "plasma-meta" <<<"$shell"
  [ -z "$apps" ]
}

@test "stock compositor reports no Noctalia preset even if shell defaults on" {
  local noctalia_packages
  noctalia_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["niri"],"stock":true}}' noctalia)"
  [ -z "$noctalia_packages" ]
}

@test "noctalia set omits the dropped bitwarden-cli backend (ADR 0094)" {
  # bitwarden left the default set; its CLI backend must no longer resolve
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  ! grep -qx "bitwarden-cli" <<<"$noctalia_packages"
}

@test "noctalia set reports enriched plugin tool deps (ADR 0093/0094)" {
  # committed install-noctalia.jsonc enables the curated plugin set by default
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  grep -qx "smartmontools" <<<"$noctalia_packages"   # drive-health
  grep -qx "wl-mirror"     <<<"$noctalia_packages"    # wl-screen-mirror
  grep -qx "fzf"           <<<"$noctalia_packages"    # file-search
  grep -qx "ollama"        <<<"$noctalia_packages"    # llamanager
  grep -qx "iw"            <<<"$noctalia_packages"    # hotspot
  grep -qx "bind"          <<<"$noctalia_packages"    # dns-switcher
  ! grep -qx "docker"      <<<"$noctalia_packages"    # mini-docker was dropped (ADR 0094)
}

@test "noctalia set omits battery deps under the laptop:auto default" {
  # the resolver has no hardware, so auto does not report the battery pair
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  ! grep -qx "upower" <<<"$noctalia_packages"
}

@test "noctalia set reports battery deps when laptop is forced true" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/extras/desktop"
  printf '{"laptop":true,"battery-widget":true}\n' \
    > "$test_directory/extras/desktop/install-noctalia.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[],\"environment\":{\"desktop\":[\"niri\"],\"stock\":false}}'"
  echo "$output" | grep -qP '^noctalia\tderived\tupower$'
  rm -rf "$test_directory"
}


# ── display manager derived set (ADR 0069) ──────────────────────────────────

@test "display-manager set: auto on a kde-only box resolves to sddm" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' display-manager)"
  grep -qx "sddm" <<<"$display_manager_packages"
  ! grep -qx "greetd" <<<"$display_manager_packages"
}

@test "display-manager set: auto on a Noctalia hyprland box is noctalia-greeter" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":["hyprland"],"stock":false}}' \
    display-manager)"
  [ "$display_manager_packages" = "$(printf '%s\n' greetd noctalia-greeter)" ]
}

@test "display-manager set: auto on a Noctalia niri box is noctalia-greeter" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' \
    display-manager)"
  [ "$display_manager_packages" = "$(printf '%s\n' greetd noctalia-greeter)" ]
}

@test "display-manager set: auto on a shell-less niri box is greetd + tuigreet" {
  local display_manager_packages
  display_manager_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["niri"],"stock":false,"wayland_shell":"none"}}' \
    display-manager)"
  [ "$display_manager_packages" = "$(printf '%s\n' greetd greetd-tuigreet)" ]
}

@test "display-manager set: auto on a stock hyprland box is greetd + tuigreet" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":["hyprland"],"stock":true}}' \
    display-manager)"
  [ "$display_manager_packages" = "$(printf '%s\n' greetd greetd-tuigreet)" ]
}

@test "display-manager set: auto with kde present resolves to sddm" {
  local display_manager_packages
  display_manager_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde","hyprland"],"stock":false}}' display-manager)"
  grep -qx "sddm" <<<"$display_manager_packages"
  ! grep -qx "greetd" <<<"$display_manager_packages"
}

@test "display-manager set: an explicit greetd on a kde box wins over auto" {
  local display_manager_packages
  display_manager_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde"],"stock":false,"display_manager":"greetd"}}' \
    display-manager)"
  grep -qx "greetd"          <<<"$display_manager_packages"
  grep -qx "greetd-tuigreet" <<<"$display_manager_packages"
  ! grep -qx "sddm" <<<"$display_manager_packages"
}

@test "display-manager set: explicit noctalia-greeter is greetd + the greeter" {
  local display_manager_packages
  display_manager_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde"],"stock":false,"display_manager":"noctalia-greeter"}}' \
    display-manager)"
  [ "$display_manager_packages" = "$(printf '%s\n' greetd noctalia-greeter)" ]
}

@test "display-manager set: empty when no desktop is selected" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":[]}}' display-manager)"
  [ -z "$display_manager_packages" ]
}

@test "sddm is no longer reported inside the kde-shell set" {
  local kdeshell
  kdeshell="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' kde-shell)"
  grep -qx "sddm-kcm" <<<"$kdeshell"
  ! grep -qx "sddm" <<<"$kdeshell"
}

# Drift guard (Candidate 5): the KDE adapter installs shell_packages from
# install-kde.jsonc and the resolver reports them — assert the resolver's
# kde-shell set equals the jsonc data, so install and query cannot diverge.
@test "kde-shell source == install-kde.jsonc shell + curated shell packages" {
  source "$INSTALLER_DIR/lib/config/categorized-list.sh"
  local json expected got stock_expected stock_got
  json="$(jsonc_strip "$INSTALLER_DIR/extras/desktop/kde/install-kde.jsonc")"
  stock_expected="$(categorized_list_parse \
    "$(jq -c '.shell_packages' <<<"$json")" bool shell_packages | sort -u)"
  expected="$({ printf '%s\n' "$stock_expected"; categorized_list_parse \
    "$(jq -c '.curated_shell_packages' <<<"$json")" bool \
    curated_shell_packages; } | sort -u)"
  got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' kde-shell)"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got")
  # stock KDE reports the shell_packages alone (ADR 0157)
  stock_got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":true}}' kde-shell)"
  diff <(printf '%s\n' "$stock_expected") <(printf '%s\n' "$stock_got")
}

@test "kde-shell set includes the packaged weather widget (ADR 0120)" {
  local shell
  shell="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' kde-shell)"
  grep -qx "plasma-applets-weather-widget-3" <<<"$shell" \
    || { echo "kde-shell missing plasma-applets-weather-widget-3"; return 1; }
}

@test "kde extra-apps set includes orca and vlc (ADR 0120)" {
  local apps
  apps="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' \
    kde-apps-extra)"
  grep -qx "orca" <<<"$apps" || { echo "extra-apps missing orca"; return 1; }
  grep -qx "vlc"  <<<"$apps" || { echo "extra-apps missing vlc";  return 1; }
}

@test "the derived audio set covers the formerly hand-declared packages" {
  local audio_packages; audio_packages="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' audio)"
  local package
  for package in gst-plugin-pipewire pipewire-jack libpulse; do
    grep -qx "$package" <<<"$audio_packages" || { echo "audio set missing: $package"; return 1; }
  done
}

@test "changing the filesystem changes the filesystem-tool set" {
  local zfs btrfs xfs
  zfs="$(packages_of   '{"users":[],"filesystem":"zfs"}')"
  btrfs="$(packages_of '{"users":[],"filesystem":"btrfs"}')"
  xfs="$(packages_of   '{"users":[],"filesystem":"xfs"}')"

  grep -qx "zfs-dkms"    <<<"$zfs"
  ! grep -qx "zfs-dkms"  <<<"$btrfs"
  grep -qx "btrfs-progs" <<<"$btrfs"
  grep -qx "xfsprogs"    <<<"$xfs"
}

@test "a per-group filesystem contributes its tools too" {
  local packages; packages="$(packages_of '{"users":[],"filesystem":"zfs",
    "data_pools":[{"name":"t","filesystem":"btrfs"}]}')"
  grep -qx "zfs-dkms"    <<<"$packages"
  grep -qx "btrfs-progs" <<<"$packages"
}

@test "changing the bootloader changes the bootloader package" {
  local systemd_boot_packages grub
  systemd_boot_packages="$(packages_of   '{"users":[],"options":{"bootloader":"systemd-boot"}}')"
  grub="$(packages_of '{"users":[],"options":{"bootloader":"grub"}}')"
  ! grep -qx "grub" <<<"$systemd_boot_packages"
  grep -qx "grub"   <<<"$grub"
}

@test "new loaders resolve their manifest package (ADR 0077)" {
  local limine refind efistub
  limine="$(packages_of  '{"users":[],"options":{"bootloader":"limine"}}')"
  refind="$(packages_of  '{"users":[],"options":{"bootloader":"refind"}}')"
  efistub="$(packages_of '{"users":[],"options":{"bootloader":"efistub"}}')"
  grep -qx "limine" <<<"$limine"
  grep -qx "refind" <<<"$refind"
  # efistub needs no extra package beyond efibootmgr (already in base)
  ! grep -qx "grub"   <<<"$efistub"
  ! grep -qx "limine" <<<"$efistub"
  ! grep -qx "refind" <<<"$efistub"
}

@test "changing the kernel selection changes the kernel packages" {
  local lts zen multi
  lts="$(packages_of   '{"users":[],"options":{"kernel":["lts"]}}' kernel)"
  zen="$(packages_of   '{"users":[],"options":{"kernel":["zen"]}}' kernel)"
  multi="$(packages_of '{"users":[],"options":{"kernel":["lts","zen"]}}' kernel)"
  [ "$lts" = "$(printf 'linux-lts\nlinux-lts-headers')" ]
  grep -qx "linux-zen" <<<"$zen"
  [ "$(awk 'END { print NR }' <<<"$multi")" -eq 4 ]
}

@test "changing a user's login shell changes the shell package" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/core" "$test_directory/users/alice"
  printf '{"shell":"/bin/zsh"}\n'  > "$test_directory/users/core/profile.jsonc"
  printf '{"shell":"/bin/fish"}\n' > "$test_directory/users/alice/profile.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"alice\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "fish" ]
  rm -rf "$test_directory"
}

@test "a user with no profile falls back to User Core's shell" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/core"
  printf '{"shell":"/bin/zsh"}\n' > "$test_directory/users/core/profile.jsonc"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"bob\"]}' \
      | awk -F'\t' '\$1 == \"login-shell\" { print \$3 }'"
  [ "$output" = "zsh" ]
  rm -rf "$test_directory"
}

@test "Security and Backup Extras resolve from post_install" {
  local config='{"users":["a"],"post_install":{
    "security":{"firewall":"firewalld","antivirus":true,"rootkit":true,
                "apparmor":true},
    "backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  local security_packages bak
  security_packages="$(packages_of "$config" security)"; bak="$(packages_of "$config" backup)"
  grep -qx "firewalld" <<<"$security_packages"
  grep -qx "clamav"    <<<"$security_packages"
  grep -qx "borg"      <<<"$bak"
  grep -qx "zfs-auto-snapshot" <<<"$bak"
}

@test "toggling a security tool changes the resolved set" {
  local on off
  on="$(packages_of  '{"users":["a"],"post_install":{"security":
    {"firewall":"firewalld","apparmor":true}}}' security)"
  off="$(packages_of '{"users":["a"],"post_install":{"security":
    {"firewall":"none","apparmor":false}}}' security)"
  grep -qx "firewalld" <<<"$on"
  [ -z "$off" ]
}

@test "sops resolves only when the host or a user ships secrets" {
  local test_directory; test_directory="$(mktemp -d)"
  mkdir -p "$test_directory/users/alice" "$test_directory/hosts/box"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"alice\"],\"system\":{\"hostname\":\"box\"}}' \
      | awk -F'\t' '\$1 == \"sops\"'"
  [ -z "$output" ]

  printf '{}' > "$test_directory/users/alice/secrets.json"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[\"alice\"],\"system\":{\"hostname\":\"box\"}}' \
      | awk -F'\t' '\$1 == \"sops\" { print \$3 }'"
  echo "$output" | grep -qx sops
  rm -rf "$test_directory"
}

@test "sops resolves for secrets under the hosts/vm + users/vm fallback" {
  local test_directory config; test_directory="$(mktemp -d)"
  config='{"users":["bob"],"system":{"hostname":"vmbox"}}'
  mkdir -p "$test_directory/hosts/vm/vmbox" "$test_directory/users/vm/bob"
  printf '{}' > "$test_directory/hosts/vm/vmbox/secrets.json"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    _package_resolver_has_secrets '$config'"
  [ "$status" -eq 0 ]

  rm "$test_directory/hosts/vm/vmbox/secrets.json"
  printf '{}' > "$test_directory/users/vm/bob/secrets.json"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    _package_resolver_has_secrets '$config'"
  [ "$status" -eq 0 ]
  rm -rf "$test_directory"
}

# ── LUKS userland follows the per-group rule (ADR 0043) ─────────────────────
# The resolver must report the same LUKS set the install list adds
# (install_config_any_nonzfs_luks): root OR any data pool that is a non-zfs
# ENCRYPTED group — never the global encryption flag alone.

@test "luks: zfs root + encrypted ext4 data pool reports the luks set" {
  local config='{"users":[],"data_pools":[{"name":"tank0",
    "filesystem":"ext4","encryption":true}]}'
  [ -n "$(packages_of "$config" luks)" ]
}

@test "luks: encrypted zfs root + plaintext ext4 data pool reports none" {
  local config='{"users":[],"options":{"encryption":true},
    "data_pools":[{"name":"tank0","filesystem":"ext4"}]}'
  [ -z "$(packages_of "$config" luks)" ]
}

@test "luks: a manual layout reports none even with encryption on (ADR 0073)" {
  local config='{"users":[],"filesystem":"ext4","options":{"encryption":true},
    "disk_config":{"kind":"manual","partitions":[]}}'
  [ -z "$(packages_of "$config" luks)" ]
}
