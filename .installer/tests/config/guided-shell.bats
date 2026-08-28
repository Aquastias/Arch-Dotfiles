#!/usr/bin/env bats
# Tests for .os/lib/guided.sh — the Guided Installer's fzf shell (ADR 0039).
# The shell is impure glue, but its selection seam (guided_select /
# guided_prompt) is replayable: under a GUIDED_REPLAY answers file the menu
# is driven headlessly, no fzf, no tty. So guided_build — the assembly path —
# is exercised deterministically here; the fzf rendering stays smoke-only.
#
# Behaviour under test (external only — the Effective Config a replayed
# session assembles, and the INSTALL consent gate), never internal structure.

setup() {
  TEST_DIR="$(mktemp -d)"
  export OS_DIR="$TEST_DIR"

  # Mirror common.sh faithfully: info/warn/section echo to STDOUT, error to
  # stderr. guided_build's only stdout MUST be the Effective Config — any human
  # output (the review screen) has to be redirected, so these stdout stubs are
  # the guard that catches stdout pollution.
  info()    { echo "[info] $*"; }
  warn()    { echo "[warn] $*"; }
  error()   { echo "[error] $*" >&2; return 1; }
  section() { echo "== $* =="; }
  export -f info warn error section

  mkdir -p "$OS_DIR/hosts/core"
  printf '%s\n' \
    '{"host_programs":["cups"],"sysctl":{"vm.swappiness":10}}' \
    > "$OS_DIR/hosts/core/profile.jsonc"

  # Real pure cores (emit pulls in the real picker_assign_disks + layers).
  source "$BATS_TEST_DIRNAME/../../lib/config/state.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  source "$BATS_TEST_DIRNAME/../../lib/config/menu.sh"

  # Stub only the live-disk enumeration (no lsblk in tests); picker_assign_disks
  # stays real so the assembled config is the genuine artifact.
  live_medium_disks() { :; }
  picker_enum_disks() { printf '%s\n' "/dev/disk/by-id/wwn-0xDEAD"; }
  export -f live_medium_disks picker_enum_disks

  # shellcheck source=../../lib/guided.sh
  source "$BATS_TEST_DIRNAME/../../lib/guided.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

write_answers() {
  local f="$TEST_DIR/answers"
  printf '%s\n' "$@" > "$f"
  printf '%s' "$f"
}

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
  jq -e '.users == ["aquastias"]' "$OS_DIR/hosts/eterniox/profile.jsonc"
  jq -e '.system.hostname == "eterniox"' "$OS_DIR/hosts/eterniox/profile.jsonc"
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
  [ -f "$OS_DIR/hosts/eterniox/profile.jsonc" ]
  jq -e 'has("disk") | not' "$OS_DIR/hosts/eterniox/profile.jsonc"   # device-less
  jq -e '.options.bootloader == "grub"' "$OS_DIR/hosts/eterniox/profile.jsonc"
}

@test "guided_build: a replayed Save refuses an ad-hoc user that already exists" {
  mkdir -p "$OS_DIR/users/carol"
  printf 'KEEP\n' > "$OS_DIR/users/carol/profile.jsonc"
  guided_load_replay "$(write_answers \
    'hostname=eterniox' \
    'new_user_name=carol' 'new_user_password=x' \
    'terminal=save' 'save_name=eterniox')"

  run guided_build
  [ "$status" -ne 0 ]
  [ "$status" -ne 64 ]
  [ "$(cat "$OS_DIR/users/carol/profile.jsonc")" = "KEEP" ]   # untouched
  [ ! -f "$OS_DIR/hosts/eterniox/profile.jsonc" ]             # host not committed
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
  [ -f "$OS_DIR/users/carol/profile.jsonc" ]
  jq -e '.shell == "/bin/zsh" and .sudo == true' \
    "$OS_DIR/users/carol/profile.jsonc"
  # passwords land ONLY in the side manifest — never in the Effective Config
  echo "$effective" | jq -e 'has("root_password") | not'
  echo "$effective" | jq -e '(.. | objects | has("password")) // false | not' \
    2>/dev/null || true
  jq -e '.root_password == "r00t"' "$GUIDED_SECRETS_MANIFEST"
  jq -e '.users.carol.password == "hunter2"' "$GUIDED_SECRETS_MANIFEST"
}

