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
  done < <(printf '%s\n' "$output")
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
  output_has_line $'repo\tcore\thtop'      # core declares it
  output_has_line $'repo\thost\tripgrep'   # this profile adds it
  output_has_line $'aur\thost\tbrave-bin'
  output_has_line $'base\tderived\tbase'
  rm -rf "$test_directory"
}

@test "with no Host Core to compare against, authored slots read authored" {
  local test_directory; test_directory="$(mktemp -d)"
  INSTALLER_DIR="$test_directory" run bash -c "
    source '$BATS_TEST_DIRNAME/../../lib/common.sh'
    source '$BATS_TEST_DIRNAME/../../lib/packages/package-resolver.sh'
    package_resolver_resolve '{\"users\":[],\"packages\":{\"repo\":{\"c\":[\"htop\"]}}}'"
  output_has_line $'repo\tauthored\thtop'
  rm -rf "$test_directory"
}


# ── each derived set tracks the setting that drives it ──────────────────────

@test "changing the GPU vendor changes the resolved driver set" {
  local amd nvidia intel
  amd="$(packages_of '{"users":[],"environment":{"gpu":["amd"]}}' gpu)"
  nvidia="$(packages_of '{"users":[],"environment":{"gpu":["nvidia"]}}' gpu)"
  intel="$(packages_of '{"users":[],"environment":{"gpu":["intel"]}}' gpu)"

  text_has_line "$amd" "vulkan-radeon"
  text_has_line "$nvidia" "nvidia-open-dkms"
  text_has_line "$intel" "intel-media-driver"
  [ "$amd" != "$nvidia" ]
  [ "$nvidia" != "$intel" ]
}

@test "a hybrid GPU config resolves both vendors' drivers" {
  local both; both="$(packages_of '{"users":[],
    "environment":{"gpu":["amd","nvidia"]}}' gpu)"
  text_has_line "$both" "vulkan-radeon"
  text_has_line "$both" "nvidia-open-dkms"
  text_has_line "$both" "nvidia-prime" # prime-run (ADR 0161)
}

@test "changing the desktop selection changes the audio and Plasma sets" {
  local none kde
  none="$(packages_of '{"users":[],"environment":{"desktop":[]}}')"
  kde="$(packages_of  '{"users":[],"environment":{"desktop":["kde"],"stock":false}}')"

  ! text_has_line "$none" "pipewire"
  ! text_has_line "$none" "plasma-meta"
  text_has_line "$kde" "pipewire"
  text_has_line "$kde" "wireplumber"
  text_has_line "$kde" "plasma-meta"
  text_has_line "$kde" "konsole"
}


# ── niri core set (ADR 0090) ────────────────────────────────────────────────

@test "niri-shell set reports the niri core packages" {
  source "$INSTALLER_DIR/lib/packages/niri.sh"
  local got want
  got="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' niri-shell)"
  want="$(niri_core_packages | sort)"
  [ "$(printf '%s\n' "$got" | sort)" = "$want" ]
  text_has_line "$got" "niri"
  text_has_line "$got" "seatd"
}

@test "niri-shell set is empty when niri is not selected" {
  local got
  got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' niri-shell)"
  [ -z "$got" ]
}

@test "noctalia set reports the work preset when wayland_shell defaults on" {
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  text_has_line "$noctalia_packages" "noctalia"
  text_has_line "$noctalia_packages" "kitty"
  text_has_line "$noctalia_packages" "brightnessctl"
  text_has_line "$noctalia_packages" "playerctl"   # media-key backend (ADR 0096)
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
  text_has_line "$noctalia_packages" "noctalia"
  text_has_line "$noctalia_packages" "kitty"
  text_has_line "$noctalia_packages" "playerctl"
  text_has_line "$noctalia_packages" "smartmontools"   # drive-health: a shared-core plugin dep
  text_has_line "$noctalia_packages" "socat"   # hypr-submap/screen-mirror: hypr-slice dep
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
  text_has_line "$shell" "plasma-meta"
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
  ! text_has_line "$noctalia_packages" "bitwarden-cli"
}

