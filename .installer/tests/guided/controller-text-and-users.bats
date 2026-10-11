#!/usr/bin/env bats
# Tests: text screen and users (split from controller.bats;
# shared setup in controller-helpers.bash)

load controller-helpers


# ── text screen: typed INTO fzf's query line, never leaves the window ─────────

@test "enter(text): a typed query commits the scalar + returns to the category" {
  set_navigation "$(navigation_to_text System system.hostname hostname)"
  run guided_controller_enter "current: (unset)" "myhost"
  [ "$output" = "render" ]
  [ "$(jq -r '.system.hostname' "$GUIDED_STATE_FILE")" = "myhost" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(text): an empty query leaves the value unchanged" {
  set_navigation "$(navigation_to_text System system.hostname hostname)"
  run guided_controller_enter "current: (unset)" ""
  [ "$output" = "render" ]
  [ "$(jq -c '. == {}' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(text): sysctl parses key=value from the query" {
  set_navigation "$(navigation_to_text Security sysctl sysctl)"
  run guided_controller_enter "current: (unset)" "vm.swappiness=20"
  [ "$(jq -c '.sysctl["vm.swappiness"]' "$GUIDED_STATE_FILE")" = "20" ]
}

@test "enter(text __persist__): a typed path appends to persist.directories" {
  set_navigation "$(navigation_to_text Disks __persist__ "persist dir")"
  run guided_controller_enter "current: (unset)" "/var/lib/foo"
  [ "$(jq -c '.persist.directories' "$GUIDED_STATE_FILE")" = '["/var/lib/foo"]' ]
}


# ── sysctl as a list screen (default vm.swappiness=10) ───────────────────────

@test "enter(category): sysctl opens its list screen" {
  set_navigation "$(navigation_to_category Security)"
  run guided_controller_enter "Sysctl: "
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

@test "list(values sysctl): lists current pairs + an Add action + Back" {
  printf '%s\n' '{"sysctl":{"vm.swappiness":10}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Security sysctl sysctl)"
  run guided_controller_list
  echo "$output" | grep -q "vm.swappiness=10"
  echo "$output" | grep -q "+ Add sysctl"
  echo "$output" | grep -q "← Back"
}

@test "enter(values sysctl): + Add opens the key=value text editor" {
  set_navigation "$(navigation_to_values Security sysctl sysctl)"
  run guided_controller_enter "+ Add sysctl (key=value)"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}

@test "enter(text sysctl): adding a pair returns to the sysctl list screen" {
  set_navigation "$(navigation_to_text Security sysctl sysctl)"
  run guided_controller_enter "+ Add sysctl (key=value)" "vm.dirty_ratio=20"
  [ "$(jq -c '.sysctl["vm.dirty_ratio"]' "$GUIDED_STATE_FILE")" = "20" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "sysctl" ]
}


# ── users as a native screen: toggle existing + in-fzf create (no terminal) ──

@test "enter(category): users opens its native screen" {
  set_navigation "$(navigation_to_category Users)"
  run guided_controller_enter "Users: "
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "list(values users): existing users marked + Create + Back, core excluded" {
  export INSTALLER_DIR="$TEST_DIR"
  mkdir -p "$INSTALLER_DIR/users/alice" "$INSTALLER_DIR/users/bob" "$INSTALLER_DIR/users/core"
  printf '{}' > "$INSTALLER_DIR/users/alice/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/bob/profile.jsonc"
  printf '{}' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  echo "$output" | grep -q "^alice — "          # enabled: name — shell · pw …
  echo "$output" | grep -q "^bob — disabled$"   # disabled: no checkbox
  ! echo "$output" | grep -q "core"
  echo "$output" | grep -q "+ Create user"
}

@test "enter(values users): a user row opens its User Editor (slice 02)" {
  printf '%s\n' '{"users":["alice","bob"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_enter "bob — bash · pw default 12345"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "bob" ]
}

@test "enter(values users): + Create opens the new-user text editor" {
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_enter "+ Create user (name)"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "__newuser__" ]
}


# ── in-menu credentials (ticket 03) ──────────────────────────────────────────

@test "list(values users): rows tag unset secrets 'default 12345' (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  echo "$output" | grep -qx "root — bash · pw default 12345"
  echo "$output" | grep -q "^aquastias — zsh · pw default 12345"
  echo "$output" | grep -qE '^ +password \(aquastias\): default 12345$'
}

@test "list(values users): rows tag 'custom' once the secret file has them" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  echo "$output" | grep -qx "root — bash · pw custom"
  echo "$output" | grep -qE '^ +password \(aquastias\): custom$'
}

@test "list(values users): a wired age key tags unset secrets 'from age'" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"],"options":{"age_key_url":"https://k/age"}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  echo "$output" | grep -qx "root — bash · pw from age"
  echo "$output" | grep -qE '^ +password \(aquastias\): from age$'
}

@test "list(values users): an operator override beats a wired age key ('custom')" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"age_key_url":"https://k/age"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  echo "$output" | grep -qx "root — bash · pw custom"
}