# ── the encryption passphrase round-trips handoff file → manifest (ADR 0054) ──

@test "secrets: an enc passphrase in the handoff file lands in the manifest" {
  _guided_users_reset
  local f="$TEST_DIR/secrets.json"
  printf '%s\n' '{"enc_passphrase":"corrhorse","root_password":"r00t"}' > "$f"
  _guided_load_secrets_file "$f"
  [ "$_GUIDED_ENC_PASSPHRASE" = "corrhorse" ]
  run _guided_secrets_manifest
  echo "$output" | jq -e '.enc_passphrase == "corrhorse"'
  echo "$output" | jq -e '.root_password == "r00t"'
}

@test "secrets: no enc_passphrase key when none was captured" {
  _guided_users_reset
  run _guided_secrets_manifest
  echo "$output" | jq -e 'has("enc_passphrase") | not'
}

# ── Advanced freeform authoring: build an arbitrary skeleton group by group ─

@test "_guided_author_skeleton: replay authors the OS pool + a storage group" {
  guided_load_replay "$(write_answers \
    'adv_os_topology=mirror' 'adv_os_disk_count=2' \
    'adv_storage_count=1' 'adv_storage_0_name=data' \
    'adv_storage_0_topology=raidz1' 'adv_storage_0_disk_count=3' \
    'adv_data_count=0')"
  _GUIDED_STATE="$(cfgstate_new)"

  _guided_author_skeleton
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

@test "_guided_filesystem_options: all four built filesystems are active" {
  run _guided_filesystem_options
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "zfs"
  echo "$output" | grep -qx "btrfs"
  echo "$output" | grep -qx "ext4"
  echo "$output" | grep -qx "xfs"
  # Every adapter is built now, so nothing is flagged reserved.
  ! echo "$output" | grep -q "reserved"
}

@test "_guided_edit_filesystem: picking zfs commits the filesystem" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "zfs"; }
  export -f guided_select

  _guided_edit_filesystem
  [ "$(cfgstate_get "$_GUIDED_STATE" filesystem)" = "zfs" ]
}

@test "_guided_edit_filesystem: a reserved filesystem is refused, no commit" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  # All four adapters ship today, so exercise the reserved seam (kept for a
  # future unbuilt adapter) with an injected reserved filesystem.
  _GUIDED_FS_RESERVED=(reiserfs)
  guided_select() { printf '%s' "reiserfs (reserved)"; }
  export -f guided_select

  run _guided_edit_filesystem
  [ "$status" -ne 0 ]
  [ -z "$(cfgstate_get "$_GUIDED_STATE" filesystem)" ]
}

# ── encryption / impermanence are bool toggles through the seam ─────────────

@test "_guided_edit_encryption: selecting true enables encryption" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_encryption
  echo "$_GUIDED_STATE" | jq -e '.options.encryption == true'
}

@test "_guided_edit_impermanence: selecting true enables impermanence" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_impermanence
  echo "$_GUIDED_STATE" | jq -e '.options.impermanence.enabled == true'
}

# ── persist extensions: free-text directories appended for impermanence ─────

@test "_guided_add_persist: appends a directory to persist.directories" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "/etc/wireguard"; }
  export -f guided_prompt

  _guided_add_persist
  echo "$_GUIDED_STATE" | jq -e '.persist.directories == ["/etc/wireguard"]'
}

@test "_guided_add_persist: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_add_persist
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.persist == null'
}

# ── Host identity edits (issue 01): locale / timezone / keymap over the seeds ─
# The seed is the BASELINE; an edit writes the OVERRIDE map (so the row flips ●)
# and wins effectively over the seed.

