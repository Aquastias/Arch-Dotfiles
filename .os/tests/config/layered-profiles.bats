#!/usr/bin/env bats
# End-to-end regression over the COMMITTED profiles (ADR 0056/0057).
#
# Resolves the real `core`, `desktop`, `laptop` and VM-fixture profiles through
# the Layer Resolver and asserts the final sets, so a curation mistake fails in
# seconds here rather than in a VM install. This also pins the invariants the
# curation established:
#   - laptop contributes no packages of its own
#   - no Program name appears in any package list
#   - nothing declared duplicates what a derived set already provides
#   - the VM fixtures resolve lean, with no workstation userland

setup() {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  source "$OS_DIR/lib/config/profile.sh"
  source "$OS_DIR/lib/config/layer-resolver.sh"
  source "$OS_DIR/lib/config/layers.sh"
  configs_build_registry
}

# repo_of <profile> / aur_of <profile> — the resolved flat package set.
repo_of() { load_profile "$1" | jq -r '.packages.repo // {}
  | to_entries[].value[]' | sort -u; }
aur_of()  { load_profile "$1" | jq -r '.packages.aur // {}
  | to_entries[].value[]' | sort -u; }
core_repo() { jsonc_strip "$OS_DIR/hosts/core/profile.jsonc" \
  | jq -r '.packages.repo | to_entries[].value[]' | sort -u; }

# ── the committed profiles resolve ──────────────────────────────────────────

@test "core, desktop and laptop all resolve without error" {
  local h
  for h in desktop laptop; do
    run load_profile "$h"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
  done
}

@test "laptop resolves to exactly Host Core's package set" {
  # laptop declares no packages, so its resolved set IS core's — the whole
  # point of the two-layer model for this fleet.
  [ "$(repo_of laptop)" = "$(core_repo)" ]
}

@test "desktop resolves to core plus its own delta, and is a superset" {
  local desk core
  desk="$(repo_of desktop)"; core="$(core_repo)"
  # every core package survives into desktop
  local p
  while IFS= read -r p; do
    grep -qx "$p" <<<"$desk" || { echo "core package missing: $p"; return 1; }
  done <<<"$core"
  # and desktop adds strictly more
  [ "$(wc -l <<<"$desk")" -gt "$(wc -l <<<"$core")" ]
}

@test "desktop's delta packages land in the resolved set" {
  local desk; desk="$(repo_of desktop)"
  local p
  for p in qemu-full libguestfs virt-viewer lutris wine tectonic dnsmasq; do
    grep -qx "$p" <<<"$desk" || { echo "missing desktop delta: $p"; return 1; }
  done
}

@test "core packages reach both machines" {
  local p h
  for h in desktop laptop; do
    local pkgs; pkgs="$(repo_of "$h")"
    for p in firefox steam kitty htop gimp vlc; do
      grep -qx "$p" <<<"$pkgs" || { echo "$h missing core pkg: $p"; return 1; }
    done
  done
}

@test "aur resolves layered too: core on both, delta on desktop only" {
  local d l
  d="$(aur_of desktop)"; l="$(aur_of laptop)"
  local p
  # ttf-ms-fonts left the core AUR list for the options.fonts Font Catalog (ADR
  # 0080) — it is routed to the paru pass by the font resolver, not packages.aur.
  for p in vscodium-bin zen-browser-bin octopi; do
    grep -qx "$p" <<<"$d" || { echo "desktop missing core aur: $p"; return 1; }
    grep -qx "$p" <<<"$l" || { echo "laptop missing core aur: $p"; return 1; }
  done
  grep -qx "brave-bin" <<<"$d"
  ! grep -qx "brave-bin" <<<"$l"
}

# ── no Program name appears in any package list ─────────────────────────────

@test "no Program name appears in any committed package list" {
  local h pkgs p
  for h in desktop laptop; do
    pkgs="$(repo_of "$h"; aur_of "$h")"
    while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      [ "$(program_kind "$p")" = "none" ] \
        || { echo "$h: '$p' is a Program, not a package"; return 1; }
    done <<<"$pkgs"
  done
}

# The three live violations the curation removed.
@test "docker, virt-manager and teamspeak3 are gone from both hosts" {
  local h p
  for h in desktop laptop; do
    local pkgs; pkgs="$(repo_of "$h"; aur_of "$h")"
    for p in docker docker-compose virt-manager teamspeak3; do
      ! grep -qx "$p" <<<"$pkgs" || { echo "$h still declares $p"; return 1; }
    done
  done
}

# ── nothing declared duplicates a derived set ───────────────────────────────

@test "no declared package duplicates the Base Package List" {
  local h p pkgs
  for h in desktop laptop; do
    pkgs="$(repo_of "$h")"
    for p in base base-devel linux-firmware networkmanager openssh cronie \
             efibootmgr dosfstools vim git sudo rsync jq pacman-contrib \
             man-db man-pages texinfo stow; do
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h re-declares base package: $p"; return 1; }
    done
  done
}

@test "no declared package duplicates the derived audio set" {
  local h p pkgs
  for h in desktop laptop; do
    pkgs="$(repo_of "$h")"
    for p in pipewire pipewire-pulse pipewire-alsa wireplumber \
             gst-plugin-pipewire pipewire-jack libpulse; do
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h re-declares derived audio package: $p"; return 1; }
    done
  done
}

@test "no declared package duplicates a derived filesystem tool or shell" {
  local h p pkgs
  for h in desktop laptop; do
    pkgs="$(repo_of "$h")"
    for p in btrfs-progs xfsprogs zsh; do
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h re-declares derived package: $p"; return 1; }
    done
  done
}

@test "no declared package duplicates a KDE-adapter package" {
  local h p pkgs
  for h in desktop laptop; do
    pkgs="$(repo_of "$h")"
    for p in papirus-icon-theme qt5-wayland qt6-wayland xdg-utils sddm-kcm \
             konsole dolphin ark okular kate; do
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h re-declares DE-adapter package: $p"; return 1; }
    done
  done
}

# ── everything CURATION.md marked drop is gone ──────────────────────────────

@test "every dropped package is absent from every committed profile" {
  local h p pkgs
  for h in desktop laptop; do
    pkgs="$(repo_of "$h"; aur_of "$h"; core_repo)"
    for p in zram-generator uwsm nftables iptables wireless_tools less zed \
             flatpak libavif qemu-base vde2 cpio zinit qt6ct-kde \
             btop-theme-catppuccin catppuccin-cursors-mocha \
             catppuccin-gtk-theme-mocha catppuccin-sddm-theme-mocha \
             catppuccin-plasma-colorscheme-mocha \
             catppuccin-konsole-colorscheme-mocha-git \
             papirus-folders-catppuccin-git \
             plymouth-theme-catppuccin-mocha-git; do
      ! grep -qx "$p" <<<"$pkgs" || { echo "$h still declares $p"; return 1; }
    done
  done
}

@test "no catppuccin package survives anywhere" {
  local h
  for h in core desktop laptop; do
    ! grep -q "catppuccin" "$OS_DIR/hosts/$h/profile.jsonc" \
      || { echo "$h still declares a catppuccin package"; return 1; }
  done
}

# ── the VM fixtures resolve lean ────────────────────────────────────────────

@test "the VM fixtures inherit no packages from Host Core" {
  local h
  for h in arch-data arch-kde arch-secure; do
    run load_profile "$h"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '(.packages.repo // {}) == {}'
    echo "$output" | jq -e '(.packages.aur // {}) == {}'
  done
}

@test "the VM fixtures pull in no workstation userland" {
  local h p pkgs
  for h in arch-data arch-kde arch-secure; do
    pkgs="$(repo_of "$h")"
    for p in steam firefox gimp discord wine lutris kitty; do
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h pulled workstation package: $p"; return 1; }
    done
  done
}

# inherit is scoped to packages — the fixtures still get core's users/sysctl.
# cups is no longer among core's system programs (ADR 0079): it is
# toggle-derived and injected at assembly, so the loaded profile inherits no
# system programs from core here.
@test "the VM fixtures still inherit Host Core's sysctl" {
  local h
  for h in arch-data arch-kde arch-secure; do
    run load_profile "$h"
    echo "$output" | jq -e '.sysctl["vm.swappiness"] == 10'
    echo "$output" | jq -e '.host_programs | index("cups") | not'
  done
}

# ── promoted Core-Owned Programs (ADR 0089) ─────────────────────────────────
# Packages the installer once pacstrapped bare, now kind:host Programs with a
# single home: absent from packages.repo, present in host_programs on the real
# hosts, and excluded on the lean VM fixtures.

host_programs_of() { load_profile "$1" | jq -r '.host_programs // [] | .[]'; }

@test "promoted Core-Owned Programs resolve into host_programs, not packages" {
  local h p pkgs hp
  for h in desktop laptop; do
    pkgs="$(repo_of "$h")"; hp="$(host_programs_of "$h")"
    for p in ccache reflector smartmontools fwupd; do
      grep -qx "$p" <<<"$hp" \
        || { echo "$h missing host program: $p"; return 1; }
      ! grep -qx "$p" <<<"$pkgs" \
        || { echo "$h still declares $p as a package"; return 1; }
    done
  done
}

@test "the VM fixtures exclude the promoted Core-Owned Programs" {
  local h p hp
  for h in arch-data arch-kde arch-secure; do
    hp="$(host_programs_of "$h")"
    for p in ccache reflector smartmontools fwupd; do
      ! grep -qx "$p" <<<"$hp" \
        || { echo "$h did not exclude host program: $p"; return 1; }
    done
  done
}

# ── the user layer ──────────────────────────────────────────────────────────

@test "a real user inherits User Core's programs and zsh shell" {
  run load_user_profile aquastias
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.programs | index("docker")'
  echo "$output" | jq -e '.programs | index("virt-manager")'
  echo "$output" | jq -e '.shell == "/bin/zsh"'
}

@test "the throwaway test users exclude User Core's programs" {
  local u
  for u in vm-test vm-data; do
    run load_user_profile "$u"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.programs | index("docker") | not'
    echo "$output" | jq -e '.programs | index("virt-manager") | not'
  done
}

@test "the control keys never reach a resolved profile" {
  local h
  for h in desktop laptop arch-kde; do
    run load_profile "$h"
    echo "$output" | jq -e '(.packages // {}) | has("inherit") | not'
    echo "$output" | jq -e '(.packages // {}) | has("exclude") | not'
    echo "$output" | jq -e 'has("host_programs_exclude") | not'
  done
  run load_user_profile vm-test
  echo "$output" | jq -e 'has("programs_exclude") | not'
}
