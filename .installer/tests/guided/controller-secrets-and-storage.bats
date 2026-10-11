#!/usr/bin/env bats
# Tests: secrets, encryption, mirrors (split from controller.bats;
# shared setup in controller-helpers.bash)

load controller-helpers


# ── slice 05: inline masked password entry (secret screen) ───────────────────

@test "enter(rooteditor): root pw opens the inline screen under rich chrome" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_root_editor Users)"
  run guided_controller_enter "password: (not set)"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "secret" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" target)" = "root" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
}

@test "enter(rooteditor): root pw falls back to execute() without rich chrome" {
  secret_setup; unset GUIDED_RICH_CHROME
  set_navigation "$(navigation_to_root_editor Users)"
  [ "$(guided_controller_enter "password: (not set)")" = "secret-root" ]
}

@test "enter(secret entry): stashes the buffer as pending + moves to confirm" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWBUF_FILE"
  set_navigation "$(navigation_to_secret Users root "" entry)"
  run guided_controller_enter ""
  [ "$output" = "render" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "confirm" ]
  [ "$(cat "$GUIDED_PWPENDING_FILE")" = "hunter2" ]
  [ -z "$(cat "$GUIDED_PWBUF_FILE")" ]            # buffer cleared for the retype
}

@test "enter(secret confirm): a match writes the root password + backs out" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWPENDING_FILE"
  printf 'hunter2' > "$GUIDED_PWBUF_FILE"
  set_navigation "$(navigation_to_secret Users root "" confirm)"
  run guided_controller_enter ""
  [ "$output" = "render" ]
  [ "$(jq -r '.root_password' "$GUIDED_SECRETS_FILE")" = "hunter2" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ -z "$(cat "$GUIDED_PWBUF_FILE")" ]
}

@test "enter(secret confirm): a mismatch re-prompts and writes nothing" {
  secret_setup
  printf 'hunter2' > "$GUIDED_PWPENDING_FILE"
  printf 'huntor2' > "$GUIDED_PWBUF_FILE"
  set_navigation "$(navigation_to_secret Users root "" confirm)"
  run guided_controller_enter ""
  [ "$output" = "secret-mismatch" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
  [ "$(jq -r '.root_password // "unset"' "$GUIDED_SECRETS_FILE")" = "unset" ]
}

@test "enter(secret entry): an empty password is refused" {
  secret_setup
  : > "$GUIDED_PWBUF_FILE"
  set_navigation "$(navigation_to_secret Users root "" entry)"
  run guided_controller_enter ""
  [[ "$output" == notice* ]]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
}

@test "secret flow (user): a confirmed match writes that user's password" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"users":["dave"]}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values Users users users)"
  run guided_controller_enter "      password (dave): (not set)"
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" target)" = "user" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" user)" = "dave" ]
  printf 'davepw' > "$GUIDED_PWBUF_FILE"
  guided_controller_enter "" >/dev/null                 # entry → confirm
  printf 'davepw' > "$GUIDED_PWBUF_FILE"
  guided_controller_enter "" >/dev/null                 # confirm → save
  [ "$(jq -r '.users.dave.password' "$GUIDED_SECRETS_FILE")" = "davepw" ]
}


# ── Encryption Editor + collapsed Disks row (ADR 0059) ───────────────────────

@test "list(Disks): the Encryption row reads off + no legacy rows when off" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '{}\n' > "$GUIDED_SECRETS_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -qx "Encryption ▸ off"
  ! echo "$output" | grep -qE "^Encryption: "        # no generic bool row
  ! echo "$output" | grep -q "encryption password:"  # no old sub-row
}

@test "list(Disks): the Encryption row shows on · default when on + unset" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -q "Encryption ▸ on · default 12345678"
  ! echo "$output" | grep -q "⚠"                     # no gate warning anymore
}

@test "list(Disks): the Encryption row carries the override dot when on" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -qE "Encryption ▸ on · default 12345678  ●$"
}

@test "list(Disks): the Encryption row reads on · custom once captured" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"
  printf '%s\n' '{"enc_passphrase":"corrhorse"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -q "Encryption ▸ on · custom"
}

