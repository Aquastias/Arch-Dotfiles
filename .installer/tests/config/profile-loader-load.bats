#!/usr/bin/env bats
# Tests: loading and merging (split from profile-loader.bats;
# shared setup in profile-loader-helpers.bash)

load profile-loader-helpers


# ── profile_loader_load: real profile.jsonc + core merge ──────────────────────────

@test "profile_loader_load: merges real host profile.jsonc with core" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":["alice"],"host_programs":["cups"]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["bob"],"system":{"hostname":"eterniox"}}'

  run profile_loader_load desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice","bob"]'
  echo "$output" | jq -e '.host_programs == ["cups"]'
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "profile_loader_load: finds a VM host profile.jsonc under hosts/vm/<name>" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"host_programs":["cups"]}'
  write_jsonc "$INSTALLER_DIR/hosts/vm/arch-data/profile.jsonc" \
    '{"users":["vm-data"],"mode":"multi"}'

  run profile_loader_load arch-data
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["vm-data"]'
  echo "$output" | jq -e '.host_programs == ["cups"]'
  echo "$output" | jq -e '.mode == "multi"'
}


# ── no dual-read: the loader reads ONLY profile.jsonc (issue 10) ───────────
# The transient scaffold is gone: a sibling legacy config.jsonc is ignored,
# and a host with no profile.jsonc yields core-only (rc 1), never a config
# synthesized from the legacy files.

@test "profile_loader_load: ignores a sibling legacy config.jsonc (reads only profile)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"host_programs":["cups"]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" '{"users":["bob"]}'
  # a leftover legacy config.jsonc with conflicting content must not be read
  write_jsonc "$INSTALLER_DIR/hosts/desktop/config.jsonc" \
    '{"users":["LEGACY"],"host_programs":["LEGACY"]}'

  run profile_loader_load desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["bob"]'
  echo "$output" | jq -e '.host_programs == ["cups"]'
}

@test "profile_loader_load: missing host profile.jsonc → core only, rc 1 (no synth)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"host_programs":["cups"]}'
  # a legacy config.jsonc exists but must NOT be synthesized in
  write_jsonc "$INSTALLER_DIR/hosts/desktop/config.jsonc" '{"users":["LEGACY"]}'

  run profile_loader_load desktop
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.host_programs == ["cups"]'
  echo "$output" | jq -e '(.users // []) == []'
}


# ── user path: profile.jsonc + user core (symmetric with the host path) ─────

@test "profile_loader_load_user: merges real user profile.jsonc with core" {
  write_jsonc "$INSTALLER_DIR/users/core/profile.jsonc" \
    '{"shell":"/bin/bash","groups":["audio"]}'
  write_jsonc "$INSTALLER_DIR/users/aquastias/profile.jsonc" \
    '{"sudo":true,"groups":["video"]}'

  run profile_loader_load_user aquastias
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '.sudo == true'
  echo "$output" | jq -e '.groups == ["audio","video"]'
}

@test "profile_loader_load_user: missing user profile.jsonc → core only, rc 1 (no synth)" {
  write_jsonc "$INSTALLER_DIR/users/core/profile.jsonc" '{"shell":"/bin/bash"}'
  # a legacy user config.jsonc exists but must NOT be synthesized in
  write_jsonc "$INSTALLER_DIR/users/aquastias/config.jsonc" '{"sudo":true}'

  run profile_loader_load_user aquastias
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.shell == "/bin/bash"'
  echo "$output" | jq -e '(.sudo // false) == false'
}


# ── loader contract: exit codes, merge rules, JSONC (moved from configs.bats) ─

@test "profile_loader_load: missing core profile.jsonc is a hard error (exit 2)" {
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" '{"users":["alice"]}'

  run profile_loader_load desktop
  [ "$status" -eq 2 ]
  [[ "$output" =~ "missing host core profile" ]]
}

@test "profile_loader_load: 'core' as host name is rejected (exit 3)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":["alice"]}'

  run profile_loader_load core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "profile_loader_load_user: 'core' as user name is rejected (exit 3)" {
  write_jsonc "$INSTALLER_DIR/users/core/profile.jsonc" '{"shell":"/bin/bash"}'

  run profile_loader_load_user core
  [ "$status" -eq 3 ]
  [[ "$output" =~ "reserved name" ]]
}

