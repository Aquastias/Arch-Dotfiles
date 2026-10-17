#!/usr/bin/env bats
# Tests: consent and users (split from shell.bats;
# shared setup in shell-helpers.bash)

load shell-helpers


# ── the typed INSTALL is the sole consent gate ─────────────────────────────

@test "guided_build: aborts with no config when INSTALL is not typed" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=nope')"

  run guided_build
  [ "$status" -ne 0 ]
  # nothing installable leaks to stdout
  refute_json() { ! echo "$1" | jq -e 'has("mode")' 2>/dev/null; }
  refute_json "$(guided_build 2>/dev/null)"
}


# ── in-menu credentials (ticket 03): load the handoff file into held-aside vars ─

@test "_guided_shell_load_secrets_file: populates root + user passwords from the file" {
  _GUIDED_ROOT_PASSWORD=""
  _GUIDED_USER_PASSWORDS=()
  local secrets_file; secrets_file="$(mktemp)"
  printf '%s\n' \
    '{"root_password":"r00t","users":{"aquastias":{"password":"aq"}}}' > "$secrets_file"
  _guided_shell_load_secrets_file "$secrets_file"
  rm -f "$secrets_file"
  [ "$_GUIDED_ROOT_PASSWORD" = "r00t" ]
  [ "${_GUIDED_USER_PASSWORDS[aquastias]}" = "aq" ]
}

@test "_guided_shell_load_secrets_file: an empty/missing file is a no-op" {
  _GUIDED_ROOT_PASSWORD="kept"
  _GUIDED_USER_PASSWORDS=()
  _guided_shell_load_secrets_file "/nonexistent/secrets.json"
  [ "$_GUIDED_ROOT_PASSWORD" = "kept" ]
}

@test "in-menu secrets feed the no-SOPS manifest (never the Config State)" {
  _GUIDED_ROOT_PASSWORD=""
  _GUIDED_USER_PASSWORDS=()
  local secrets_file; secrets_file="$(mktemp)"
  printf '%s\n' '{"root_password":"r","users":{"alex":{"password":"a"}}}' > "$secrets_file"
  _guided_shell_load_secrets_file "$secrets_file"; rm -f "$secrets_file"
  run _guided_shell_secrets_manifest
  [ "$(jq -r '.root_password' <<<"$output")" = "r" ]
  [ "$(jq -r '.users.alex.password' <<<"$output")" = "a" ]
}


# ── a persistent-path created user (name only) gets a default profile ─────────

@test "_guided_shell_materialize_users: a created user without a profile gets a default" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"users":["newbie"]}'
  _GUIDED_ADHOC_ORDER=()
  _guided_shell_materialize_users
  [ -f "$INSTALLER_DIR/users/newbie/profile.jsonc" ]
  jq -e '.sudo == true and (.groups | index("wheel"))
    and (.programs | index("searxng"))' \
    "$INSTALLER_DIR/users/newbie/profile.jsonc"
}


# ── issue 04: In-Menu Disk Binding resolves without a post-menu pick ──────────

@test "_guided_shell_resolve_assignment: a fully-bound layout picks no disks" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"mode":"multi","os_pool":{"topology":"mirror",
    "devices":["/dev/disk/by-id/a","/dev/disk/by-id/b"]}}'
  # would fail loudly if the bound path ever reached the flat picker
  guided_pick_disks() { echo CALLED; return 1; }
  run _guided_shell_resolve_assignment
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q CALLED
  echo "$output" | jq -e '.os_pool == ["/dev/disk/by-id/a","/dev/disk/by-id/b"]'
}

@test "_guided_shell_resolve_assignment: single mode uses the in-menu root disk" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"mode":"single","root_disk":"/dev/disk/by-id/root"}'
  _GUIDED_DISK=""
  run _guided_shell_resolve_assignment
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single" and .disk == "/dev/disk/by-id/root"'
}


# ── slice 02: install-scoped User Editor deltas merged onto the clone ─────────

