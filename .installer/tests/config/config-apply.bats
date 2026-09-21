#!/usr/bin/env bats
# Tests for .installer/lib/config/config-apply.sh — the Config Apply Planner
# (ADR 0134). ca_plan is pure JSON-in/JSON-out; ca_ships_home_list walks a
# programs tree. Every assertion is external: given these inputs, this plan.
#
# Apply rule (from the design prototype):
#   apply(program) = selected && ships_home(program) && !config_exclude(program)

setup() {
  source "$BATS_TEST_DIRNAME/../../lib/config/config-apply.sh"
}

# plan <programs> <ships_home> <exclude> — compact plan output.
plan() { ca_plan "$1" "$2" "$3" | jq -c .; }

@test "plan: a selected program that ships home and is not excluded applies" {
  run plan '["kitty"]' '["kitty"]' '[]'
  echo "$output" | jq -e '. == ["kitty"]'
}

@test "plan: a package-only program (no home) is not in the plan" {
  run plan '["ccache","kitty"]' '["kitty"]' '[]'
  echo "$output" | jq -e '. == ["kitty"]'
}

@test "plan: an excluded program is not in the plan though its package installs" {
  run plan '["kitty","zsh"]' '["kitty","zsh"]' '["kitty"]'
  echo "$output" | jq -e '. == ["zsh"]'
}

@test "plan: empty config_exclude applies every home-shipping program" {
  run plan '["kitty","zsh","ccache"]' '["kitty","zsh"]' '[]'
  echo "$output" | jq -e '. == ["kitty","zsh"]'
}

@test "plan: preserves selection order and dedupes" {
  run plan '["zsh","kitty","zsh"]' '["kitty","zsh"]' '[]'
  echo "$output" | jq -e '. == ["zsh","kitty"]'
}

@test "plan: a program not selected never applies even if it ships home" {
  run plan '["zsh"]' '["kitty","zsh"]' '[]'
  echo "$output" | jq -e '. == ["zsh"]'
}

# ── ca_ships_home_list walks a programs tree ────────────────────────────────

@test "ships_home_list: lists exactly the programs that have a home/ dir" {
  root="$BATS_TEST_TMPDIR/programs"
  mkdir -p "$root/system/kitty/home/.config/kitty"
  mkdir -p "$root/system/zsh/home"
  mkdir -p "$root/dev/ccache"            # no home/ → package-only
  touch "$root/system/kitty/home/.config/kitty/kitty.conf"

  run bash -c "source '$BATS_TEST_DIRNAME/../../lib/config/config-apply.sh'
               ca_ships_home_list '$root' | jq -c 'sort'"
  echo "$output" | jq -e '. == ["kitty","zsh"]'
}

@test "home_dir: resolves a program name to its home/ path" {
  root="$BATS_TEST_TMPDIR/programs"
  mkdir -p "$root/system/kitty/home"
  run bash -c "source '$BATS_TEST_DIRNAME/../../lib/config/config-apply.sh'
               ca_home_dir '$root' kitty"
  [ "$status" -eq 0 ]
  [[ "$output" == "$root/system/kitty/home" ]]
}

@test "home_dir: returns non-zero for a program without a home/" {
  root="$BATS_TEST_TMPDIR/programs"
  mkdir -p "$root/dev/ccache"
  run bash -c "source '$BATS_TEST_DIRNAME/../../lib/config/config-apply.sh'
               ca_home_dir '$root' ccache"
  [ "$status" -ne 0 ]
}

# ── ca_stow_selection — the ./stow-configs.sh wrapper's pure brain ──────────────
# select <ships> <except> <only> — compact selection output.
select_() { ca_stow_selection "$1" "$2" "$3" | jq -c .; }

@test "selection: no except and no positional args stows every home program" {
  run select_ '["kitty","lazygit","zsh"]' '[]' '[]'
  echo "$output" | jq -e '. == ["kitty","lazygit","zsh"]'
}

@test "selection: --except subtracts the named programs" {
  run select_ '["kitty","lazygit","zsh"]' '["lazygit"]' '[]'
  echo "$output" | jq -e '. == ["kitty","zsh"]'
}

@test "selection: positional args select exactly that subset, in their order" {
  run select_ '["kitty","lazygit","zsh"]' '[]' '["zsh","kitty"]'
  echo "$output" | jq -e '. == ["zsh","kitty"]'
}

@test "selection: a positional name that ships no home is dropped" {
  run select_ '["kitty","zsh"]' '[]' '["kitty","ccache"]'
  echo "$output" | jq -e '. == ["kitty"]'
}

@test "selection: an --except name that ships no home is a no-op" {
  run select_ '["kitty","zsh"]' '["ccache"]' '[]'
  echo "$output" | jq -e '. == ["kitty","zsh"]'
}