@test "_guided_edit_locale: a typed value writes an override over the seed" {
  _GUIDED_REPLAY=0
  _GUIDED_BASELINE="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "de_DE.UTF-8"; }
  export -f guided_prompt

  _guided_edit_locale
  echo "$_GUIDED_STATE" | jq -e '.system.locale == "de_DE.UTF-8"'   # in override
  cfgstate_is_overridden "$_GUIDED_STATE" system.locale             # flips ●
  [ "$(cfgstate_get "$(_guided_effective)" system.locale)" = "de_DE.UTF-8" ]
}

@test "_guided_edit_timezone / _guided_edit_keymap: typed values override the seeds" {
  _GUIDED_REPLAY=0
  _GUIDED_BASELINE="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() {
    case "$1" in
    timezone) printf '%s' "America/New_York" ;;
    keymap)   printf '%s' "de" ;;
    esac
  }
  export -f guided_prompt

  _guided_edit_timezone
  _guided_edit_keymap
  echo "$_GUIDED_STATE" | jq -e '.system.timezone == "America/New_York"'
  echo "$_GUIDED_STATE" | jq -e '.system.keymap == "de"'
}

# ── resetting an overridden identity field falls back to the seed, never empty ─
# The baseline layer is why Reset can't strip the back-end-required identity:
# reset drops the OVERRIDE, and the seeded baseline still supplies the value.

@test "reset of an overridden locale falls back to the seeded baseline" {
  _GUIDED_BASELINE="$(cfgstate_seed_defaults "$(cfgstate_new)")"
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" system.locale '"de_DE.UTF-8"')"
  [ "$(cfgstate_get "$(_guided_effective)" system.locale)" = "de_DE.UTF-8" ]

  _GUIDED_STATE="$(cfgstate_unset "$_GUIDED_STATE" system.locale)"   # reset field
  [ -z "$(cfgstate_get "$_GUIDED_STATE" system.locale)" ]           # override gone
  [ "$(cfgstate_get "$(_guided_effective)" system.locale)" = "en_US.UTF-8" ]
}

# ── Pacman + Advanced edits (issue 06 Pass B): reuse the issue-05 helpers ───

@test "_guided_edit_mirror_countries: multi-select stores the country array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "Japan" "Australia"; }
  export -f guided_multi

  _guided_edit_mirror_countries
  echo "$_GUIDED_STATE" | jq -e '.options.mirror_countries == ["Japan","Australia"]'
}

@test "_guided_edit_optional_repos: a replay set selects the optional repos" {
  _GUIDED_STATE="$(cfgstate_new)"
  guided_load_replay "$(write_answers 'optional_repos=multilib core-testing')"
  _guided_edit_optional_repos
  echo "$_GUIDED_STATE" \
    | jq -e '.options.optional_repos == ["multilib","core-testing"]'
}

@test "_guided_add_custom_repository: a replayed repo appends an object" {
  _GUIDED_STATE="$(cfgstate_new)"
  guided_load_replay "$(write_answers 'custom_repository=cool https://x Never')"
  _guided_add_custom_repository
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].name == "cool"'
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].url == "https://x"'
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].sign_check == "Never"'
  echo "$_GUIDED_STATE" \
    | jq -e '.options.custom_repositories[0].sign_option == "TrustedOnly"'
}

@test "_guided_edit_firewall: picking ufw sets the firewall to ufw" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "ufw"; }
  export -f guided_select

  _guided_edit_firewall
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.firewall == "ufw"'
}

@test "_guided_edit_firewall: picking none disables the firewall" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "none"; }
  export -f guided_select

  _guided_edit_firewall
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.firewall == "none"'
}

@test "_guided_edit_antivirus: selecting false drops clamav from the selection" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_edit_antivirus
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.antivirus == false'
}

@test "_guided_edit_borg: selecting false drops borg from the selection" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_edit_borg
  echo "$_GUIDED_STATE" | jq -e '.post_install.backup.borg == false'
}

# ── no-user guard (M5): the terminal actions need a Primary User when extras
# are selected (the tools install via that user's paru pass) ────────────────

@test "_guided_guard_post_install: passes with selections and a seeded user" {
  _GUIDED_BASELINE="$(jq -nc --argjson pi "$(post_install_default)" \
    '{users:["aquastias"], post_install:$pi}')"
  _GUIDED_STATE="$(cfgstate_new)"
  run _guided_guard_post_install
  [ "$status" -eq 0 ]
}