@test "enter(values users): the merged root row opens the Root Editor (ADR 0063)" {
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_enter "root — bash · pw default 12345"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "rooteditor" ]
}

@test "enter(values users): a per-user password row captures for that user" {
  set_navigation "$(navigation_to_values Users users users)"
  [ "$(guided_controller_enter "      password (aquastias): default 12345")" \
    = "secret-user aquastias" ]
}


# ── Users screen: no disk-encryption row (ADR 0059) ──────────────────────────
# The disk passphrase moved to the Disks Encryption Editor; the Users screen is
# now strictly accounts. Its rows still report the ACCOUNT default (12345), not
# the disk default — guarding the deliberate split against a single-constant
# refactor.

@test "list(values users): no disk-encryption row, even with encryption on" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"],"options":{"encryption":true}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_list
  ! echo "$output" | grep -q "disk encryption:"
  echo "$output" | grep -qx "root — bash · pw default 12345"   # account default
}

@test "enter(values users): no row routes to the passphrase capture" {
  set_navigation "$(navigation_to_values Users users users)"
  # the old row line, were it still handled, would emit secret-enc; it must not.
  [ "$(guided_controller_enter "disk encryption: default 12345678")" != "secret-enc" ]
}


# ── Root Editor: password + shell behind one editor (ADR 0063) ───────────────
# The merged root row opens a Root Editor exposing exactly `password` and `shell`.
# Storage is unchanged (options.root_shell + the no-SOPS root role); only the
# surface moved off the Users list into this editor.

@test "list(rooteditor): shows a password row + a shell row (default bash)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_navigation "$(navigation_to_root_editor Users)"
  run guided_controller_list
  echo "$output" | grep -qx "password: default 12345"
  echo "$output" | grep -q "shell: bash"
  echo "$output" | grep -q "← Back"
}

@test "enter(rooteditor): shell cycles bash→zsh into options.root_shell" {
  set_navigation "$(navigation_to_root_editor Users)"
  run guided_controller_enter "shell: bash   (Enter cycles)"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.options.root_shell' "$GUIDED_STATE_FILE")" = "/bin/zsh" ]
}

@test "enter(rooteditor): shell cycles zsh→fish" {
  printf '%s\n' '{"options":{"root_shell":"/bin/zsh"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_root_editor Users)"
  guided_controller_enter "shell: zsh   (Enter cycles)" >/dev/null
  [ "$(jq -r '.options.root_shell' "$GUIDED_STATE_FILE")" = "/bin/fish" ]
}

@test "enter(rooteditor): cycling shell to default (bash) drops the override" {
  printf '%s\n' '{"options":{"root_shell":"/bin/fish"}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_root_editor Users)"
  guided_controller_enter "shell: fish   (Enter cycles)" >/dev/null
  [ "$(jq -r '.options.root_shell // "unset"' "$GUIDED_STATE_FILE")" = "unset" ]
}

@test "enter(rooteditor): password falls back to execute() without rich chrome" {
  unset GUIDED_RICH_CHROME
  set_navigation "$(navigation_to_root_editor Users)"
  [ "$(guided_controller_enter "password: default 12345")" = "secret-root" ]
}

@test "back(rooteditor): Esc returns to the Users list" {
  set_navigation "$(navigation_to_root_editor Users)"
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}


# ── action rows visible in rich chrome (ADR 0063) ────────────────────────────

@test "list(values users) rich: + Create user + Back render as visible rows" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  GUIDED_RICH_CHROME=1 run guided_controller_list
  echo "$output" | grep -q "+ Create user"
  echo "$output" | grep -q "← Back"
}


# ── user detail preview (ADR 0063) ───────────────────────────────────────────
# The Users screen joins the preview set; hovering a user row shows its effective
# (core-merged, override-applied) profile. A session-created user reflects its
# in-progress editor-form state (held in the userforms file).

