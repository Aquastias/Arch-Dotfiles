#!/usr/bin/env bats
# Claude statusline (ADR 0133). The statusline is a pure JSON→string function,
# so: fixture payload in, expected segments out. Guards the 5h-meter ↔ $cost
# swap and the native-field segments against regression. $HOME is mocked to
# drive the subscription/API branch; a temp git repo drives the dirty dot; a
# stub PATH drives the ccusage-absent path.

setup() {
  REPO="$BATS_TEST_DIRNAME/../../.."
  # single source under the claude program home/ (ADR 0134)
  SL="$REPO/.installer/programs/dev/claude/home/.claude/scripts/statusline.sh"
  HOME_SUB="$BATS_TEST_TMPDIR/sub"
  HOME_API="$BATS_TEST_TMPDIR/api"
  mkdir -p "$HOME_SUB/.claude" "$HOME_API/.claude"
  CRED='{"claudeAiOauth":{"subscriptionType":"max","rateLimitTier":"max_20x"}}'
  printf '%s' "$CRED" >"$HOME_SUB/.claude/.credentials.json"
  printf '%s' '{"billingType":"api"}' >"$HOME_API/.claude.json"
  RESETS=$(( $(date +%s) + 11520 ))   # +3h12m
}

# render <fixture-json> — pipe a one-line fixture through the statusline.
# Sets $output/$status for the caller (bats `run` writes shell globals).
render() { run bash -c "printf '%s' '$1' | bash '$SL'"; }

fixture() { # $1 ctx% $2 hit $3 r5% $4 add $5 del
  printf '%s' "{\"model\":{\"display_name\":\"Opus\"},\
\"effort\":{\"level\":\"high\"},\
\"workspace\":{\"current_dir\":\"/tmp/dotfiles\"},\
\"context_window\":{\"used_percentage\":$1,\"total_input_tokens\":76000,\
\"context_window_size\":200000},\
\"prompt_cache\":{\"hit_ratio\":$2},\
\"rate_limits\":{\"five_hour\":{\"used_percentage\":$3,\"resets_at\":$RESETS}},\
\"cost\":{\"total_cost_usd\":1.37,\"total_duration_ms\":723000,\
\"total_lines_added\":$4,\"total_lines_removed\":$5}}"
}

@test "subscription plan shows the 5h meter, not the API dollar cost" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 38 0.94 42 120 30)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '5h 42%'
}

@test "API plan shows the dollar cost and no 5h meter (cost swap)" {
  export HOME="$HOME_API" SANDBOX_RUNTIME=1
  render "$(fixture 22 0.88 42 60 8)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '\$1.37'
  ! echo "$output" | grep -q '5h '
}

@test "near-limit exercises the red meter + red bar branch" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 93 0.28 91 40 15)"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '5h 91%'
  echo "$output" | grep -q '93%'
}

@test "cache-hit comes from prompt_cache.hit_ratio (native), no transcript" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 38 0.94 42 120 30)"
  echo "$output" | grep -q '94%'
}

@test "effort level renders beside the model" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 38 0.94 42 120 30)"
  echo "$output" | grep -q '·high'
}

@test "lines added are green, deleted shown separately (+add / -del)" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 38 0.94 42 120 30)"
  echo "$output" | grep -q '+120'
  echo "$output" | grep -q '\-30'
}

@test "emoji icon set renders (folder present)" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  render "$(fixture 38 0.94 42 120 30)"
  echo "$output" | grep -q '📁'
}

@test "dirty working tree shows a dot; clean tree does not" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  local g="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$g"; git -C "$g" init -q
  git -C "$g" config user.email t@t; git -C "$g" config user.name t
  echo a >"$g/a"; git -C "$g" add a; git -C "$g" commit -qm init
  local fx; fx="$(fixture 38 0.94 42 120 30)"
  run bash -c "cd '$g'; printf '%s' '$fx' | bash '$SL'"
  ! echo "$output" | grep -q '●'
  echo b >>"$g/a"
  run bash -c "cd '$g'; printf '%s' '$fx' | bash '$SL'"
  echo "$output" | grep -q '●'
}

@test "renders with ccusage genuinely absent from PATH (graceful)" {
  export HOME="$HOME_SUB" SANDBOX_RUNTIME=1
  # A stub PATH with only the tools the statusline needs — no ccusage, whether
  # or not the host has it installed.
  local bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  for t in bash jq git date awk stat grep cut tr id head cat mkdir mv; do
    ln -sf "$(command -v "$t")" "$bin/$t"
  done
  local fx; fx="$(fixture 38 0.94 42 120 30)"
  run env -i HOME="$HOME_SUB" SANDBOX_RUNTIME=1 PATH="$bin" \
    bash -c "printf '%s' '$fx' | bash '$SL'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '5h 42%'
  ! echo "$output" | grep -q '🔥'
}
