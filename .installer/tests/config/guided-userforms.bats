#!/usr/bin/env bats
# Tests for .os/lib/guided-userforms.sh — the Guided Installer's install-scoped
# per-user profile deltas (ADR 0051). A file path + name/key in, a file mutation
# or value out; pure, no fzf, no tty. The deltas are held aside like passwords —
# never the Config State, never a committed repo file — and merged onto the
# install clone at Proceed.

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/guided-userforms.sh"
  UF="$(mktemp)"; printf '{}\n' > "$UF"
}
teardown() { rm -f "$UF"; }

@test "set then get: a field round-trips into the per-user delta" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  [ "$(guided_userform_field "$UF" alice shell)" = "/bin/zsh" ]
  [ "$(guided_userform_get "$UF" alice)" = '{"shell":"/bin/zsh"}' ]
}

@test "get: an unset user is an empty object" {
  [ "$(guided_userform_get "$UF" nobody)" = '{}' ]
  [ -z "$(guided_userform_field "$UF" nobody shell)" ]
}

@test "set: multiple fields accumulate under one user" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  guided_userform_set "$UF" alice sudo 'true'
  [ "$(jq -c '.alice' "$UF")" = '{"shell":"/bin/zsh","sudo":true}' ]
}

@test "unset: drops one field but keeps the rest" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  guided_userform_set "$UF" alice sudo 'true'
  guided_userform_unset "$UF" alice shell
  [ "$(jq -c '.alice' "$UF")" = '{"sudo":true}' ]
}

@test "unset: removes the user entirely once its delta is empty" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  guided_userform_unset "$UF" alice shell
  [ "$(jq -c '.' "$UF")" = '{}' ]
}

@test "clear: drops a whole user's delta" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  guided_userform_set "$UF" bob sudo 'true'
  guided_userform_clear "$UF" alice
  [ "$(jq -c '.' "$UF")" = '{"bob":{"sudo":true}}' ]
}

@test "names: only users with a non-empty delta are listed" {
  guided_userform_set "$UF" alice shell '"/bin/zsh"'
  guided_userform_set "$UF" bob shell '"/bin/fish"'
  run guided_userform_names "$UF"
  echo "$output" | grep -qx alice
  echo "$output" | grep -qx bob
}
