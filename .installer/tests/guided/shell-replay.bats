#!/usr/bin/env bats
# Tests: session replay (split from shell.bats;
# shared setup in shell-helpers.bash)

load shell-helpers


# ── tracer: a replayed session assembles the single-disk Effective Config ───

@test "guided_build: a replayed session assembles the Effective Config" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  # stdout is the Effective Config; the review screen goes to stderr.
  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "eterniox"'
  echo "$effective" | jq -e '.mode == "single"'
  echo "$effective" | jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"'
  # Seeded defaults derive the section System Programs (ADR 0079/0080/0089):
  # cups (printing), bluetooth, power-profiles-daemon (power), reflector
  # (mirrors), in inject order.
  echo "$effective" \
    | jq -e '.host_programs
        == ["cups","bluetooth","power-profiles-daemon","reflector"]'
}


# ── issue 09: a built non-zfs root filesystem is selectable in replay ───────

@test "guided_build: a replayed btrfs root filesystem commits (built adapter)" {
  guided_load_replay "$(write_answers \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'filesystem=btrfs' \
    'confirm=INSTALL')"
  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.filesystem == "btrfs"'
}


# ── an untouched run is ready to install on the seeded defaults (issue 01) ──

@test "guided_build: an untouched run emits the seeded defaults" {
  guided_load_replay "$(write_answers \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "eterniox"'
  echo "$effective" | jq -e '.users == ["aquastias"]'
  echo "$effective" | jq -e '.mode == "single"'
  echo "$effective" | jq -e '.system.locale == "en_US.UTF-8"'
  echo "$effective" | jq -e '.system.timezone == "Europe/Bucharest"'
  echo "$effective" | jq -e '.system.keymap == "us"'
}


# ── Save of an untouched run records the Primary User explicitly (issue 01) ──

@test "guided_build: an untouched Save writes a profile with the Primary User" {
  guided_load_replay "$(write_answers \
    'terminal=save' 'save_name=eterniox')"

  run guided_build
  [ "$status" -eq 64 ]
  jq -e '.users == ["aquastias"]' "$INSTALLER_DIR/hosts/eterniox/profile.jsonc"
  jq -e '.system.hostname == "eterniox"' "$INSTALLER_DIR/hosts/eterniox/profile.jsonc"
}


# ── editing a Host identity row overrides the seed in the emitted config ─────

@test "guided_build: editing locale overrides the seed in the emitted config" {
  guided_load_replay "$(write_answers \
    'locale=de_DE.UTF-8' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.locale == "de_DE.UTF-8"'
}


# ── a replayed session carries the Disks choices into the Effective Config ──

@test "guided_build: a replayed session emits filesystem/encryption/impermanence/persist" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'filesystem=zfs' \
    'encryption=true' \
    'impermanence=true' \
    'persist_dir=/etc/wireguard' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.filesystem == "zfs"'
  echo "$effective" | jq -e '.options.encryption == true'
  echo "$effective" | jq -e '.options.impermanence.enabled == true'
  echo "$effective" | jq -e '.persist.directories == ["/etc/wireguard"]'
}


# ── a replayed session carries the Options + Environment choices (issue 05) ─

@test "guided_build: a replayed session emits Options + Environment fields" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'kernel=zen lts' \
    'bootloader=grub' \
    'swap=false' \
    'swap_size=8G' \
    'esp_size=4G' \
    'ssh=true' \
    'age_key_url=https://example.test/key.age' \
    'desktop=kde' \
    'gpu=amd nvidia' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.options.kernel == ["zen","lts"]'
  echo "$effective" | jq -e '.options.bootloader == "grub"'
  echo "$effective" | jq -e '.options.swap == false'
  echo "$effective" | jq -e '.options.swap_size == "8G"'
  echo "$effective" | jq -e '.options.esp_size == "4G"'
  echo "$effective" | jq -e '.options.ssh.enabled == true'
  echo "$effective" | jq -e '.options.age_key_url == "https://example.test/key.age"'
  echo "$effective" | jq -e '.environment.desktop == ["kde"]'
  echo "$effective" | jq -e '.environment.gpu == ["amd","nvidia"]'
}