@test "profile_loader_load: arrays concat+dedupe, objects deep-merge, scalars win" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" \
    '{"users":["alice","shared"],"system":{"timezone":"UTC"}}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"users":["shared","bob"],"system":{"hostname":"eterniox"}}'

  run profile_loader_load desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice","shared","bob"]'
  echo "$output" | jq -e '.system.timezone == "UTC"'
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "profile_loader_load: JSONC // comments are stripped before parsing" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{
  // comment on its own line
  "users": ["alice"], // trailing comment
  "host_programs": ["cups"]
}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" '{}'

  run profile_loader_load desktop
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.users == ["alice"]'
  echo "$output" | jq -e '.host_programs == ["cups"]'
}


# ── profile_loader_assemble_config: the --profile effective-config seam ────────────
# Composes profile_loader_load + picker_assign_disks + the dirname-is-identity
# hostname fallback (ADR 0036) into the transient effective config the
# install back-end consumes. Pure: no disks, no TTY.

@test "profile_loader_assemble_config: hostname falls back to the profile name" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/arch-kde/profile.jsonc" \
    '{"environment":{"desktop":["kde"]}}'

  run profile_loader_assemble_config arch-kde '{"mode":"single","disk":"/dev/sda"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "arch-kde"'
  echo "$output" | jq -e '.mode == "single"'
  echo "$output" | jq -e '.disk == "/dev/sda"'
  echo "$output" | jq -e 'has("host_profile") | not'
}

@test "profile_loader_assemble_config: a profile-set hostname wins over the name" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"system":{"hostname":"eterniox"}}'

  run profile_loader_assemble_config desktop '{"mode":"single","disk":"/dev/sda"}'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.system.hostname == "eterniox"'
}

@test "profile_loader_assemble_config: under-populated raidz1 aborts (min-disk)" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/srv/profile.jsonc" \
    '{"os_pool":{"topology":"raidz1"}}'

  run profile_loader_assemble_config srv \
    '{"mode":"multi","os_pool":["/dev/sda","/dev/sdb"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"raidz1"* ]]
}


# ── closed-schema validation: reject unknown keys at any depth ──────────────
# Any key the schema does not enumerate aborts with the offending path,
# before any disk-touching phase (ADR 0036, amends ADR 0015).

@test "validate: unknown top-level key in host profile aborts with its path" {
  run profile_loader_validate_schema host '{"optionz":{"bootloader":"grub"}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"optionz"* ]]
}

@test "validate: unknown nested key aborts with the full path" {
  run profile_loader_validate_schema host \
    '{"options":{"impermanence":{"enabld":true}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.impermanence.enabld"* ]]
}


# ── ADR 0134 user keys: programs_inherit + config_exclude ───────────────────

@test "validate: programs_inherit is accepted on a user profile" {
  run profile_loader_validate_schema user '{"programs_inherit":false,"programs":["zsh"]}'
  [ "$status" -eq 0 ]
}

@test "validate: config_exclude is accepted on a user profile" {
  run profile_loader_validate_schema user '{"config_exclude":["kitty"]}'
  [ "$status" -eq 0 ]
}

@test "validate: an unknown user key still aborts with its path" {
  run profile_loader_validate_schema user '{"programz":["zsh"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"programz"* ]]
}

@test "validate: programs as an object is rejected (stays an array)" {
  # ADR 0134: programs_inherit is a sibling key, never a {inherit,list} reshape.
  run profile_loader_validate_schema user '{"programs":{"inherit":false}}'
  [ "$status" -ne 0 ]
}


# ── retired wire format aborts (ADR 0084 migration) ─────────────────────────
# The Host Program field was renamed system_programs → host_programs (no alias).
# The closed schema enforces the hard cutover: the old key is now unknown.

@test "validate: the retired system_programs key aborts with its path" {
  run profile_loader_validate_schema host '{"system_programs":["grub"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"system_programs"* ]]
}

@test "validate: the retired system_programs_exclude key aborts" {
  run profile_loader_validate_schema host '{"system_programs_exclude":["grub"]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"system_programs_exclude"* ]]
}


# ── the collapsed package slots (ticket 02) ─────────────────────────────────
# packages.extra was packages.repo without a category; packages.groups was
# authored by no profile and shared a namespace with the derived GPU/audio
# buckets. Both left the schema, so naming either aborts with its path rather
# than silently doing nothing.

