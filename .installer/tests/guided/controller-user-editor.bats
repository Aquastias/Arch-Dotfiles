#!/usr/bin/env bats
# Tests: User Editor (split from controller.bats;
# shared setup in controller-helpers.bash)

load controller-helpers


# ── slice 02: the per-user User Editor ───────────────────────────────────────

@test "back(useredit): returns to the flattened Users list" {
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_back
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "list(useredit committed): enabled + shell (from profile) + Back" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{"shell":"/bin/zsh"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_list
  echo "$output" | grep -q "enabled: on"
  echo "$output" | grep -q "shell: zsh"
  echo "$output" | grep -q "← Back"
  ! echo "$output" | grep -q "remove user"     # committed → no remove
}

@test "list(useredit ad-hoc): remove + shell, no enabled row" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users dave)"
  run guided_controller_list
  ! echo "$output" | grep -q "enabled:"        # ad-hoc → no enabled
  echo "$output" | grep -q "shell: zsh"        # User Core default
  echo "$output" | grep -q "✗ remove user"
}

@test "enter(useredit): enabled toggles the user out of the install" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_enter "enabled: on   (Enter toggles)"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '[]' ]
}

@test "enter(useredit): shell cycles into an install-scoped override" {
  export INSTALLER_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_enter "shell: bash   (Enter cycles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.alice.shell' "$GUIDED_USERFORMS_FILE")" = "/bin/zsh" ]
  run guided_controller_list
  echo "$output" | grep -q "shell: zsh"        # display reflects the override
}

@test "enter(useredit): cycling back to the committed shell drops the override" {
  export INSTALLER_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"alice":{"shell":"/bin/fish"}}\n' > "$GUIDED_USERFORMS_FILE"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{"shell":"/bin/bash"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_enter "shell: fish   (Enter cycles)"   # fish → wrap bash = committed
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]     # strict delta: override gone
}

@test "enter(useredit): remove drops an ad-hoc user + returns to the list" {
  export INSTALLER_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"dave":{"shell":"/bin/zsh"}}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users dave)"
  run guided_controller_enter "✗ remove user"
  [ "$output" = "render" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '[]' ]
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]     # its form cleared too
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}

@test "directive→action: secret rows execute the masked capture verb" {
  local action; action="$(_controller_directive_to_action secret-root /e)"
  [[ "$action" == *"secret root"* ]]
  action="$(_controller_directive_to_action "secret-user alex" /e)"
  [[ "$action" == *"secret user alex"* ]]
}

@test "directive→action: a notice warns in the header without accepting" {
  local action; action="$(_controller_directive_to_action "notice ⚠ set it" /e)"
  [[ "$action" == *"change-header("* ]]
  [[ "$action" == *"bell"* ]]
  [[ "$action" != *accept* ]]
}

@test "enter(text __newuser__): a typed name is added + drops into the editor" {
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_text Users __newuser__ "new user")"
  run guided_controller_enter "+ Create user (name)" "carol"
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice","carol"]' ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "carol" ]
  # seeded with the create defaults: User Core shell / sudo on / wheel
  [ "$(jq -c '.carol' "$GUIDED_USERFORMS_FILE")" \
    = '{"shell":"/bin/zsh","sudo":true,"groups":["wheel"]}' ]
}

@test "enter(text __newuser__): a duplicate name is refused with a notice" {
  export INSTALLER_DIR="$TEST_DIR"; mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_text Users __newuser__ "new user")"
  run guided_controller_enter "+ Create user (name)" "alice"
  [[ "$output" == notice* ]]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice"]' ]   # unchanged
}


# ── clone user (ADR 0064) ────────────────────────────────────────────────────

@test "list(useredit): offers the clone row for both committed + ad-hoc users" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{"shell":"/bin/zsh"}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice","dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"           # committed
  run guided_controller_list
  echo "$output" | grep -q "⧉ Clone this user"
  set_navigation "$(navigation_to_user_edit Users dave)"            # ad-hoc
  run guided_controller_list
  echo "$output" | grep -q "⧉ Clone this user"
}

@test "enter(useredit): clone drops to a name screen carrying the source" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_edit Users alice)"
  run guided_controller_enter "⧉ Clone this user"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "__cloneuser__" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "alice" ]
}

@test "enter(text __cloneuser__): copies shape not identity into a clone" {
  export INSTALLER_DIR="$TEST_DIR"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; uf="$GUIDED_USERFORMS_FILE"
  printf '{}\n' > "$uf"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '%s' '{"shell":"/bin/fish","sudo":true,
    "groups":["wheel","docker"],"programs":["git"],
    "git":{"name":"Alice"},"ssh_authorized_keys":["ssh-ed25519 AAAA"]}' \
    > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_clone Users alice)"
  run guided_controller_enter "clone" "bob"
  [ "$output" = "render" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice","bob"]' ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "bob" ]
  # account-shape copied from the source's effective view
  [ "$(jq -r '.bob.shell' "$uf")" = "/bin/fish" ]
  [ "$(jq -c '.bob.sudo' "$uf")" = "true" ]
  [ "$(jq -c '.bob.groups' "$uf")" = '["wheel","docker"]' ]
  [ "$(jq -c '.bob.programs' "$uf")" = '["git"]' ]
  # identity fields are NOT carried across
  [ "$(jq -r '.bob.git // "none"' "$uf")" = "none" ]
  [ "$(jq -r '.bob.ssh_authorized_keys // "none"' "$uf")" = "none" ]
}