# ── a replayed session carries the Options / Packages / Security / Backup fields
# (the old Pacman + Advanced answers; dotfiles_repo is gone — issue 02)

@test "guided_build: a replayed session emits Options/Packages/post_install" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'mirror_countries=Japan Australia' \
    'optional_repos=core-testing' \
    'package=htop tmux' \
    'sysctl=vm.swappiness=20' \
    'firewall=ufw' \
    'antivirus=false' \
    'borg=false' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.options.mirror_countries == ["Japan","Australia"]'
  echo "$effective" | jq -e '.options.optional_repos == ["core-testing"]'
  echo "$effective" | jq -e '.packages.repo.extra == ["htop","tmux"]'
  echo "$effective" | jq -e '.sysctl["vm.swappiness"] == 20'
  # Structured Security/Backup object: overrides merge over the secure baseline.
  echo "$effective" | jq -e '.post_install.security.firewall == "ufw"'
  echo "$effective" | jq -e '.post_install.security.antivirus == false'
  echo "$effective" | jq -e '.post_install.security.rootkit == true'
  echo "$effective" | jq -e '.post_install.backup.borg == false'
  echo "$effective" | jq -e '.post_install.backup.zfs_auto_snapshot == true'
  # dotfiles_repo is removed entirely — never emitted
  echo "$effective" | jq -e 'has("dotfiles_repo") | not'
}


# ── set -e safety: install.sh runs the guided front-end under `set -Eeuo
# pipefail`. A replay file declares only a few fields; every other edit no-ops
# (returns non-zero "no commit"). Those no-ops must NOT abort the run. ─────────

@test "guided_build: a partial replay survives install.sh's set -e" {
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"
  # The $( ) subshell contains set -e exactly like install.sh:268 calling
  # guided_build under `set -Eeuo pipefail`. An abort empties effective.
  effective="$(set -Eeuo pipefail; guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.system.hostname == "eterniox"'
  echo "$effective" | jq -e '.post_install.security.firewall == "firewalld"'
}

@test "guided_build: a partial replay does not spuriously fire install.sh's ERR trap" {
  # install.sh installs an ERR trap (set -E inherits it into guided_build). A
  # no-op replay edit must not fire it — else the install log fills with bogus
  # "aborted at line N" noise that masks a real abort.
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"
  errs="$( (set -Eeuo pipefail; trap 'echo SPURIOUS-ERR-TRAP >&2' ERR; \
    guided_build >/dev/null) 2>&1 )"
  [[ "$errs" != *SPURIOUS-ERR-TRAP* ]]
}


# ── terminal actions (issue 08): Save profile + Export config ───────────────

@test "guided_build: a replayed Save writes a device-less profile, no install" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'bootloader=grub' \
    'terminal=save' \
    'save_name=eterniox')"

  run guided_build
  [ "$status" -eq 64 ]                       # action done — no back-end install
  [ -f "$INSTALLER_DIR/hosts/eterniox/profile.jsonc" ]
  jq -e 'has("disk") | not' "$INSTALLER_DIR/hosts/eterniox/profile.jsonc"   # device-less
  jq -e '.options.bootloader == "grub"' "$INSTALLER_DIR/hosts/eterniox/profile.jsonc"
}

@test "guided_build: a replayed Save refuses an ad-hoc user that already exists" {
  mkdir -p "$INSTALLER_DIR/users/carol"
  printf 'KEEP\n' > "$INSTALLER_DIR/users/carol/profile.jsonc"
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'new_user_name=carol' 'new_user_password=x' \
    'terminal=save' 'save_name=eterniox')"

  run guided_build
  [ "$status" -ne 0 ]
  [ "$status" -ne 64 ]
  [ "$(cat "$INSTALLER_DIR/users/carol/profile.jsonc")" = "KEEP" ]   # untouched
  [ ! -f "$INSTALLER_DIR/hosts/eterniox/profile.jsonc" ]             # host not committed
}

