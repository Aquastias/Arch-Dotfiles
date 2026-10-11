#!/usr/bin/env bats
# Tests: edits (split from shell.bats;
# shared setup in shell-helpers.bash)

load shell-helpers


# ── persist extensions: free-text directories appended for impermanence ─────

@test "_guided_shell_add_persist: appends a directory to persist.directories" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "/etc/wireguard"; }
  export -f guided_prompt

  _guided_shell_add_persist
  echo "$_GUIDED_STATE" | jq -e '.persist.directories == ["/etc/wireguard"]'
}

@test "_guided_shell_add_persist: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_shell_add_persist
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.persist == null'
}


# ── Host identity edits (issue 01): locale / timezone / keymap over the seeds ─
# The seed is the BASELINE; an edit writes the OVERRIDE map (so the row flips ●)
# and wins effectively over the seed.

@test "_guided_shell_edit_locale: a typed value writes an override over the seed" {
  _GUIDED_REPLAY=0
  _GUIDED_BASELINE="$(config_state_seed_defaults "$(config_state_new)")"
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "de_DE.UTF-8"; }
  export -f guided_prompt

  _guided_shell_edit_locale
  echo "$_GUIDED_STATE" | jq -e '.system.locale == "de_DE.UTF-8"'   # in override
  config_state_is_overridden "$_GUIDED_STATE" system.locale             # flips ●
  [ "$(config_state_get "$(_guided_shell_effective)" system.locale)" = "de_DE.UTF-8" ]
}

@test "_guided_shell_edit_timezone / _guided_shell_edit_keymap: typed values override the seeds" {
  _GUIDED_REPLAY=0
  _GUIDED_BASELINE="$(config_state_seed_defaults "$(config_state_new)")"
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() {
    case "$1" in
    timezone) printf '%s' "America/New_York" ;;
    keymap)   printf '%s' "de" ;;
    esac
  }
  export -f guided_prompt

  _guided_shell_edit_timezone
  _guided_shell_edit_keymap
  echo "$_GUIDED_STATE" | jq -e '.system.timezone == "America/New_York"'
  echo "$_GUIDED_STATE" | jq -e '.system.keymap == "de"'
}


# ── resetting an overridden identity field falls back to the seed, never empty ─
# The baseline layer is why Reset can't strip the back-end-required identity:
# reset drops the OVERRIDE, and the seeded baseline still supplies the value.

@test "reset of an overridden locale falls back to the seeded baseline" {
  _GUIDED_BASELINE="$(config_state_seed_defaults "$(config_state_new)")"
  _GUIDED_STATE="$(config_state_set "$(config_state_new)" system.locale '"de_DE.UTF-8"')"
  [ "$(config_state_get "$(_guided_shell_effective)" system.locale)" = "de_DE.UTF-8" ]

  _GUIDED_STATE="$(config_state_unset "$_GUIDED_STATE" system.locale)"   # reset field
  [ -z "$(config_state_get "$_GUIDED_STATE" system.locale)" ]           # override gone
  [ "$(config_state_get "$(_guided_shell_effective)" system.locale)" = "en_US.UTF-8" ]
}


# ── Pacman + Advanced edits (issue 06 Pass B): reuse the issue-05 helpers ───

@test "_guided_shell_edit_mirror_countries: multi-select stores the country array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { printf '%s\n' "Japan" "Australia"; }
  export -f guided_multi

  _guided_shell_edit_mirror_countries
  echo "$_GUIDED_STATE" | jq -e '.options.mirror_countries == ["Japan","Australia"]'
}

@test "_guided_shell_edit_optional_repos: a replay set selects the optional repos" {
  _GUIDED_STATE="$(config_state_new)"
  guided_load_replay "$(write_answers 'optional_repos=multilib core-testing')"
  _guided_shell_edit_optional_repos
  echo "$_GUIDED_STATE" \
    | jq -e '.options.optional_repos == ["multilib","core-testing"]'
}

@test "_guided_shell_add_custom_repository: a replayed repo appends an object" {
  _GUIDED_STATE="$(config_state_new)"
  guided_load_replay "$(write_answers 'custom_repository=cool https://x Never')"
  _guided_shell_add_custom_repository
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].name == "cool"'
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].url == "https://x"'
  echo "$_GUIDED_STATE" | jq -e '.options.custom_repositories[0].sign_check == "Never"'
  echo "$_GUIDED_STATE" \
    | jq -e '.options.custom_repositories[0].sign_option == "TrustedOnly"'
}

@test "_guided_shell_edit_firewall: picking ufw sets the firewall to ufw" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "ufw"; }
  export -f guided_select

  _guided_shell_edit_firewall
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.firewall == "ufw"'
}

@test "_guided_shell_edit_firewall: picking none disables the firewall" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "none"; }
  export -f guided_select

  _guided_shell_edit_firewall
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.firewall == "none"'
}