@test "enter(Disks): the Encryption row opens the Encryption Editor" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "Encryption ▸ on · default 12345678"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "list(encryption): off shows only the enabled row + Back" {
  printf '%s\n' '{"options":{"encryption":false}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  run guided_controller_list
  echo "$output" | grep -qx "enabled: off"
  ! echo "$output" | grep -q "password:"
  echo "$output" | grep -q "← Back"
}

@test "list(encryption): on shows enabled + password + Back" {
  export GUIDED_SECRETS_FILE="$TEST_DIR/secrets.json"; printf '{}\n' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  run guided_controller_list
  echo "$output" | grep -qx "enabled: on"
  echo "$output" | grep -qx "password: default 12345678"
}

@test "enter(encryption): enabled toggles in place and stays on the editor" {
  _seed_baseline                                 # so the strict-delta normalise
  set_navigation "$(navigation_to_encryption Disks)"           # has the default to compare to
  run guided_controller_enter "enabled: off"
  [ "$output" = "refresh" ]
  [ "$(jq -r '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
  # toggling back to the baseline drops the override (strict delta)
  run guided_controller_enter "enabled: on"
  [ "$output" = "refresh" ]
  [ "$(jq 'getpath(["options","encryption"]) == null' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "enter(encryption): password opens the inline capture (rich chrome)" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  run guided_controller_enter "password: default 12345678"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "secret" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" target)" = "enc" ]
}

@test "enter(encryption): password falls back to execute() (legacy)" {
  secret_setup; unset GUIDED_RICH_CHROME
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  [ "$(guided_controller_enter "password: default 12345678")" = "secret-enc" ]
}

@test "enter(secret entry enc): a passphrase under 8 chars is refused" {
  secret_setup
  printf 'short7x' > "$GUIDED_PWBUF_FILE"        # 7 chars
  set_navigation "$(navigation_to_secret Disks enc "" entry)"
  run guided_controller_enter ""
  [[ "$output" == notice* ]]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "entry" ]
  [ -z "$(cat "$GUIDED_PWPENDING_FILE")" ]        # nothing stashed
}

@test "enter(secret entry enc): 8+ chars advances to confirm" {
  secret_setup
  printf 'eightchr' > "$GUIDED_PWBUF_FILE"        # 8 chars
  set_navigation "$(navigation_to_secret Disks enc "" entry)"
  run guided_controller_enter ""
  [ "$output" = "render" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" phase)" = "confirm" ]
  [ "$(cat "$GUIDED_PWPENDING_FILE")" = "eightchr" ]
}

@test "secret flow (enc): confirmed passphrase writes enc + returns to the Editor" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  run guided_controller_enter "password: default 12345678"
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" target)" = "enc" ]
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"
  guided_controller_enter "" >/dev/null                  # entry → confirm
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"
  guided_controller_enter "" >/dev/null                  # confirm → save
  [ "$(jq -r '.enc_passphrase' "$GUIDED_SECRETS_FILE")" = "corrhorse" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "encryption" ]
}

@test "enter(encryption): setting a passphrase leaves enabled unchanged" {
  secret_setup; export GUIDED_RICH_CHROME=1
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  guided_controller_enter "password: default 12345678" >/dev/null
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"; guided_controller_enter "" >/dev/null
  printf 'corrhorse' > "$GUIDED_PWBUF_FILE"; guided_controller_enter "" >/dev/null
  [ "$(jq -r '.options.encryption' "$GUIDED_STATE_FILE")" = "true" ]
}

@test "encryption editor: a stored passphrase survives an off→on toggle" {
  secret_setup
  printf '%s\n' '{"enc_passphrase":"corrhorse"}' > "$GUIDED_SECRETS_FILE"
  printf '%s\n' '{"options":{"encryption":true}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_encryption Disks)"
  guided_controller_enter "enabled: on"  >/dev/null   # → off (baseline: override dropped)
  guided_controller_enter "enabled: off" >/dev/null   # → on again
  run guided_controller_list
  echo "$output" | grep -qx "password: custom"    # retained, not cleared
}