@test "noctalia set reports enriched plugin tool deps (ADR 0093/0094)" {
  # committed install-noctalia.jsonc enables the curated plugin set by default
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  text_has_line "$noctalia_packages" "smartmontools"   # drive-health
  text_has_line "$noctalia_packages" "wl-mirror"    # wl-screen-mirror
  text_has_line "$noctalia_packages" "fzf"    # file-search
  text_has_line "$noctalia_packages" "ollama"    # llamanager
  text_has_line "$noctalia_packages" "iw"    # hotspot
  text_has_line "$noctalia_packages" "bind"    # dns-switcher
  ! text_has_line "$noctalia_packages" "docker"    # mini-docker was dropped (ADR 0094)
}

@test "noctalia set reports upower from the base preset, not the battery pair" {
  # upower is in the base preset; the resolver has no hardware, so laptop:auto
  # still reports no battery plugin of its own
  local noctalia_packages
  noctalia_packages="$(packages_of '{"users":[],"environment":{"desktop":["niri"],"stock":false}}' noctalia)"
  [ "$(printf '%s\n' "$noctalia_packages" | grep -cx upower)" -eq 1 ]
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
  output_has_line $'noctalia\tderived\tupower'
  rm -rf "$test_directory"
}


# ── display manager derived set (ADR 0069) ──────────────────────────────────

@test "display-manager set: auto on a kde-only box resolves to sddm" {
  local display_manager_packages
  display_manager_packages="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' display-manager)"
  text_has_line "$display_manager_packages" "sddm"
  ! text_has_line "$display_manager_packages" "greetd"
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
  text_has_line "$display_manager_packages" "sddm"
  ! text_has_line "$display_manager_packages" "greetd"
}

@test "display-manager set: an explicit greetd on a kde box wins over auto" {
  local display_manager_packages
  display_manager_packages="$(packages_of \
    '{"users":[],"environment":{"desktop":["kde"],"stock":false,"display_manager":"greetd"}}' \
    display-manager)"
  text_has_line "$display_manager_packages" "greetd"
  text_has_line "$display_manager_packages" "greetd-tuigreet"
  ! text_has_line "$display_manager_packages" "sddm"
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
  text_has_line "$kdeshell" "sddm-kcm"
  ! text_has_line "$kdeshell" "sddm"
}

# Drift guard (Candidate 5): the KDE adapter installs shell_packages from
# install-kde.jsonc and the resolver reports them — assert the resolver's
# kde-shell set equals the jsonc data, so install and query cannot diverge.
@test "kde-shell source == install-kde.jsonc shell + curated shell packages" {
  source "$INSTALLER_DIR/lib/config/categorized-list.sh"
  local json expected got stock_expected stock_got shell_json curated_json
  json="$(jsonc_strip "$INSTALLER_DIR/extras/desktop/kde/install-kde.jsonc")"
  # The adapter's two shell lists.
  shell_json="$(printf '%s\n' "$json" | jq -c '.shell_packages')"
  curated_json="$(printf '%s\n' "$json" | jq -c '.curated_shell_packages')"
  stock_expected="$(categorized_list_parse "$shell_json" bool shell_packages \
    | sort -u)"
  expected="$({ printf '%s\n' "$stock_expected"; categorized_list_parse \
    "$curated_json" bool curated_shell_packages; } | sort -u)"
  got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' kde-shell)"
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got")
  # stock KDE reports the shell_packages alone (ADR 0157)
  stock_got="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":true}}' kde-shell)"
  diff <(printf '%s\n' "$stock_expected") <(printf '%s\n' "$stock_got")
}

@test "kde-shell set includes the packaged weather widget (ADR 0120)" {
  local shell
  shell="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' kde-shell)"
  text_has_line "$shell" "plasma-applets-weather-widget-3" \
    || { echo "kde-shell missing plasma-applets-weather-widget-3"; return 1; }
}

@test "kde extra-apps set includes orca and vlc (ADR 0120)" {
  local apps
  apps="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' \
    kde-apps-extra)"
  text_has_line "$apps" "orca" || { echo "extra-apps missing orca"; return 1; }
  text_has_line "$apps" "vlc" || { echo "extra-apps missing vlc";  return 1; }
}

