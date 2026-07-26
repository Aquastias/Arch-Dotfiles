#!/usr/bin/env bats
# Tests for .os/lib/config/profiles.sh — the Guided Installer's Profiles picker
# core (ADR 0055): enumerate installable Host Profiles + seed a Config State from
# one. Pure: a hosts/ tree or JSON in, names / text / state out, no TTY.
#
# Behaviour under test (external only — the names, header text, and seeded state
# the helpers emit), never internal structure. Prior art: guided-seed.bats,
# guided-state.bats.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/state.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  # shellcheck source=../../lib/config/skeleton.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/skeleton.sh"
  # shellcheck source=../../lib/config/profiles.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profiles.sh"

  # A fixture hosts/ tree: core (excluded), two real profiles, a vm tree
  # (excluded), a skeleton-less dir (no profile.jsonc → excluded).
  HOSTS="$(mktemp -d "${BATS_TMPDIR:-/tmp}/hosts.XXXXXX")"
  mkdir -p "$HOSTS"/{core,desktop,laptop,vm/arch-kde,notes}
  printf '{}\n' > "$HOSTS/core/profile.jsonc"
  printf '{}\n' > "$HOSTS/vm/arch-kde/profile.jsonc"
  cat > "$HOSTS/desktop/profile.jsonc" <<'JSONC'
// Host Profile for `desktop` (eterniox).
// 2x NVMe mirror + 3x SSD raidz1.
{ "system": { "hostname": "eterniox" }, "options": { "encryption": true } }
JSONC
  # laptop: no leading header comment at all.
  printf '{ "system": { "hostname": "chronos" } }\n' \
    > "$HOSTS/laptop/profile.jsonc"
}

teardown() { rm -rf "$HOSTS"; }

# ── tracer: enumeration lists the two installable profiles, alphabetical ─────

@test "profiles_list: lists desktop + laptop, alphabetical" {
  run profiles_list "$HOSTS"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "desktop" ]
  [ "${lines[1]}" = "laptop" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "profiles_list: excludes core (the merge base)" {
  run profiles_list "$HOSTS"
  ! grep -qx core <<<"$output"
}

@test "profiles_list: excludes the vm/ harness tree" {
  run profiles_list "$HOSTS"
  ! grep -qx vm <<<"$output"
  ! grep -qx arch-kde <<<"$output"
}

@test "profiles_list: excludes a dir with no profile.jsonc" {
  run profiles_list "$HOSTS"
  ! grep -qx notes <<<"$output"
}

# ── header comment: stripped prose for the preview pane ─────────────────────

@test "profiles_header: returns the // block with markers stripped" {
  run profiles_header "$HOSTS" desktop
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Host Profile for \`desktop\` (eterniox)." ]
  [ "${lines[1]}" = "2x NVMe mirror + 3x SSD raidz1." ]
}

@test "profiles_header: empty for a header-less profile" {
  run profiles_header "$HOSTS" laptop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── seed-merge: profile values win, seed fields survive ─────────────────────

@test "profiles_seed: profile values win over the seeded state" {
  state="$(cfgstate_set "$(cfgstate_new)" system.hostname '"seeded"')"
  state="$(cfgstate_set "$state" system.keymap '"us"')"
  profile='{"system":{"hostname":"eterniox"},"options":{"encryption":true}}'

  run profiles_seed "$state" "$profile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'   # profile wins
  echo "$output" | jq -e '.system.keymap == "us"'           # seed survives
  echo "$output" | jq -e '.options.encryption == true'
}

@test "profiles_seed: introduces no device paths (flattened)" {
  profile='{"os_pool":{"pool_name":"rpool","topology":"mirror",
            "devices":["/dev/disk/by-id/a","/dev/disk/by-id/b"]}}'
  run profiles_seed "$(cfgstate_new)" "$profile"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.os_pool | has("devices") | not'
  echo "$output" | jq -e '.os_pool.disk_count == 2'   # count derived
}