@test "guided_build: a replayed Export writes the device-baked config to a path" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'terminal=export' \
    "export_path=$TEST_DIR/out/eterniox.effective.jsonc")"

  run guided_build
  [ "$status" -eq 64 ]
  [ -f "$TEST_DIR/out/eterniox.effective.jsonc" ]
  jq -e '.disk == "/dev/disk/by-id/wwn-0xDEAD"' \
    "$TEST_DIR/out/eterniox.effective.jsonc"   # device-baked
}


# ── a replayed ad-hoc user is materialized; passwords go only to the manifest ─

@test "guided_build: an ad-hoc user is materialized + passwords manifested, none leak" {
  export GUIDED_SECRETS_MANIFEST="$TEST_DIR/manifest.json"
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'new_user_name=carol' 'new_user_shell=/bin/zsh' 'new_user_sudo=true' \
    'new_user_groups=' 'new_user_programs=' 'new_user_git_name=' \
    'new_user_git_email=' 'new_user_ssh_keys=' 'new_user_password=hunter2' \
    'root_password=r00t' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  # ad-hoc user joins the host users[] after the seeded Primary User (aquastias
  # stays first); its User Profile is materialized.
  echo "$effective" | jq -e '.users == ["aquastias","carol"]'
  [ -f "$INSTALLER_DIR/users/carol/profile.jsonc" ]
  jq -e '.shell == "/bin/zsh" and .sudo == true' \
    "$INSTALLER_DIR/users/carol/profile.jsonc"
  # passwords land ONLY in the side manifest — never in the Effective Config
  echo "$effective" | jq -e 'has("root_password") | not'
  echo "$effective" | jq -e '(.. | objects | has("password")) // false | not' \
    2>/dev/null || true
  jq -e '.root_password == "r00t"' "$GUIDED_SECRETS_MANIFEST"
  jq -e '.users.carol.password == "hunter2"' "$GUIDED_SECRETS_MANIFEST"
}


# ── the encryption passphrase round-trips handoff file → manifest (ADR 0054) ──

@test "secrets: an enc passphrase in the handoff file lands in the manifest" {
  _guided_shell_users_reset
  local secrets_file="$TEST_DIR/secrets.json"
  printf '%s\n' '{"enc_passphrase":"corrhorse","root_password":"r00t"}' > "$secrets_file"
  _guided_shell_load_secrets_file "$secrets_file"
  [ "$_GUIDED_ENCRYPTION_PASSPHRASE" = "corrhorse" ]
  run _guided_shell_secrets_manifest
  echo "$output" | jq -e '.enc_passphrase == "corrhorse"'
  echo "$output" | jq -e '.root_password == "r00t"'
}

@test "secrets: no enc_passphrase key when none was captured" {
  _guided_shell_users_reset
  run _guided_shell_secrets_manifest
  echo "$output" | jq -e 'has("enc_passphrase") | not'
}


# ── Advanced freeform authoring: build an arbitrary skeleton group by group ─

@test "_guided_shell_author_skeleton: replay authors the OS pool + a storage group" {
  guided_load_replay "$(write_answers \
    'adv_os_topology=mirror' 'adv_os_disk_count=2' \
    'adv_storage_count=1' 'adv_storage_0_name=data' \
    'adv_storage_0_topology=raidz1' 'adv_storage_0_disk_count=3' \
    'adv_data_count=0')"
  _GUIDED_STATE="$(config_state_new)"

  _guided_shell_author_skeleton
  echo "$_GUIDED_STATE" | jq -e '.mode == "multi"'
  echo "$_GUIDED_STATE" | jq -e '.os_pool.topology == "mirror"'
  echo "$_GUIDED_STATE" | jq -e '.storage_groups[0].name == "data"'
  echo "$_GUIDED_STATE" | jq -e '.storage_groups[0].disk_count == 3'
}

