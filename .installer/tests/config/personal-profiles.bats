#!/usr/bin/env bats
# Tests for the committed personal Host Profiles hosts/{desktop,laptop} (ADR
# 0055): both are encrypted, SSH-enabled ZFS machines (desktop impermanent;
# laptop persistent-root) that load and validate clean against the closed
# schema. Behaviour under test: the
# effective config the loader produces + profile_loader_validate's verdict — never how
# the profile file is laid out. Prior art: profile-loader.bats.

setup() {
  export INSTALLER_DIR="$BATS_TEST_DIRNAME/../.."
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile-loader.sh
  source "$INSTALLER_DIR/lib/config/profile-loader.sh"
}

# ── each profile merges with core and carries the new machine shape ─────────

flags_on() {  # <profile-name>
  profile_loader_load "$1" | jq -e '
    .filesystem == "zfs"
    and .options.encryption == true
    and .options.impermanence.enabled == true
    and .options.ssh.enabled == true'
}

persists() {  # <profile-name>
  profile_loader_load "$1" | jq -e '
    (.persist.directories // []) as $d
    | ($d | index("/home")) != null
      and ($d | index("/var/lib/docker")) != null
      and ($d | index("/var/lib/libvirt")) != null'
}

@test "desktop: encrypted, impermanent, ssh-enabled zfs" {
  flags_on desktop
}

# Discord (extra repo) is a fleet app declared in Host Core, so it resolves onto
# both real machines (desktop, laptop) with no per-profile packages block.
@test "discord (from core) resolves onto desktop and laptop" {
  profile_loader_load desktop | jq -e '[.packages.repo[]?[]?] | index("discord")'
  profile_loader_load laptop  | jq -e '[.packages.repo[]?[]?] | index("discord")'
}

@test "laptop: encrypted, ssh-enabled zfs (impermanence disabled)" {
  profile_loader_load laptop | jq -e '
    .filesystem == "zfs"
    and .options.encryption == true
    and (.options.impermanence.enabled // false) == false
    and .options.ssh.enabled == true'
}

@test "desktop: persists /home + docker + libvirt" {
  persists desktop
}

@test "laptop: has no impermanence persist block (persistent root)" {
  profile_loader_load laptop | jq -e '(.persist // null) == null'
}

# ── the layouts are unchanged (desktop multi mirror+raidz1, laptop single) ──

@test "desktop: keeps its rpool mirror x2 + data raidz1 x3 layout" {
  run profile_loader_load desktop
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror" and .os_pool.disk_count == 2'
  echo "$output" | jq -e '.storage_groups[0].topology == "raidz1"
                          and .storage_groups[0].disk_count == 3'
}

@test "laptop: keeps its single-disk layout" {
  run profile_loader_load laptop
  echo "$output" | jq -e '.mode == "single"'
}

# ── validate-at-load passes for both (closed schema + config-sanity) ────────

@test "desktop: profile_loader_validate passes" {
  run profile_loader_validate desktop
  [ "$status" -eq 0 ]
}

@test "laptop: profile_loader_validate passes" {
  run profile_loader_validate laptop
  [ "$status" -eq 0 ]
}