@test "_guided_guard_post_install: aborts with selections but zero users" {
  _GUIDED_BASELINE="$(jq -nc --argjson pi "$(post_install_default)" \
    '{post_install:$pi}')"
  _GUIDED_STATE="$(cfgstate_new)"
  run _guided_guard_post_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"user"* ]]
}

@test "_guided_guard_post_install: passes userless when nothing is selected" {
  _GUIDED_BASELINE="$(cfgstate_new)"
  _GUIDED_STATE="$(cfgstate_new)"
  run _guided_guard_post_install
  [ "$status" -eq 0 ]
}

# ── Users (issue 07): committed multi-select + ad-hoc create ────────────────

@test "_guided_pick_users: committed multi-select sets users[], primary first" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/bob" "$OS_DIR/users/core"
  : > "$OS_DIR/users/alice/profile.jsonc"
  : > "$OS_DIR/users/bob/profile.jsonc"
  : > "$OS_DIR/users/core/profile.jsonc"
  guided_multi() { printf '%s\n' "alice" "bob"; }   # core never offered
  export -f guided_multi

  _guided_pick_users
  echo "$_GUIDED_STATE" | jq -e '.users == ["alice","bob"]'
}

@test "_guided_create_user: ad-hoc form authors a User Profile + adds the user" {
  guided_load_replay "$(write_answers \
    'new_user_name=carol' \
    'new_user_shell=/bin/zsh' \
    'new_user_sudo=true' \
    'new_user_groups=docker libvirt' \
    'new_user_programs=' \
    'new_user_git_name=Carol' \
    'new_user_git_email=c@x.io' \
    'new_user_ssh_keys=' \
    'new_user_password=hunter2')"
  _GUIDED_STATE="$(cfgstate_new)"
  _guided_users_reset

  _guided_create_user
  echo "$_GUIDED_STATE" | jq -e '.users == ["carol"]'                 # in the list
  echo "${_GUIDED_ADHOC_FORM[carol]}" \
    | jq -e '.shell == "/bin/zsh" and .sudo == true'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e '.groups == ["docker","libvirt"]'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e '.git.name == "Carol"'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e 'has("name") | not'    # username = dir
  [ "${_GUIDED_USER_PW[carol]}" = "hunter2" ]
}

@test "_guided_create_user: an empty password defaults to 12345" {
  guided_load_replay "$(write_answers \
    'new_user_name=dave' 'new_user_password=')"
  _GUIDED_STATE="$(cfgstate_new)"
  _guided_users_reset

  _guided_create_user
  [ "${_GUIDED_USER_PW[dave]}" = "12345" ]
}

# ── passwords: root + the no-SOPS secrets manifest ──────────────────────────

@test "_guided_set_root_password: a typed password is held aside" {
  _GUIDED_REPLAY=0
  _guided_users_reset
  guided_prompt() { printf '%s' "r00t"; }
  export -f guided_prompt

  _guided_set_root_password
  [ "$_GUIDED_ROOT_PW" = "r00t" ]
}

@test "_guided_secrets_manifest: builds the root + per-user password shape" {
  _guided_users_reset
  _GUIDED_ROOT_PW="r00t"
  _GUIDED_USER_PW[carol]="hunter2"

  run _guided_secrets_manifest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.root_password == "r00t"'
  echo "$output" | jq -e '.users.carol.password == "hunter2"'
}

@test "_guided_secrets_manifest: an unset root password defaults to 12345 (ADR 0055)" {
  _guided_users_reset

  run _guided_secrets_manifest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.root_password == "12345"'
}

@test "_guided_user_names: lists committed users, excludes core + vm-* fixtures" {
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core" \
    "$OS_DIR/users/vm-test" "$OS_DIR/users/vm-data"
  : > "$OS_DIR/users/alice/profile.jsonc"
  : > "$OS_DIR/users/core/profile.jsonc"
  : > "$OS_DIR/users/vm-test/profile.jsonc"
  : > "$OS_DIR/users/vm-data/profile.jsonc"

  run _guided_user_names
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "alice"
  ! echo "$output" | grep -qx "core"
  ! echo "$output" | grep -qx "vm-test"
  ! echo "$output" | grep -qx "vm-data"
}