@test "guided_build: a replayed Advanced session bakes the authored skeleton" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=advanced' \
    'adv_os_topology=mirror' 'adv_os_disk_count=2' \
    'adv_storage_count=1' 'adv_storage_0_name=data' \
    'adv_storage_0_topology=raidz1' 'adv_storage_0_disk_count=3' \
    'adv_data_count=0' \
    'disks=/dev/disk/by-id/A /dev/disk/by-id/B /dev/disk/by-id/C /dev/disk/by-id/D /dev/disk/by-id/E' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.os_pool.topology == "mirror"'
  echo "$effective" | jq -e '(.os_pool.disks | length) == 2'
  echo "$effective" | jq -e '.storage_groups[0].topology == "raidz1"'
  echo "$effective" | jq -e '(.storage_groups[0].disks | length) == 3'
}


# ── a replayed MULTI-disk session bakes the preset skeleton's disks (issue 04)

@test "guided_build: a replayed os-mirror session bakes the 2-disk OS mirror" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=os-mirror' \
    'disks=/dev/disk/by-id/wwn-A /dev/disk/by-id/wwn-B' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  [ -n "$effective" ]
  echo "$effective" | jq -e '.mode == "multi"'
  echo "$effective" | jq -e '.os_pool.topology == "mirror"'
  echo "$effective" | jq -e \
    '.os_pool.disks == ["/dev/disk/by-id/wwn-A","/dev/disk/by-id/wwn-B"]'
}

@test "guided_build: a multi session with the wrong disk count aborts" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'layout=os-mirror' \
    'disks=/dev/disk/by-id/wwn-A' \
    'accept_layout=ACCEPT' \
    'confirm=INSTALL')"

  run guided_build
  [ "$status" -ne 0 ]
}


# ── the config must carry the back-end's required identity fields ───────────
# (validation.sh requires system.locale + system.timezone; the tracer defaults
#  them — issue 05 turns these into live-system-picked menu rows.)

@test "guided_build: the config carries the required identity defaults" {
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.system.locale and .system.timezone'
  echo "$effective" | jq -e '.system.keymap'
}


# ── filesystem-first Disks: all four adapters ship, none reserved (issue 09) ─

@test "_guided_shell_filesystem_options: all four built filesystems are active" {
  run _guided_shell_filesystem_options
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "zfs"
  echo "$output" | grep -qx "btrfs"
  echo "$output" | grep -qx "ext4"
  echo "$output" | grep -qx "xfs"
  # Every adapter is built now, so nothing is flagged reserved.
  ! echo "$output" | grep -q "reserved"
}

@test "_guided_shell_edit_filesystem: picking zfs commits the filesystem" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "zfs"; }
  export -f guided_select

  _guided_shell_edit_filesystem
  [ "$(config_state_get "$_GUIDED_STATE" filesystem)" = "zfs" ]
}

@test "_guided_shell_edit_filesystem: a reserved filesystem is refused, no commit" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  # All four adapters ship today, so exercise the reserved seam (kept for a
  # future unbuilt adapter) with an injected reserved filesystem.
  _GUIDED_FS_RESERVED=(reiserfs)
  guided_select() { printf '%s' "reiserfs (reserved)"; }
  export -f guided_select

  run _guided_shell_edit_filesystem
  [ "$status" -ne 0 ]
  [ -z "$(config_state_get "$_GUIDED_STATE" filesystem)" ]
}


# ── encryption / impermanence are bool toggles through the seam ─────────────

@test "_guided_shell_edit_encryption: selecting true enables encryption" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_shell_edit_encryption
  echo "$_GUIDED_STATE" | jq -e '.options.encryption == true'
}

@test "_guided_shell_edit_impermanence: selecting true enables impermanence" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_shell_edit_impermanence
  echo "$_GUIDED_STATE" | jq -e '.options.impermanence.enabled == true'
}