@test "_guided_shell_apply_userforms: merges a shell delta, keeps the committed delta" {
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  # committed delta carries groups; the edit only changes shell
  printf '{"groups":["docker"],"shell":"/bin/bash"}' \
    > "$INSTALLER_DIR/users/alice/profile.jsonc"
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_shell_apply_userforms
  jq -e '.shell == "/bin/zsh"' "$INSTALLER_DIR/users/alice/profile.jsonc"
  jq -e '.groups == ["docker"]' "$INSTALLER_DIR/users/alice/profile.jsonc"  # delta kept
}

@test "_guided_shell_apply_userforms: no-op when no deltas were held aside" {
  mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  _GUIDED_USERFORMS_JSON=''
  _guided_shell_apply_userforms
  jq -e '.shell == "/bin/bash"' "$INSTALLER_DIR/users/alice/profile.jsonc"   # untouched
}


# ── slice 04: Save-warn — committed profiles never rewritten ─────────────────

@test "_guided_shell_committed_userform_edits: reports committed users, not ad-hoc" {
  mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  # dave has NO committed profile → session-created, must not be reported
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"},"dave":{"shell":"/bin/fish"}}'
  run _guided_shell_committed_userform_edits
  echo "$output" | grep -qx alice
  ! echo "$output" | grep -qx dave
}

@test "_guided_shell_apply_userforms save: does NOT rewrite a committed profile" {
  mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" alice "
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_shell_apply_userforms save
  jq -e '.shell == "/bin/bash"' "$INSTALLER_DIR/users/alice/profile.jsonc"   # untouched
}

@test "_guided_shell_apply_userforms save: still applies to a session-created user" {
  mkdir -p "$INSTALLER_DIR/users/dave"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/dave/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" "     # dave was not committed at start
  _GUIDED_USERFORMS_JSON='{"dave":{"shell":"/bin/zsh"}}'
  _guided_shell_apply_userforms save
  jq -e '.shell == "/bin/zsh"' "$INSTALLER_DIR/users/dave/profile.jsonc"
}

@test "_guided_shell_apply_userforms proceed: DOES apply to a committed profile" {
  mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" alice "
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_shell_apply_userforms proceed
  jq -e '.shell == "/bin/zsh"' "$INSTALLER_DIR/users/alice/profile.jsonc"
}


# ── headless replay: `profile=<name>` seeds the state (ADR 0055) ─────────────

@test "_guided_shell_seed_from_profile: replay 'profile=' re-baselines the session" {
  mkdir -p "$INSTALLER_DIR/hosts/desktop"
  cat > "$INSTALLER_DIR/hosts/desktop/profile.jsonc" <<'JSONC'
{ "system": { "hostname": "eterniox" },
  "options": { "encryption": true }, "filesystem": "zfs" }
JSONC
  guided_load_replay "$(write_answers 'profile=desktop')"
  _GUIDED_STATE='{"marker":1}'
  _guided_shell_seed_from_profile
  jq -e '.options.encryption == true' <<<"$_GUIDED_BASELINE"
  jq -e '.filesystem == "zfs"' <<<"$_GUIDED_BASELINE"
  jq -e '.system.hostname == "eterniox"' <<<"$_GUIDED_BASELINE"
  jq -e '. == {}' <<<"$_GUIDED_STATE"       # earlier overrides dropped
}

@test "_guided_shell_seed_from_profile: no 'profile=' key leaves the state untouched" {
  guided_load_replay "$(write_answers 'hostname=x')"
  _GUIDED_STATE='{"marker":1}'
  _guided_shell_seed_from_profile
  jq -e '.marker == 1' <<<"$_GUIDED_STATE"
}

@test "_guided_shell_seed_from_profile: an unknown profile is a no-op" {
  guided_load_replay "$(write_answers 'profile=ghost')"
  _GUIDED_STATE='{"marker":1}'
  _guided_shell_seed_from_profile
  jq -e '.marker == 1' <<<"$_GUIDED_STATE"
}


# ── one-select install (ADR 0055): replay `profile=` assembles the machine ───
# The same assembly path the VM drives via install.sh --guided. Proves a seeded
# profile flows all the way to the Effective Config with no field answers and no
# password answers (secrets default to 12345 via the manifest, tested separately).

