# impermanence-tool-helpers.bash — shared setup for the impermanence-tool-*.bats parts
# Tests for .installer/tools/impermanence.sh — operator CLI for Persist
# Extensions.
#
# Strategy: redirect filesystem writes under $FAKEROOT via env overrides.
# Stub systemctl/zfs (in $BIN_STUBS, first on PATH) to log argv to $CALLS.

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKEROOT="$TEST_DIR/root"
  CALLS="$TEST_DIR/calls.log"
  BIN_STUBS="$TEST_DIR/bin"
  mkdir -p "$FAKEROOT" "$BIN_STUBS"
  export TEST_DIR FAKEROOT CALLS BIN_STUBS

  TOOL="$BATS_TEST_DIRNAME/../tools/impermanence.sh"
  export TOOL

  MOCK_STATE="$TEST_DIR/mock"
  mkdir -p "$MOCK_STATE"
  : > "$MOCK_STATE/list-units"
  : > "$MOCK_STATE/fragment-paths"
  : > "$MOCK_STATE/what-paths"
  # All Rollback Datasets @blank present by default.
  cat > "$MOCK_STATE/zfs-snapshots" <<EOF
rpool/ROOT/etc@blank
rpool/ROOT/opt@blank
rpool/ROOT/srv@blank
rpool/ROOT/usrlocal@blank
EOF
  export MOCK_STATE

  cat > "$BIN_STUBS/zfs" <<'ZFS'
#!/usr/bin/env bash
printf 'zfs %s\n' "$*" >> "$CALLS"
case "$1" in
  list)
    name="${@: -1}"
    if grep -qxF "$name" "$MOCK_STATE/zfs-snapshots"; then
      echo "$name"; exit 0
    fi
    exit 1
    ;;
  diff)
    ds="${@: -1}"
    safe="${ds//\//_}"
    cat "$MOCK_STATE/zfs-diff-$safe" 2>/dev/null
    exit 0
    ;;
esac
ZFS
  chmod +x "$BIN_STUBS/zfs"

  export IMPERMANENCE_RPOOL=rpool

  cat > "$BIN_STUBS/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$CALLS"
case "$1" in
  list-units) cat "$MOCK_STATE/list-units" ;;
  show)
    # systemctl show -p <Prop> --value <unit>
    unit="${@: -1}"
    case "$3" in
      What) grep "^$unit " "$MOCK_STATE/what-paths" 2>/dev/null | awk '{print $2}' ;;
      *)    grep "^$unit " "$MOCK_STATE/fragment-paths" | awk '{print $2}' ;;
    esac
    ;;
esac
STUB
  chmod +x "$BIN_STUBS/systemctl"
  PATH="$BIN_STUBS:$PATH"
  export PATH

  # Default env: impermanence "enabled" (persist mount exists, manifest empty).
  export IMPERMANENCE_ROOT="$FAKEROOT"
  export IMPERMANENCE_MOUNT="$FAKEROOT/persist"
  export IMPERMANENCE_MANIFEST="$FAKEROOT/usr/lib/impermanence/defaults.manifest"
  export IMPERMANENCE_HOSTNAME="testhost"
  export IMPERMANENCE_HOSTS_DIR="$FAKEROOT/os/hosts"
  mkdir -p "$IMPERMANENCE_MOUNT" \
           "${IMPERMANENCE_MANIFEST%/*}" \
           "$IMPERMANENCE_HOSTS_DIR/testhost"
  : > "$IMPERMANENCE_MANIFEST"
  cat > "$IMPERMANENCE_HOSTS_DIR/testhost/profile.jsonc" <<'JSONC'
{
  "persist": {
    "directories": [],
    "files": []
  }
}
JSONC
}

teardown() { rm -rf "$TEST_DIR"; }

# Helper: a "live" file under FAKEROOT, ready to be persisted.
seed_live_file() {
  local path="$1"
  mkdir -p "$IMPERMANENCE_ROOT${path%/*}"
  echo "live-data" > "$IMPERMANENCE_ROOT$path"
}

seed_live_directory() {
  local path="$1"
  mkdir -p "$IMPERMANENCE_ROOT$path"
  echo "live-data" > "$IMPERMANENCE_ROOT$path/marker"
}

# Seed a persisted state: file is already on /persist, unit + tmpfiles exist,
# and the host config declares it. This is the state `add` leaves behind.
seed_persisted_file() {
  local target="$1"
  seed_live_file "$target"
  "$TOOL" add "$target"
  : > "$CALLS"  # clear add's systemctl calls
}

# Seed live data for all Curated Persist Defaults under $IMPERMANENCE_ROOT.
seed_all_curated_live() {
  local curated_path
  for curated_path in /etc/machine-id /etc/hostname /etc/locale.conf \
           /etc/vconsole.conf /etc/adjtime /etc/fstab; do
    mkdir -p "$IMPERMANENCE_ROOT${curated_path%/*}"
    echo "x" > "$IMPERMANENCE_ROOT$curated_path"
  done
  for curated_path in /etc/ssh /etc/secrets /etc/NetworkManager/system-connections \
           /etc/sudoers.d /etc/pacman.d /root; do
    mkdir -p "$IMPERMANENCE_ROOT$curated_path"
  done
}

# A real host: profile dir `desktop`, machine hostname pinned to `eterniox`.
seed_pinned_profile() {
  mkdir -p "$IMPERMANENCE_HOSTS_DIR/desktop"
  cat > "$IMPERMANENCE_HOSTS_DIR/desktop/profile.jsonc" <<'JSONC'
{
  // hostname differs from the profile directory name
  "system": { "hostname": "eterniox" },
  "persist": {
    "directories": ["/home"],
    "files": []
  }
}
JSONC
}