# ── list builders: packages.repo.extra / host_programs / sysctl ───────────

@test "_guided_add_package: typed names (whitespace-split) append to extra" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "htop tmux"; }
  export -f guided_prompt

  _guided_add_package
  echo "$_GUIDED_STATE" | jq -e '.packages.repo.extra == ["htop","tmux"]'
}

@test "_guided_add_package: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_add_package
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.packages == null'
}

@test "_guided_add_host_program: picked names append, deduped" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_set "$(cfgstate_new)" host_programs '["cups"]')"
  guided_multi() { printf '%s\n' "docker" "cups"; }   # cups already present
  export -f guided_multi

  _guided_add_host_program
  echo "$_GUIDED_STATE" | jq -e '.host_programs | index("docker")'
  echo "$_GUIDED_STATE" \
    | jq -e '([.host_programs[] | select(. == "cups")] | length) == 1'
}

@test "_guided_add_sysctl: a key=value sets a literal (dotted) sysctl key" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "vm.swappiness=10"; }
  export -f guided_prompt

  _guided_add_sysctl
  # the dotted key is a literal object key, value stored as a number
  echo "$_GUIDED_STATE" | jq -e '.sysctl["vm.swappiness"] == 10'
}

@test "_guided_add_sysctl: a malformed entry (no =) commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "not-a-pair"; }
  export -f guided_prompt

  run _guided_add_sysctl
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.sysctl == null'
}

# ── the multi-select seam: a replayed answer is the whitespace-separated list

@test "guided_multi: a replayed answer yields one option per line, in order" {
  guided_load_replay "$(write_answers 'kernel=zen lts')"
  run guided_multi kernel "Kernels" lts default hardened zen
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | sed -n 1p)" = "zen" ]
  [ "$(echo "$output" | sed -n 2p)" = "lts" ]
}

# ── Options edits: kernel is a token list, primary (first picked) first ─────

@test "_guided_edit_kernel: multi-select stores the token array, primary first" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "zen" "lts"; }
  export -f guided_multi

  _guided_edit_kernel
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == ["zen","lts"]'
}

@test "_guided_edit_kernel: no pick leaves the kernel untouched" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { :; }
  export -f guided_multi

  run _guided_edit_kernel
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == null'
}

# ── bootloader / swap-size / ssh: simple scalar + bool edits ───────────────

@test "_guided_edit_bootloader: picking grub commits the bootloader" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "grub"; }
  export -f guided_select

  _guided_edit_bootloader
  echo "$_GUIDED_STATE" | jq -e '.options.bootloader == "grub"'
}

@test "_guided_edit_swap_size: a typed size commits options.swap_size" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' "8G"; }
  export -f guided_prompt

  _guided_edit_swap_size
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == "8G"'
}

@test "_guided_edit_swap_size: empty input commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_edit_swap_size
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == null'
}

@test "_guided_edit_ssh: selecting true enables ssh" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_edit_ssh
  echo "$_GUIDED_STATE" | jq -e '.options.ssh.enabled == true'
}

# ── Environment: desktop is a multi, gpu auto clears vendors ────────────────

@test "_guided_edit_desktop: multi-select stores the desktop array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "kde"; }
  export -f guided_multi

  _guided_edit_desktop
  echo "$_GUIDED_STATE" | jq -e '.environment.desktop == ["kde"]'
}

@test "_guided_edit_gpu: vendors store an array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "amd" "nvidia"; }
  export -f guided_multi

  _guided_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == ["amd","nvidia"]'
}

@test "_guided_edit_gpu: auto stores the scalar and clears any vendors" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(cfgstate_new)"
  guided_multi() { printf '%s\n' "auto" "amd"; }   # auto wins, vendors dropped
  export -f guided_multi

  _guided_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == "auto"'
}

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

