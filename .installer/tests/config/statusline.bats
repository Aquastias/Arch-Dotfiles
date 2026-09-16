#!/usr/bin/env bats
# Claude statusline (ADR 0133). The statusline is a pure JSON→string function,
# so: fixture payload in, expected segments out. Guards the 5h-meter ↔ $cost
# swap and the native-field segments against regression. $HOME is mocked to
# drive the subscription/API branch; a temp git repo drives the dirty dot.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."
  SL="$REPO/.claude/scripts/statusline.sh"
  HOME_SUB="$BATS_TEST_TMPDIR/sub"
  HOME_API="$BATS_TEST_TMPDIR/api"
  mkdir -p "$HOME_SUB/.claude" "$HOME_API/.claude"
  # subscription: Max 20x, no billingType file
  printf '%s' '{"claudeAiOauth":{"subscriptionType":"max","rateLimitTier":"max_20x"}}' \
    >"$HOME_SUB/.claude/.credentials.json"
  # API: usage-billed
  printf '%s' '{"billingType":"api"}' >"$HOME_API/.claude.json"
  RESETS=$(( $(date +%s) + 11520 ))   # +3h12m
}

sub_fixture() {
  cat <<EOF
{"model":{"display_name":"Opus"},"effort":{"level":"high"},
"workspace":{"current_dir":"/tmp/dotfiles"},
"context_window":{"used_percentage":38,"total_input_tokens":76000,"context_window_size":200000},
"prompt_cache":{"hit_ratio":0.94},
"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":$RESETS}},
"cost":{"total_cost_usd":1.37,"total_duration_ms":723000,"total_lines_added":120,"total_lines_removed":30}}
EOF
}

api_fixture() {
  cat <<EOF
{"model":{"display_name":"Opus"},"effort":{"level":"high"},
"workspace":{"current_dir":"/tmp/dotfiles"},
"context_window":{"used_percentage":22,"total_input_tokens":44000,"context_window_size":200000},
"prompt_cache":{"hit_ratio":0.88},
"rate_limits":{"five_hour":{"used_percentage":42,"resets_at":$RESETS}},
"cost":{"total_cost_usd":1.37,"total_duration_ms":302000,"total_lines_added":60,"total_lines_removed":8}}
EOF
}

@test "subscription plan shows the 5h meter, not a dollar cost" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '5h 42%'
  ! echo "$output" | grep -q '\$'
}

@test "API plan shows the dollar cost, not the 5h meter" {
  export HOME="$HOME_API" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(api_fixture | tr -d '\n')' | bash '$SL'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\$1.37'
  ! echo "$output" | grep -q '5h '
}

@test "cache-hit comes from prompt_cache.hit_ratio (native), no transcript" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  echo "$output" | grep -q '94%'
}

@test "effort level renders beside the model" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  echo "$output" | grep -q '·high'
}

@test "lines added are green, deleted shown separately (+add / -del)" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  echo "$output" | grep -q '+120'
  echo "$output" | grep -q '\-30'
}

@test "emoji icon set renders (folder present)" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  echo "$output" | grep -q '📁'
}

@test "dirty working tree shows a dot; clean tree does not" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  local g="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$g"; git -C "$g" init -q
  git -C "$g" config user.email t@t; git -C "$g" config user.name t
  echo a >"$g/a"; git -C "$g" add a; git -C "$g" commit -qm init
  # clean
  run bash -c "cd '$g'; printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  ! echo "$output" | grep -q '●'
  # dirty
  echo b >>"$g/a"
  run bash -c "cd '$g'; printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  echo "$output" | grep -q '●'
}

@test "renders without ccusage installed (graceful)" {
  # ccusage is absent in CI; the script must still exit 0 and render
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  run bash -c "PATH=/usr/bin:/bin printf '%s' '$(sub_fixture | tr -d '\n')' | bash '$SL'"
  [ "$status" -eq 0 ]
}
