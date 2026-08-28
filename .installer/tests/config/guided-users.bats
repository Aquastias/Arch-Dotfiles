#!/usr/bin/env bats
# Tests for the Guided Installer's Users authoring (issue 07): an ad-hoc user
# form → a User Profile delta over User Core, and the host users[] names. The
# delta is the committed artifact a Save writes and the Runner loads; it must be
# closed-schema-valid (no `name` key — the directory basename is the username,
# ADR 0036) and sparse (only what the operator set, so User Core fills the rest).
#
# Pure: a form JSON in → a profile JSON out, no TTY.

setup() {
  error() { echo "[error] $*" >&2; return 1; }
  export -f error

  # shellcheck source=../../lib/config/emit.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/emit.sh"
  # validate_config_schema — assert the authored user delta is schema-clean.
  # shellcheck source=../../lib/config/profile.sh
  source "$BATS_TEST_DIRNAME/../../lib/config/profile.sh"
}

# ── tracer: a form's fields become a User Profile, name dropped ─────────────

@test "guided_user_profile: maps the form fields, drops the username" {
  form='{"name":"alice","shell":"/bin/zsh","sudo":true}'

  run guided_user_profile "$form"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.shell == "/bin/zsh"'
  echo "$output" | jq -e '.sudo == true'
  echo "$output" | jq -e 'has("name") | not'   # the dir basename is the username
}

# ── a fuller form: arrays + git kept, empty/false fields pruned, schema-clean ─

@test "guided_user_profile: keeps arrays + git, prunes empties, validates" {
  form='{"name":"bob","shell":"","sudo":false,
         "groups":["docker"],"programs":["git"],
         "git":{"name":"Bob","email":"b@x.io"},
         "ssh_authorized_keys":[]}'

  run guided_user_profile "$form"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("shell") | not'                 # "" pruned
  echo "$output" | jq -e 'has("sudo") | not'                  # false pruned
  echo "$output" | jq -e '.groups == ["docker"]'
  echo "$output" | jq -e '.programs == ["git"]'
  echo "$output" | jq -e '.git.name == "Bob" and .git.email == "b@x.io"'
  echo "$output" | jq -e 'has("ssh_authorized_keys") | not'   # [] pruned

  run validate_config_schema user "$(guided_user_profile "$form")"
  [ "$status" -eq 0 ]
}