@test "_guided_load_secrets_file: populates root + user passwords from the file" {
  _GUIDED_ROOT_PW=""
  _GUIDED_USER_PW=()
  local f; f="$(mktemp)"
  printf '%s\n' \
    '{"root_password":"r00t","users":{"aquastias":{"password":"aq"}}}' > "$f"
  _guided_load_secrets_file "$f"
  rm -f "$f"
  [ "$_GUIDED_ROOT_PW" = "r00t" ]
  [ "${_GUIDED_USER_PW[aquastias]}" = "aq" ]
}

@test "_guided_load_secrets_file: an empty/missing file is a no-op" {
  _GUIDED_ROOT_PW="kept"
  _GUIDED_USER_PW=()
  _guided_load_secrets_file "/nonexistent/secrets.json"
  [ "$_GUIDED_ROOT_PW" = "kept" ]
}

@test "in-menu secrets feed the no-SOPS manifest (never the Config State)" {
  _GUIDED_ROOT_PW=""
  _GUIDED_USER_PW=()
  local f; f="$(mktemp)"
  printf '%s\n' '{"root_password":"r","users":{"alex":{"password":"a"}}}' > "$f"
  _guided_load_secrets_file "$f"; rm -f "$f"
  run _guided_secrets_manifest
  [ "$(jq -r '.root_password' <<<"$output")" = "r" ]
  [ "$(jq -r '.users.alex.password' <<<"$output")" = "a" ]
}

# ── a persistent-path created user (name only) gets a default profile ─────────

@test "_guided_materialize_users: a created user without a profile gets a default" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"users":["newbie"]}'
  _GUIDED_ADHOC_ORDER=()
  _guided_materialize_users
  [ -f "$OS_DIR/users/newbie/profile.jsonc" ]
  jq -e '.sudo == true and (.groups | index("wheel"))
    and (.programs | index("searxng"))' \
    "$OS_DIR/users/newbie/profile.jsonc"
}

# ── issue 04: In-Menu Disk Binding resolves without a post-menu pick ──────────

@test "_guided_resolve_assignment: a fully-bound layout picks no disks" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"mode":"multi","os_pool":{"topology":"mirror",
    "devices":["/dev/disk/by-id/a","/dev/disk/by-id/b"]}}'
  # would fail loudly if the bound path ever reached the flat picker
  guided_pick_disks() { echo CALLED; return 1; }
  run _guided_resolve_assignment
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q CALLED
  echo "$output" | jq -e '.os_pool == ["/dev/disk/by-id/a","/dev/disk/by-id/b"]'
}

@test "_guided_resolve_assignment: single mode uses the in-menu root disk" {
  _GUIDED_BASELINE='{}'
  _GUIDED_STATE='{"mode":"single","root_disk":"/dev/disk/by-id/root"}'
  _GUIDED_DISK=""
  run _guided_resolve_assignment
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.mode == "single" and .disk == "/dev/disk/by-id/root"'
}

# ── slice 02: install-scoped User Editor deltas merged onto the clone ─────────

@test "_guided_apply_userforms: merges a shell delta, keeps the committed delta" {
  mkdir -p "$OS_DIR/users/alice" "$OS_DIR/users/core"
  printf '{}' > "$OS_DIR/users/core/profile.jsonc"
  # committed delta carries groups; the edit only changes shell
  printf '{"groups":["docker"],"shell":"/bin/bash"}' \
    > "$OS_DIR/users/alice/profile.jsonc"
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_apply_userforms
  jq -e '.shell == "/bin/zsh"' "$OS_DIR/users/alice/profile.jsonc"
  jq -e '.groups == ["docker"]' "$OS_DIR/users/alice/profile.jsonc"  # delta kept
}

@test "_guided_apply_userforms: no-op when no deltas were held aside" {
  mkdir -p "$OS_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  _GUIDED_USERFORMS_JSON=''
  _guided_apply_userforms
  jq -e '.shell == "/bin/bash"' "$OS_DIR/users/alice/profile.jsonc"   # untouched
}

# ── slice 04: Save-warn — committed profiles never rewritten ─────────────────