@test "validate: packages.extra aborts with its path" {
  run profile_loader_validate_schema host '{"packages":{"extra":["htop"]}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"packages.extra"* ]]
}

@test "validate: packages.groups aborts with its path" {
  run profile_loader_validate_schema host '{"packages":{"groups":{"cli":["htop"]}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"packages.groups"* ]]
}

@test "validate: authoring the derived gpu/audio bucket aborts" {
  run profile_loader_validate_schema host '{"packages":{"groups":{"gpu":["mesa"]}}}'
  [ "$status" -ne 0 ]
  run profile_loader_validate_schema host \
    '{"packages":{"groups":{"audio":["pipewire"]}}}'
  [ "$status" -ne 0 ]
}

@test "validate: packages.repo categories still pass" {
  run profile_loader_validate_schema host \
    '{"packages":{"repo":{"extra":["htop"]},"aur":{"misc":["x"]}}}'
  [ "$status" -eq 0 ]
}

@test "validate: the options.zswap.* keys are accepted (closed schema)" {
  run profile_loader_validate_schema host \
    '{"options":{"zswap":{"enabled":true,"compressor":"zstd","max_pool_percent":20}}}'
  [ "$status" -eq 0 ]
}

@test "validate: a typo under options.zswap aborts with its path" {
  run profile_loader_validate_schema host '{"options":{"zswap":{"enabld":true}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.zswap.enabld"* ]]
}

@test "validate: the options.pacman.* keys are accepted (ADR 0074)" {
  run profile_loader_validate_schema host \
    '{"options":{"pacman":{"ilovecandy":true,"color":true,
      "verbose_pkg_lists":true,"disable_download_timeout":false,
      "no_progress_bar":false,"parallel_downloads":5}}}'
  [ "$status" -eq 0 ]
}

@test "validate: a typo under options.pacman aborts with its path" {
  run profile_loader_validate_schema host '{"options":{"pacman":{"ilovcandy":true}}}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"options.pacman.ilovcandy"* ]]
}

@test "validate: unknown key in storage_groups[] aborts with its path" {
  run profile_loader_validate_schema host \
    '{"storage_groups":[{"name":"g","bogus":1}]}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"storage_groups[].bogus"* ]]
}

@test "validate: host_profile is dropped — the dirname is the identity" {
  # ADR 0036: host_profile is no longer a config field; --profile / the
  # host directory name is the identity. A leftover host_profile now aborts.
  run profile_loader_validate_schema host '{"host_profile":"desktop"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"host_profile"* ]]
}

@test "validate: unknown key in a user profile aborts" {
  run profile_loader_validate_schema user '{"shel":"/bin/zsh"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"shel"* ]]
}

@test "validate: unknown key in a program config aborts" {
  run profile_loader_validate_schema program \
    '{"name":"x","kind":"host","desc":"y"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"desc"* ]]
}

@test "validate: a typo'd program 'kind' key is caught (misroute guard)" {
  run profile_loader_validate_schema program \
    '{"name":"x","kidn":"host","description":"y"}'
  [ "$status" -ne 0 ]
  [[ "$output" == *"kidn"* ]]
}


# ── positive: representative valid configs pass clean ──────────────────────