@test "preview(values users): the Users screen is registered for a preview" {
  set_navigation "$(navigation_to_values Users users users)"
  run _controller_field_has_preview users
  [ "$status" -eq 0 ]
}

@test "preview(values users): a session user shows its in-progress form state" {
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '%s\n' '{"alice":{"shell":"/bin/fish","sudo":true,
    "groups":["wheel","docker"],"programs":["git"],
    "ssh_authorized_keys":["k1","k2"],"git":{"name":"A","email":"a@x"}}}' \
    > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_preview "alice — fish · pw default 12345"
  echo "$output" | grep -q "/bin/fish"        # shell
  echo "$output" | grep -q "sudo:.*on"
  echo "$output" | grep -q "groups:.*wheel, docker"
  echo "$output" | grep -q "programs:"
  echo "$output" | grep -q "git:.*A <a@x>"
  echo "$output" | grep -q "ssh keys:.*2"      # SSH-key count
}

@test "preview(values users): shows effective (core-merged) values" {
  mkdir -p "$INSTALLER_DIR/users"/{core,bob}
  printf '{}\n' > "$INSTALLER_DIR/users/core/profile.jsonc"
  printf '{"shell":"/bin/bash","groups":["wheel"]}\n' \
    > "$INSTALLER_DIR/users/bob/profile.jsonc"
  export GUIDED_USERFORMS_FILE="$TEST_DIR/uf.json"
  printf '{"bob":{"shell":"/bin/zsh"}}\n' > "$GUIDED_USERFORMS_FILE"
  printf '%s\n' '{"users":["bob"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_preview "bob — zsh · pw default 12345"
  echo "$output" | grep -q "/bin/zsh"          # override applied
  echo "$output" | grep -q "wheel"             # committed group merged in
}

@test "preview(values users): the root row shows shell + password source" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_preview "root — bash · pw default 12345"
  echo "$output" | grep -q "shell:.*bash"
  echo "$output" | grep -q "password:.*default 12345"
}

@test "preview(values users): + Create user previews nothing" {
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_preview "+ Create user (name)"
  [ -z "$output" ]
}

@test "proceed gate: never blocked — installs with secrets unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: allowed (terminal proceed) once all are set" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: inert (proceed) when no secrets file is wired" {
  unset GUIDED_SECRETS_FILE
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}


# ── slice 01: flatten Users + top-level password warning ─────────────────────

@test "enter(top): Users flattens straight to the users screen (no category)" {
  set_navigation '{"screen":"top"}'
  run guided_controller_enter "Users — primary user, extra accounts"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "users" ]
}

@test "back(values users): returns to top, not the category screen" {
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_back
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "top" ]
}

@test "list(top): no ⚠ block — Proceed reads review & install with pw unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  run guided_controller_list
  ! echo "$output" | grep -q "pw needed"
  ! echo "$output" | grep -q "set passwords first"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "list(top): no ⚠, normal Proceed once every password is set" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","users":{"aquastias":{"password":"a"}}}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"users":["aquastias"]}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  run guided_controller_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "list(top): undecorated when no secrets file is wired" {
  unset GUIDED_SECRETS_FILE
  set_navigation '{"screen":"top"}'
  run guided_controller_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}


# ── encryption passphrase: never a gate (ADR 0055, supersedes ADR 0054) ──────

@test "list(top): no Disks ⚠ block when passphrase unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  run guided_controller_list
  ! echo "$output" | grep -q "pw needed"
  echo "$output" | grep -q "Proceed ▸ review & install"
}

@test "proceed gate: installs even when encryption on + passphrase unset (ADR 0055)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "proceed gate: allowed once the passphrase is set (encryption on)" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","enc_passphrase":"corrhorse"}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
}

@test "gate: encryption off does not block, and the passphrase is retained" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"root_password":"r","enc_passphrase":"corrhorse"}' \
    > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":false}}' > "$GUIDED_STATE_FILE"
  set_navigation '{"screen":"top"}'
  [ "$(guided_controller_enter "Proceed ▸ review & install")" = "terminal proceed" ]
  run guided_controller_list
  ! echo "$output" | grep -qE '^Disks — .*pw needed'   # no gate while off
  # retain-silently: the stored passphrase survives the toggle-off
  [ "$(jq -r '.enc_passphrase' "$GUIDED_SECRETS_FILE")" = "corrhorse" ]
}

@test "enter(values users): a disabled user row also opens its editor" {
  printf '%s\n' '{"users":["alice"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_enter "bob — disabled"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "useredit" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "bob" ]
}