@test "_guided_shell_edit_antivirus: selecting false drops clamav from the selection" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_shell_edit_antivirus
  echo "$_GUIDED_STATE" | jq -e '.post_install.security.antivirus == false'
}

@test "_guided_shell_edit_borg: selecting false drops borg from the selection" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "false"; }
  export -f guided_select

  _guided_shell_edit_borg
  echo "$_GUIDED_STATE" | jq -e '.post_install.backup.borg == false'
}


# ── no-user guard (M5): the terminal actions need a Primary User when extras
# are selected (the tools install via that user's paru pass) ────────────────

@test "_guided_shell_guard_post_install: passes with selections and a seeded user" {
  _GUIDED_BASELINE="$(jq -nc --argjson pi "$(post_install_default)" \
    '{users:["aquastias"], post_install:$pi}')"
  _GUIDED_STATE="$(config_state_new)"
  run _guided_shell_guard_post_install
  [ "$status" -eq 0 ]
}

@test "_guided_shell_guard_post_install: aborts with selections but zero users" {
  _GUIDED_BASELINE="$(jq -nc --argjson pi "$(post_install_default)" \
    '{post_install:$pi}')"
  _GUIDED_STATE="$(config_state_new)"
  run _guided_shell_guard_post_install
  [ "$status" -ne 0 ]
  [[ "$output" == *"user"* ]]
}

@test "_guided_shell_guard_post_install: passes userless when nothing is selected" {
  _GUIDED_BASELINE="$(config_state_new)"
  _GUIDED_STATE="$(config_state_new)"
  run _guided_shell_guard_post_install
  [ "$status" -eq 0 ]
}


# ── Users (issue 07): committed multi-select + ad-hoc create ────────────────

@test "_guided_shell_pick_users: committed multi-select sets users[], primary first" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/bob" "$INSTALLER_DIR/users/core"
  : > "$INSTALLER_DIR/users/alice/profile.jsonc"
  : > "$INSTALLER_DIR/users/bob/profile.jsonc"
  : > "$INSTALLER_DIR/users/core/profile.jsonc"
  guided_multi() { printf '%s\n' "alice" "bob"; }   # core never offered
  export -f guided_multi

  _guided_shell_pick_users
  echo "$_GUIDED_STATE" | jq -e '.users == ["alice","bob"]'
}

@test "_guided_shell_create_user: ad-hoc form authors a User Profile + adds the user" {
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
  _GUIDED_STATE="$(config_state_new)"
  _guided_shell_users_reset

  _guided_shell_create_user
  echo "$_GUIDED_STATE" | jq -e '.users == ["carol"]'                 # in the list
  echo "${_GUIDED_ADHOC_FORM[carol]}" \
    | jq -e '.shell == "/bin/zsh" and .sudo == true'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e '.groups == ["docker","libvirt"]'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e '.git.name == "Carol"'
  echo "${_GUIDED_ADHOC_FORM[carol]}" | jq -e 'has("name") | not'    # username = dir
  [ "${_GUIDED_USER_PASSWORDS[carol]}" = "hunter2" ]
}

@test "_guided_shell_create_user: an empty password defaults to 12345" {
  guided_load_replay "$(write_answers \
    'new_user_name=dave' 'new_user_password=')"
  _GUIDED_STATE="$(config_state_new)"
  _guided_shell_users_reset

  _guided_shell_create_user
  [ "${_GUIDED_USER_PASSWORDS[dave]}" = "12345" ]
}


# ── passwords: root + the no-SOPS secrets manifest ──────────────────────────

@test "_guided_shell_set_root_password: a typed password is held aside" {
  _GUIDED_REPLAY=0
  _guided_shell_users_reset
  guided_prompt() { printf '%s' "r00t"; }
  export -f guided_prompt

  _guided_shell_set_root_password
  [ "$_GUIDED_ROOT_PASSWORD" = "r00t" ]
}

@test "_guided_shell_secrets_manifest: builds the root + per-user password shape" {
  _guided_shell_users_reset
  _GUIDED_ROOT_PASSWORD="r00t"
  _GUIDED_USER_PASSWORDS[carol]="hunter2"

  run _guided_shell_secrets_manifest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.root_password == "r00t"'
  echo "$output" | jq -e '.users.carol.password == "hunter2"'
}

@test "_guided_shell_secrets_manifest: an unset root password defaults to 12345 (ADR 0055)" {
  _guided_shell_users_reset

  run _guided_shell_secrets_manifest
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.root_password == "12345"'
}

@test "_guided_shell_user_names: lists committed users, excludes core + users/vm fixtures" {
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core" \
    "$INSTALLER_DIR/users/vm/test" "$INSTALLER_DIR/users/vm/data"
  : > "$INSTALLER_DIR/users/alice/profile.jsonc"
  : > "$INSTALLER_DIR/users/core/profile.jsonc"
  : > "$INSTALLER_DIR/users/vm/test/profile.jsonc"
  : > "$INSTALLER_DIR/users/vm/data/profile.jsonc"

  run _guided_shell_user_names
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "alice"
  ! echo "$output" | grep -qx "core"
  ! echo "$output" | grep -qx "vm"
  ! echo "$output" | grep -qx "test"
  ! echo "$output" | grep -qx "data"
}