@test "back(encryption): Esc returns to the Disks category" {
  set_navigation "$(navigation_to_encryption Disks)"
  run guided_controller_back
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" category)" = "Disks" ]
}

@test "directive→action: secret-enc executes the masked capture verb" {
  local action; action="$(_controller_directive_to_action secret-enc /e)"
  [[ "$action" == *"secret enc"* ]]
}

@test "mask entry: the fzf mask subcommand masks + captures the buffer" {
  export GUIDED_PWBUF_FILE="$TEST_DIR/pwbuf2"; printf 'ab' > "$GUIDED_PWBUF_FILE"
  # query is 2 bullets + a newly typed 'c'
  run bash "$BATS_TEST_DIRNAME/../../lib/guided/fzf-entry.sh" mask "••c"
  [ "$output" = "•••" ]                           # display: 3 bullets
  [ "$(cat "$GUIDED_PWBUF_FILE")" = "abc" ]       # buffer captured the real char
}


# ── impermanence: one Disks row → impermanence editor (ADR 0066) ──────────────

@test "list(category Disks): one Impermanence row, no plain toggle or add row" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  [ "$(echo "$output" | grep -cE '^Impermanence ▸ ')" = "1" ]
  ! echo "$output" | grep -qiE '^impermanence:'
  ! echo "$output" | grep -q "Add persist directory"
}

@test "list(category Disks): Impermanence row is off by default, dot when set" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^Impermanence ▸ off$'
  printf '%s\n' '{"options":{"impermanence":{"enabled":true}}}' \
    > "$GUIDED_STATE_FILE"
  run guided_controller_list
  echo "$output" | grep -qE '^Impermanence ▸ on  ●$'
}

@test "enter(category): Impermanence opens the impermanence editor" {
  set_navigation "$(navigation_to_category Disks)"
  run guided_controller_enter "Impermanence ▸ off"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "impermanence" ]
}

@test "list(impermanence): off shows only enabled off + Back" {
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^enabled: off$'
  ! echo "$output" | grep -q "Add persist directory"
  ! echo "$output" | grep -q "curated defaults"
  echo "$output" | grep -q "← Back"
}

@test "list(impermanence): on shows enabled, persist dirs, curated line, add" {
  printf '%s\n' \
    '{"options":{"impermanence":{"enabled":true}},
      "persist":{"directories":["/var/lib/foo"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_list
  echo "$output" | grep -qE '^enabled: on$'
  echo "$output" | grep -qxF '/var/lib/foo'
  echo "$output" | grep -qE '^curated defaults: [0-9]+ paths always persisted'
  echo "$output" | grep -q "Add persist directory"
  echo "$output" | grep -q "← Back"
}

@test "enter(impermanence): toggling enabled flips it and stays (refresh)" {
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_enter "enabled: off"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.options.impermanence.enabled' "$GUIDED_STATE_FILE")" = "true" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "impermanence" ]
}

@test "enter(impermanence): toggling back to the baseline drops the override" {
  config_state_seed_defaults "$(config_state_new)" > "$GUIDED_BASELINE_FILE"
  printf '%s\n' '{"options":{"impermanence":{"enabled":true}}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_enter "enabled: on"
  # strict delta: landing on the baseline (off) leaves no override
  [ "$(jq -c '.options.impermanence.enabled // "gone"' \
    "$GUIDED_STATE_FILE")" = '"gone"' ]
}

@test "enter(impermanence): Add persist opens the __persist__ text screen" {
  printf '%s\n' '{"options":{"impermanence":{"enabled":true}}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_enter "Add persist directory ▸ extend the curated defaults"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "text" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "__persist__" ]
}

@test "enter(text __persist__): appends dir and returns to the editor" {
  printf '%s\n' '{"options":{"impermanence":{"enabled":true}}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_text Disks __persist__ "persist dir")"
  run guided_controller_enter "" "/srv/x"
  [ "$(jq -c '.persist.directories' "$GUIDED_STATE_FILE")" = '["/srv/x"]' ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "impermanence" ]
}

@test "enter(impermanence): Back returns to the Disks category" {
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_enter "← Back"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "category" ]
}

@test "enter(impermanence): Enter on a persist dir removes it and re-renders" {
  printf '%s\n' \
    '{"options":{"impermanence":{"enabled":true}},
      "persist":{"directories":["/srv/a","/srv/b"]}}' > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_impermanence Disks)"
  run guided_controller_enter "/srv/a"
  [ "$output" = "refresh" ]
  [ "$(jq -c '.persist.directories' "$GUIDED_STATE_FILE")" = '["/srv/b"]' ]
  # the enabled flag is left untouched
  [ "$(jq -c '.options.impermanence.enabled' "$GUIDED_STATE_FILE")" = "true" ]
}