@test "guided_build: replay 'profile=' assembles the seeded machine end-to-end" {
  mkdir -p "$INSTALLER_DIR/hosts/laptop"
  cat > "$INSTALLER_DIR/hosts/laptop/profile.jsonc" <<'JSONC'
{ "system": { "hostname": "chronos" },
  "filesystem": "zfs", "mode": "single", "ashift": 12,
  "options": { "encryption": true,
               "impermanence": { "enabled": true },
               "ssh": { "enabled": true } },
  "persist": { "directories": ["/home"] } }
JSONC
  guided_load_replay "$(write_answers \
    'profile=laptop' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "chronos"'
  echo "$effective" | jq -e '.filesystem == "zfs"'
  echo "$effective" | jq -e '.options.encryption == true'
  echo "$effective" | jq -e '.options.impermanence.enabled == true'
  echo "$effective" | jq -e '.options.ssh.enabled == true'
  echo "$effective" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  echo "$effective" | jq -e '.persist.directories == ["/home"]'
}

@test "guided_build: a field answer overrides the seeded profile value" {
  mkdir -p "$INSTALLER_DIR/hosts/laptop"
  printf '%s\n' '{"system":{"hostname":"chronos"},"mode":"single","ashift":12}' \
    > "$INSTALLER_DIR/hosts/laptop/profile.jsonc"
  guided_load_replay "$(write_answers \
    'profile=laptop' \
    'hostname=override' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.system.hostname == "override"'   # answer wins
}


# ── manual partitioning replay (ADR 0073): a scripted table replaces cfdisk

@test "guided_build: manual_disk replays Manual Partitioning onto that disk" {
  source "$BATS_TEST_DIRNAME/../../lib/config/manual-partition.sh"
  local lsblk="$TEST_DIR/lsblk"
  cat > "$lsblk" <<'SH'
#!/usr/bin/env bash
cat <<'J'
{"blockdevices":[{"path":"/dev/vda","type":"disk","children":[
 {"path":"/dev/vda1","type":"part","fstype":null,
  "parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
  "parttypename":"EFI System"},
 {"path":"/dev/vda2","type":"part","fstype":null,
  "parttype":"0657fd6d-a4ab-43c4-84e5-0933c84b4f4f",
  "parttypename":"Linux swap"},
 {"path":"/dev/vda3","type":"part","fstype":null,
  "parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4",
  "parttypename":"Linux filesystem"}]}]}
J
SH
  chmod +x "$lsblk"
  export MANUAL_LSBLK_CMD="$lsblk"
  guided_load_replay "$(write_answers hostname=box manual_disk=/dev/vda \
    confirm=INSTALL)"
  run guided_build 2>/dev/null
  [ "$status" -eq 0 ]
  local config; config="$(printf '%s\n' "$output" | awk '/^\{/ { found = 1 } found')"
  [ "$(jq -r .disk_config.kind <<<"$config")" = "manual" ]
  [ "$(jq -r '.disk_config.partitions[]
    | select(.mountpoint == "/") | .device' <<<"$config")" = "/dev/vda3" ]
  [ "$(jq -r '.disk_config.partitions[]
    | select(.mountpoint == "/boot/efi") | .device' <<<"$config")" = "/dev/vda1" ]
}

@test "guided_build: the manual review says the table is kept, not erased" {
  source "$BATS_TEST_DIRNAME/../../lib/config/manual-partition.sh"
  manual_partition_lsblk_json() { printf '%s' '{"blockdevices":[{"path":"/dev/vda",
    "type":"disk","children":[{"path":"/dev/vda1","type":"part",
    "fstype":null,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4",
    "parttypename":"Linux filesystem"}]}]}'; }
  guided_load_replay "$(write_answers hostname=box manual_disk=/dev/vda \
    confirm=INSTALL)"
  run guided_build
  [[ "$output" != *"WILL ERASE"* ]]
  [[ "$output" == *"no wipe"* ]]
}