@test "the derived audio set covers the formerly hand-declared packages" {
  local audio_packages; audio_packages="$(packages_of '{"users":[],"environment":{"desktop":["kde"],"stock":false}}' audio)"
  local package
  for package in gst-plugin-pipewire pipewire-jack libpulse; do
    text_has_line "$audio_packages" "$package" || { echo "audio set missing: $package"; return 1; }
  done
}

@test "changing the filesystem changes the filesystem-tool set" {
  local zfs btrfs xfs
  zfs="$(packages_of   '{"users":[],"filesystem":"zfs"}')"
  btrfs="$(packages_of '{"users":[],"filesystem":"btrfs"}')"
  xfs="$(packages_of   '{"users":[],"filesystem":"xfs"}')"

  text_has_line "$zfs" "zfs-dkms"
  ! text_has_line "$btrfs" "zfs-dkms"
  text_has_line "$btrfs" "btrfs-progs"
  text_has_line "$xfs" "xfsprogs"
}

@test "a per-group filesystem contributes its tools too" {
  local packages; packages="$(packages_of '{"users":[],"filesystem":"zfs",
    "data_pools":[{"name":"t","filesystem":"btrfs"}]}')"
  text_has_line "$packages" "zfs-dkms"
  text_has_line "$packages" "btrfs-progs"
}

@test "changing the bootloader changes the bootloader package" {
  local systemd_boot_packages grub
  systemd_boot_packages="$(packages_of   '{"users":[],"options":{"bootloader":"systemd-boot"}}')"
  grub="$(packages_of '{"users":[],"options":{"bootloader":"grub"}}')"
  ! text_has_line "$systemd_boot_packages" "grub"
  text_has_line "$grub" "grub"
}

@test "new loaders resolve their manifest package (ADR 0077)" {
  local limine refind efistub
  limine="$(packages_of  '{"users":[],"options":{"bootloader":"limine"}}')"
  refind="$(packages_of  '{"users":[],"options":{"bootloader":"refind"}}')"
  efistub="$(packages_of '{"users":[],"options":{"bootloader":"efistub"}}')"
  text_has_line "$limine" "limine"
  text_has_line "$refind" "refind"
  # efistub needs no extra package beyond efibootmgr (already in base)
  ! text_has_line "$efistub" "grub"
  ! text_has_line "$efistub" "limine"
  ! text_has_line "$efistub" "refind"
}

@test "changing the kernel selection changes the kernel packages" {
  local lts zen multi
  lts="$(packages_of   '{"users":[],"options":{"kernel":["lts"]}}' kernel)"
  zen="$(packages_of   '{"users":[],"options":{"kernel":["zen"]}}' kernel)"
  multi="$(packages_of '{"users":[],"options":{"kernel":["lts","zen"]}}' kernel)"
  [ "$lts" = "$(printf 'linux-lts\nlinux-lts-headers')" ]
  text_has_line "$zen" "linux-zen"
  [ "$(printf '%s\n' "$multi" | wc -l)" -eq 4 ]
}

@test "Security and Backup Extras resolve from post_install" {
  local config='{"users":["a"],"post_install":{
    "security":{"firewall":"firewalld","antivirus":true,"rootkit":true,
                "apparmor":true},
    "backup":{"zfs_auto_snapshot":true,"borg":true}}}'
  local security_packages bak
  security_packages="$(packages_of "$config" security)"; bak="$(packages_of "$config" backup)"
  text_has_line "$security_packages" "firewalld"
  text_has_line "$security_packages" "clamav"
  text_has_line "$bak" "borg"
  text_has_line "$bak" "zfs-auto-snapshot"
}

@test "toggling a security tool changes the resolved set" {
  local on off
  on="$(packages_of  '{"users":["a"],"post_install":{"security":
    {"firewall":"firewalld","apparmor":true}}}' security)"
  off="$(packages_of '{"users":["a"],"post_install":{"security":
    {"firewall":"none","apparmor":false}}}' security)"
  text_has_line "$on" "firewalld"
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

@test "gpu set: no lib32 package when [multilib] is off" {
  local gpu_packages
  gpu_packages="$(packages_of \
    '{"users":[],"environment":{"gpu":"nvidia"},"options":{"optional_repos":[]}}' gpu)"
  text_has_line "$gpu_packages" "nvidia-utils"
  [[ $'\n'"$gpu_packages" != *$'\nlib32-'* ]]  # no lib32-* package
}