@test "_guided_committed_userform_edits: reports committed users, not ad-hoc" {
  mkdir -p "$OS_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  # dave has NO committed profile → session-created, must not be reported
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"},"dave":{"shell":"/bin/fish"}}'
  run _guided_committed_userform_edits
  echo "$output" | grep -qx alice
  ! echo "$output" | grep -qx dave
}

@test "_guided_apply_userforms save: does NOT rewrite a committed profile" {
  mkdir -p "$OS_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" alice "
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_apply_userforms save
  jq -e '.shell == "/bin/bash"' "$OS_DIR/users/alice/profile.jsonc"   # untouched
}

@test "_guided_apply_userforms save: still applies to a session-created user" {
  mkdir -p "$OS_DIR/users/dave"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/dave/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" "     # dave was not committed at start
  _GUIDED_USERFORMS_JSON='{"dave":{"shell":"/bin/zsh"}}'
  _guided_apply_userforms save
  jq -e '.shell == "/bin/zsh"' "$OS_DIR/users/dave/profile.jsonc"
}

@test "_guided_apply_userforms proceed: DOES apply to a committed profile" {
  mkdir -p "$OS_DIR/users/alice"
  printf '{"shell":"/bin/bash"}' > "$OS_DIR/users/alice/profile.jsonc"
  _GUIDED_COMMITTED_AT_START=" alice "
  _GUIDED_USERFORMS_JSON='{"alice":{"shell":"/bin/zsh"}}'
  _guided_apply_userforms proceed
  jq -e '.shell == "/bin/zsh"' "$OS_DIR/users/alice/profile.jsonc"
}

# ── headless replay: `profile=<name>` seeds the state (ADR 0055) ─────────────

@test "_guided_seed_from_profile: replay 'profile=' seeds the state" {
  mkdir -p "$OS_DIR/hosts/desktop"
  cat > "$OS_DIR/hosts/desktop/profile.jsonc" <<'JSONC'
{ "system": { "hostname": "eterniox" },
  "options": { "encryption": true }, "filesystem": "zfs" }
JSONC
  guided_load_replay "$(write_answers 'profile=desktop')"
  _GUIDED_STATE="$(cfgstate_new)"
  _guided_seed_from_profile
  jq -e '.options.encryption == true' <<<"$_GUIDED_STATE"
  jq -e '.filesystem == "zfs"' <<<"$_GUIDED_STATE"
  jq -e '.system.hostname == "eterniox"' <<<"$_GUIDED_STATE"
}

@test "_guided_seed_from_profile: no 'profile=' key leaves the state untouched" {
  guided_load_replay "$(write_answers 'hostname=x')"
  _GUIDED_STATE='{"marker":1}'
  _guided_seed_from_profile
  jq -e '.marker == 1' <<<"$_GUIDED_STATE"
}

@test "_guided_seed_from_profile: an unknown profile is a no-op" {
  guided_load_replay "$(write_answers 'profile=ghost')"
  _GUIDED_STATE='{"marker":1}'
  _guided_seed_from_profile
  jq -e '.marker == 1' <<<"$_GUIDED_STATE"
}

# ── one-select install (ADR 0055): replay `profile=` assembles the machine ───
# The same assembly path the VM drives via install.sh --guided. Proves a seeded
# profile flows all the way to the Effective Config with no field answers and no
# password answers (secrets default to 12345 via the manifest, tested separately).

@test "guided_build: replay 'profile=' assembles the seeded machine end-to-end" {
  mkdir -p "$OS_DIR/hosts/laptop"
  cat > "$OS_DIR/hosts/laptop/profile.jsonc" <<'JSONC'
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
  mkdir -p "$OS_DIR/hosts/laptop"
  printf '%s\n' '{"system":{"hostname":"chronos"},"mode":"single","ashift":12}' \
    > "$OS_DIR/hosts/laptop/profile.jsonc"
  guided_load_replay "$(write_answers \
    'profile=laptop' \
    'hostname=override' \
    'disk=/dev/disk/by-id/wwn-0xDEAD' \
    'confirm=INSTALL')"

  effective="$(guided_build 2>/dev/null)"
  echo "$effective" | jq -e '.system.hostname == "override"'   # answer wins
}