# ── Mirrors & Repositories: optional repos + custom servers/repos (ADR 0072) ──

@test "enter(category): the optional-repos row opens its multi-select" {
  set_navigation "$(navigation_to_category "Mirrors & Repositories")"
  run guided_controller_enter "Optional repositories: multilib"
  [ "$output" = "render" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
  [ "$(navigation_get "$(<"$GUIDED_NAV_FILE")" field)" = "options.optional_repos" ]
}

@test "list(values optional_repos): marks the selected repos" {
  printf '%s\n' '{"options":{"optional_repos":["multilib","core-testing"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values "Mirrors & Repositories" options.optional_repos \
    "optional repositories")"
  run guided_controller_list
  echo "$output" | grep -q "\[x\] multilib"
  echo "$output" | grep -q "\[x\] core-testing"
  echo "$output" | grep -q "\[ \] extra-testing"
}

@test "list(values mirror_servers): lists servers + an Add action + Back" {
  printf '%s\n' '{"options":{"mirror_servers":["https://a/x"]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values "Mirrors & Repositories" options.mirror_servers \
    "custom servers")"
  run guided_controller_list
  echo "$output" | grep -q "https://a/x"
  echo "$output" | grep -q "+ Add server"
  echo "$output" | grep -q "← Back"
}

@test "enter(text mirror_servers): a URL appends and returns to the list" {
  set_navigation "$(navigation_to_text "Mirrors & Repositories" options.mirror_servers \
    "custom servers")"
  run guided_controller_enter "+ Add server" "https://mirror.example/repo"
  [ "$(jq -r '.options.mirror_servers[0]' "$GUIDED_STATE_FILE")" \
    = "https://mirror.example/repo" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}

@test "list(values custom_repositories): lists repos with their SigLevel + Add" {
  printf '%s\n' \
    '{"options":{"custom_repositories":[{"name":"cool","url":"https://x","sign_check":"Never"}]}}' \
    > "$GUIDED_STATE_FILE"
  set_navigation "$(navigation_to_values "Mirrors & Repositories" options.custom_repositories \
    "custom repositories")"
  run guided_controller_list
  echo "$output" | grep -q "cool — https://x · Never"
  echo "$output" | grep -q "+ Add repository"
}

@test "enter(text custom_repositories): a repo line appends a full object" {
  set_navigation "$(navigation_to_text "Mirrors & Repositories" options.custom_repositories \
    "custom repositories")"
  run guided_controller_enter "+ Add repository" "myrepo https://r Optional TrustAll"
  [ "$(jq -r '.options.custom_repositories[0].name' "$GUIDED_STATE_FILE")" \
    = "myrepo" ]
  [ "$(jq -r '.options.custom_repositories[0].url' "$GUIDED_STATE_FILE")" \
    = "https://r" ]
  [ "$(jq -r '.options.custom_repositories[0].sign_check' "$GUIDED_STATE_FILE")" \
    = "Optional" ]
  [ "$(jq -r '.options.custom_repositories[0].sign_option' "$GUIDED_STATE_FILE")" \
    = "TrustAll" ]
  [ "$(navigation_screen "$(<"$GUIDED_NAV_FILE")")" = "values" ]
}