@test "enter(text __cloneuser__): a duplicate name is refused with a notice" {
  export INSTALLER_DIR="$TEST_DIR"; mkdir -p "$INSTALLER_DIR/users/alice"
  printf '{}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_clone Users alice)"
  run guided_controller_enter "clone" "alice"
  [[ "$output" == notice* ]]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice"]' ]   # unchanged
}

@test "enter(text __cloneuser__): a blank name backs out to the Users list" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_clone Users alice)"
  run guided_controller_enter "clone" ""
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(jq -c '.users' "$GUIDED_STATE_FILE")" = '["alice"]' ]   # unchanged
}


# ── back / abort ─────────────────────────────────────────────────────────────

@test "back: at the top screen, aborts the whole menu" {
  run guided_controller_back
  [ "$output" = "abort" ]
}

@test "back: from a category, returns to the top screen" {
  set_navigation "$(navigation_to_category Kernels)"
  run guided_controller_back
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}


# ── directive → fzf action translation (pure) ────────────────────────────────

@test "directive→action: render re-lists in place via reload" {
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
}

@test "directive→action: render also re-headers + re-prompts the screen" {
  set_navigation "$(navigation_to_category Disks)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
  echo "$output" | grep -q "change-header(Enter edit"
  echo "$output" | grep -q "change-prompt(Disks> )"
}

@test "directive→action: render clears the stale filter query first" {
  run _controller_directive_to_action render /x/entry.sh
  # clear-query must precede reload so a leftover filter can't hide the screen
  [[ "$output" == clear-query+reload* ]]
}

@test "directive→action: abort and noop map to fzf primitives" {
  [ "$(_controller_directive_to_action abort /x/entry.sh)" = "abort" ]
  [ "$(_controller_directive_to_action noop /x/entry.sh)" = "ignore" ]
}

@test "directive→action: terminal writes the verb to the result file + accepts" {
  export GUIDED_RESULT_FILE="$TEST_DIR/result"
  run _controller_directive_to_action "terminal proceed" /x/entry.sh
  echo "$output" | grep -q "proceed"
  echo "$output" | grep -q "$TEST_DIR/result"
  echo "$output" | grep -q "+accept"
}


# ── latency fast-path (ticket 04): reload(cat FILE) instead of a second fork ──

@test "fast-path: render reloads via cat of the precomputed list file" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_navigation "$(navigation_to_category Disks)"
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(cat "
  ! echo "$output" | grep -q "reload(bash"
}

@test "fast-path: the precomputed file equals guided_controller_list (output-equiv)" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_navigation "$(navigation_to_category Disks)"
  local direct; direct="$(guided_controller_list)"
  _controller_directive_to_action render /x/entry.sh >/dev/null
  [ "$(cat "$GUIDED_LIST_FILE")" = "$direct" ]
}

@test "fast-path: refresh also cats the precomputed list file" {
  export GUIDED_LIST_FILE="$TEST_DIR/list"
  set_navigation "$(navigation_to_values Kernels options.kernel kernel)"
  run _controller_directive_to_action refresh /x/entry.sh
  echo "$output" | grep -q "reload-sync(cat "
}

@test "fast-path: falls back to bash re-render with no list file wired" {
  unset GUIDED_LIST_FILE
  run _controller_directive_to_action render /x/entry.sh
  echo "$output" | grep -q "reload(bash /x/entry.sh list)"
}


# ── slice 03: full-profile User Editor fields (userfield sub-editors) ─────────

@test "list(useredit): shows the full profile rows" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_edit Users dave)"
  run guided_controller_list
  echo "$output" | grep -q "sudo: off"
  echo "$output" | grep -q "groups: (none)"
  echo "$output" | grep -q "git name: (unset)"
  echo "$output" | grep -q "git email: (unset)"
  echo "$output" | grep -q "ssh keys: 0"
  echo "$output" | grep -q "programs: (none)"
}

@test "enter(useredit): sudo toggles into the override" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_edit Users dave)"
  run guided_controller_enter "sudo: off   (Enter toggles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.dave.sudo' "$GUIDED_USERFORMS_FILE")" = "true" ]
}

@test "enter(useredit): groups opens a userfield multi-select" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_edit Users dave)"
  run guided_controller_enter "groups: (none)   (Enter edits)"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "userfield" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "groups" ]
}