@test "validate: system.locale and system.keymap accept arrays (issue 04)" {
  run profile_loader_validate_schema host \
    '{"system":{"locale":["en_US.UTF-8","de_DE.UTF-8"],"keymap":["us","de"]}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a legacy scalar system.locale/keymap still validates" {
  run profile_loader_validate_schema host \
    '{"system":{"locale":"en_US.UTF-8","keymap":"us"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: options.ssh.enabled is accepted (issue 05)" {
  run profile_loader_validate_schema host '{"options":{"ssh":{"enabled":true}}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: system.console_font is accepted (ADR 0076)" {
  run profile_loader_validate_schema host '{"system":{"console_font":"ter-116n"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: filesystem + options.encryption_method are accepted (ADR 0040)" {
  run profile_loader_validate_schema host \
    '{"filesystem":"zfs","options":{"encryption_method":"native"}}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: per-group filesystem/encryption are accepted (ADR 0043)" {
  run profile_loader_validate_schema host '{
    "data_pools":[{"name":"tank0","filesystem":"ext4","encryption":true}],
    "storage_groups":[{"name":"bulk","filesystem":"btrfs","encryption":false}]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a representative valid host profile passes" {
  run profile_loader_validate_schema host '{
    "system":{"hostname":"eterniox","locale":"en_US.UTF-8","keymap":"us"},
    "options":{"bootloader":"grub","impermanence":{"enabled":true}},
    "environment":{"desktop":["kde"],"gpu":"amd"},
    "storage_groups":[{"name":"g","topology":"mirror","owners":["a","@t"]}],
    "data_pools":[{"name":"tank","disks":["/dev/sdb"]}],
    "sysctl":{"vm.swappiness":10},
    "packages":{"repo":{"shell":["zsh"],"dev":["git"]}},
    "users":["aquastias"],"host_programs":["grub"]
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a user profile accepts user_services[] (issue 06)" {
  run profile_loader_validate_schema user \
    '{"programs":["neovim"],"user_services":["podman.socket","syncthing"]}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a representative valid user profile passes" {
  run profile_loader_validate_schema user '{
    "shell":"/bin/zsh","sudo":true,"groups":["audio","video"],
    "programs":["neovim"],"ssh_authorized_keys":[],
    "git":{"name":"A","email":"a@b.c"}
  }'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "validate: a valid program config passes" {
  run profile_loader_validate_schema program \
    '{"name":"x","kind":"user","description":"y"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


# ── drift guard: reads (accessors.sh) and validation share the key set ─────
# Every _INSTALL_CONFIG_SCHEMA read-path must be a key the closed schema
# accepts; otherwise a field could be read but rejected (or vice versa).

@test "drift guard: every _INSTALL_CONFIG_SCHEMA read-path is a valid host key" {
  # shellcheck source=../../lib/config/install-config.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/install-config.sh"
  local spec name path kind default j
  for spec in "${_INSTALL_CONFIG_SCHEMA[@]}"; do
    IFS='|' read -r name path kind default <<< "$spec"
    j="$(jq -n "$path = \"x\"")" || { echo "bad jq path: $path"; return 1; }
    run profile_loader_validate_schema host "$j"
    [ "$status" -eq 0 ] \
      || { echo "read-path '$path' ($name) rejected by closed schema: $output"; \
           return 1; }
  done
}

# ── the Fleet Layer folds for `"fleet": true` hosts only (ADR 0157) ─────────

@test "profile_loader_load: a fleet: true host folds the Fleet Layer" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{"users":[]}'
  write_jsonc "$INSTALLER_DIR/hosts/fleet/profile.jsonc" \
    '{"host_programs":["lact"]}'
  write_jsonc "$INSTALLER_DIR/hosts/mybox/profile.jsonc" '{"fleet":true}'
  write_jsonc "$INSTALLER_DIR/hosts/guest/profile.jsonc" '{}'

  run profile_loader_load mybox
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.host_programs == ["lact"]'
  run profile_loader_load guest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.host_programs // []) == []'
}

# ── profile_loader_name_for_hostname (ADR 0020: hostname ≠ profile name) ────

@test "profile_loader_name_for_hostname: maps a hostname to its profile" {
  # desktop installs hostname eterniox; the installer only knows the hostname.
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{}'
  write_jsonc "$INSTALLER_DIR/hosts/desktop/profile.jsonc" \
    '{"system":{"hostname":"eterniox"}}'
  write_jsonc "$INSTALLER_DIR/hosts/laptop/profile.jsonc" \
    '{"system":{"hostname":"chronos"}}'
  run profile_loader_name_for_hostname eterniox
  [ "$output" = "desktop" ]
  run profile_loader_name_for_hostname chronos
  [ "$output" = "laptop" ]
}

@test "profile_loader_name_for_hostname: a profile without hostname matches its dir" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{}'
  write_jsonc "$INSTALLER_DIR/hosts/vm/arch-niri/profile.jsonc" '{}'
  run profile_loader_name_for_hostname arch-niri
  [ "$output" = "arch-niri" ]
}

@test "profile_loader_name_for_hostname: no match falls back to the hostname" {
  write_jsonc "$INSTALLER_DIR/hosts/core/profile.jsonc" '{}'
  run profile_loader_name_for_hostname adhoc-box
  [ "$output" = "adhoc-box" ]
}
