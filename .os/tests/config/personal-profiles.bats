#!/usr/bin/env bats
# Tests for the committed personal Host Profiles hosts/{desktop,laptop} (ADR
# 0055): both are encrypted, SSH-enabled ZFS machines (desktop impermanent;
# laptop persistent-root) that load and validate clean against the closed
# schema. Behaviour under test: the
# effective config the loader produces + validate_profile's verdict — never how
# the profile file is laid out. Prior art: profile-loader.bats.

setup() {
  export OS_DIR="$BATS_TEST_DIRNAME/../.."
  info()    { :; }
  warn()    { :; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { :; }
  export -f info warn error section

  # shellcheck source=../../lib/config/profile.sh
  source "$OS_DIR/lib/config/profile.sh"
}

# ── each profile merges with core and carries the new machine shape ─────────

flags_on() {  # <profile-name>
  load_profile "$1" | jq -e '
    .filesystem == "zfs"
    and .options.encryption == true
    and .options.impermanence.enabled == true
    and .options.ssh.enabled == true'
}

persists() {  # <profile-name>
  load_profile "$1" | jq -e '
    (.persist.directories // []) as $d
    | ($d | index("/home")) != null
      and ($d | index("/var/lib/docker")) != null
      and ($d | index("/var/lib/libvirt")) != null'
}

@test "desktop: encrypted, impermanent, ssh-enabled zfs" {
  flags_on desktop
}

@test "laptop: encrypted, ssh-enabled zfs (impermanence disabled)" {
  load_profile laptop | jq -e '
    .filesystem == "zfs"
    and .options.encryption == true
    and (.options.impermanence.enabled // false) == false
    and .options.ssh.enabled == true'
}

@test "desktop: persists /home + docker + libvirt" {
  persists desktop
}

@test "laptop: has no impermanence persist block (persistent root)" {
  load_profile laptop | jq -e '(.persist // null) == null'
}

# ── the layouts are unchanged (desktop multi mirror+raidz1, laptop single) ──

@test "desktop: keeps its rpool mirror x2 + data raidz1 x3 layout" {
  run load_profile desktop
  echo "$output" | jq -e '.mode == "multi"'
  echo "$output" | jq -e '.os_pool.topology == "mirror" and .os_pool.disk_count == 2'
  echo "$output" | jq -e '.storage_groups[0].topology == "raidz1"
                          and .storage_groups[0].disk_count == 3'
}

@test "laptop: keeps its single-disk layout" {
  run load_profile laptop
  echo "$output" | jq -e '.mode == "single"'
}

# ── validate-at-load passes for both (closed schema + config-sanity) ────────

@test "desktop: validate_profile passes" {
  run validate_profile desktop
  [ "$status" -eq 0 ]
}

@test "laptop: validate_profile passes" {
  run validate_profile laptop
  [ "$status" -eq 0 ]
}