@test "list+enter(userfield groups): mark options + toggle into the override" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_field Users dave groups groups)"
  run guided_controller_list
  echo "$output" | grep -q "\[ \] docker"
  run guided_controller_enter "[ ] docker"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.dave.groups' "$GUIDED_USERFORMS_FILE")" = '["docker"]' ]
}

@test "enter(userfield git.name): a typed value commits + backs to the editor" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_field Users dave git.name "git name")"
  run guided_controller_enter "" "Dave D"
  [ "$output" = "render" ]
  [ "$(jq -r '.dave.git.name' "$GUIDED_USERFORMS_FILE")" = "Dave D" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
}

@test "userfield ssh: add opens a text screen, then appends the key" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_field Users dave ssh "ssh keys")"
  run guided_controller_enter "+ Add SSH key"
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "ssh.add" ]
  run guided_controller_enter "" "ssh-ed25519 AAAA"
  [ "$(jq -c '.dave.ssh_authorized_keys' "$GUIDED_USERFORMS_FILE")" \
    = '["ssh-ed25519 AAAA"]' ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "ssh" ]   # back to the key list
}

@test "userfield programs: toggle marks against resolvable program names" {
  adhoc_editor_setup
  # a couple of resolvable programs under INSTALLER_DIR/programs/<cat>/<name>
  mkdir -p "$INSTALLER_DIR/programs/dev/git" "$INSTALLER_DIR/programs/dev/htop"
  set_navigation "$(navigation_to_user_field Users dave programs programs)"
  run guided_controller_enter "[ ] git"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.dave.programs' "$GUIDED_USERFORMS_FILE")" = '["git"]' ]
}


# ── extra-packages row runs the ＋Add guard at ENTRY time (ADR 0086) ─────────
# A raw name stays a package; a Menu-Owned name is informed, not promoted (its
# control is its sole home); a free-standing user program goes to Users. What
# reaches Config State stays canonical, so no Program name lands in packages.*.

@test "extra packages: a plain name stays a repo package" {
  mixed_programs_setup
  set_navigation "$(navigation_to_text Packages packages.repo.extra "extra packages")"
  run guided_controller_enter "" "htop"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.repo.extra' "$GUIDED_STATE_FILE")" = '["htop"]' ]
}

@test "extra packages: a Menu-Owned name is not added, just informed" {
  mixed_programs_setup
  set_navigation "$(navigation_to_text Packages packages.repo.extra "extra packages")"
  run guided_controller_enter "" "cups"
  [ "$status" -eq 0 ]
  # cups is Menu-Owned (Services → printing): not promoted, not left a package.
  [ "$(jq -c '.host_programs // []' "$GUIDED_STATE_FILE")" = '[]' ]
  [ "$(jq -c '.packages.repo.extra // []' "$GUIDED_STATE_FILE")" = '[]' ]
}

@test "extra packages: a mixed entry keeps the Menu-Owned name out of state" {
  mixed_programs_setup
  set_navigation "$(navigation_to_text Packages packages.repo.extra "extra packages")"
  run guided_controller_enter "" "htop cups"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.packages.repo.extra' "$GUIDED_STATE_FILE")" = '["htop"]' ]
  [ "$(jq -c '.host_programs // []' "$GUIDED_STATE_FILE")" = '[]' ]
}

@test "extra packages: routing reports where a Menu-Owned name went" {
  mixed_programs_setup
  set_navigation "$(navigation_to_text Packages packages.repo.extra "extra packages")"
  run guided_controller_enter "" "cups"
  [[ "$output" == *"managed by"* ]]
  [[ "$output" == *"cups"* ]]
}


# ── program picker option-set MEMBERSHIP (R22) ───────────────────────────────

@test "User Editor programs picker offers exactly the system:false programs" {
  mixed_programs_setup
  mkdir -p "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_field Users dave programs programs)"
  run guided_controller_list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx "\[ \] docker"
  # borg is Backup-owned (ADR 0086): filtered from the user picker too; only the
  # free-standing docker is offered.
  ! echo "$output" | grep -q "borg"
  ! echo "$output" | grep -q "cups"
  ! echo "$output" | grep -q "grub"
  [ "$(echo "$output" | grep -c '^\[')" -eq 1 ]
}

@test "back(userfield): returns to the user's editor" {
  adhoc_editor_setup
  set_navigation "$(navigation_to_user_field Users dave groups groups)"
  run guided_controller_back
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "dave" ]
}

@test "userfield groups (committed): dropping back to committed clears override" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '{"groups":["docker"]}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"; printf '{}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_user_field Users alice groups groups)"
  # committed has docker; toggling it off then on again lands back on committed
  guided_controller_enter "[x] docker" >/dev/null    # remove → override []
  run guided_controller_enter "[ ] docker"           # add back → equals committed
  [ "$(jq -c '.' "$GUIDED_USERFORMS_FILE")" = '{}' ]   # strict delta: no override
}