# ── list builders: packages.repo.extra / host_programs / sysctl ───────────

@test "_guided_shell_add_package: typed names (whitespace-split) append to extra" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "htop tmux"; }
  export -f guided_prompt

  _guided_shell_add_package
  echo "$_GUIDED_STATE" | jq -e '.packages.repo.extra == ["htop","tmux"]'
}

@test "_guided_shell_add_package: empty input adds nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_shell_add_package
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.packages == null'
}

@test "_guided_shell_add_host_program: picked names append, deduped" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_set "$(config_state_new)" host_programs '["cups"]')"
  guided_multi() { printf '%s\n' "docker" "cups"; }   # cups already present
  export -f guided_multi

  _guided_shell_add_host_program
  echo "$_GUIDED_STATE" | jq -e '.host_programs | index("docker")'
  echo "$_GUIDED_STATE" \
    | jq -e '([.host_programs[] | select(. == "cups")] | length) == 1'
}

@test "_guided_shell_add_sysctl: a key=value sets a literal (dotted) sysctl key" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "vm.swappiness=10"; }
  export -f guided_prompt

  _guided_shell_add_sysctl
  # the dotted key is a literal object key, value stored as a number
  echo "$_GUIDED_STATE" | jq -e '.sysctl["vm.swappiness"] == 10'
}

@test "_guided_shell_add_sysctl: a malformed entry (no =) commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "not-a-pair"; }
  export -f guided_prompt

  run _guided_shell_add_sysctl
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.sysctl == null'
}


# ── the multi-select seam: a replayed answer is the whitespace-separated list

@test "guided_multi: a replayed answer yields one option per line, in order" {
  guided_load_replay "$(write_answers 'kernel=zen lts')"
  run guided_multi kernel "Kernels" lts default hardened zen
  [ "$status" -eq 0 ]
  [ "$(awk 'NR == 1' <<<"$output")" = "zen" ]
  [ "$(awk 'NR == 2' <<<"$output")" = "lts" ]
}


# ── Options edits: kernel is a token list, primary (first picked) first ─────

@test "_guided_shell_edit_kernel: multi-select stores the token array, primary first" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { printf '%s\n' "zen" "lts"; }
  export -f guided_multi

  _guided_shell_edit_kernel
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == ["zen","lts"]'
}

@test "_guided_shell_edit_kernel: no pick leaves the kernel untouched" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { :; }
  export -f guided_multi

  run _guided_shell_edit_kernel
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.kernel == null'
}


# ── bootloader / swap-size / ssh: simple scalar + bool edits ───────────────

@test "_guided_shell_edit_bootloader: picking grub commits the bootloader" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "grub"; }
  export -f guided_select

  _guided_shell_edit_bootloader
  echo "$_GUIDED_STATE" | jq -e '.options.bootloader == "grub"'
}

@test "_guided_shell_edit_swap_size: a typed size commits options.swap_size" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' "8G"; }
  export -f guided_prompt

  _guided_shell_edit_swap_size
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == "8G"'
}

@test "_guided_shell_edit_swap_size: empty input commits nothing" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_prompt() { printf '%s' ""; }
  export -f guided_prompt

  run _guided_shell_edit_swap_size
  [ "$status" -ne 0 ]
  echo "$_GUIDED_STATE" | jq -e '.options.swap_size == null'
}

@test "_guided_shell_edit_ssh: selecting true enables ssh" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_select() { printf '%s' "true"; }
  export -f guided_select

  _guided_shell_edit_ssh
  echo "$_GUIDED_STATE" | jq -e '.options.ssh.enabled == true'
}


# ── Environment: desktop is a multi, gpu auto clears vendors ────────────────

@test "_guided_shell_edit_desktop: multi-select stores the desktop array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { printf '%s\n' "kde"; }
  export -f guided_multi

  _guided_shell_edit_desktop
  echo "$_GUIDED_STATE" | jq -e '.environment.desktop == ["kde"]'
}

@test "_guided_shell_edit_gpu: vendors store an array" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { printf '%s\n' "amd" "nvidia"; }
  export -f guided_multi

  _guided_shell_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == ["amd","nvidia"]'
}

@test "_guided_shell_edit_gpu: auto stores the scalar and clears any vendors" {
  _GUIDED_REPLAY=0
  _GUIDED_STATE="$(config_state_new)"
  guided_multi() { printf '%s\n' "auto" "amd"; }   # auto wins, vendors dropped
  export -f guided_multi

  _guided_shell_edit_gpu
  echo "$_GUIDED_STATE" | jq -e '.environment.gpu == "auto"'
}
