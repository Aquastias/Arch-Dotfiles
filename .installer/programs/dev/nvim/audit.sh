# shellcheck shell=bash
# audit-timeout: 5400
# Feature Audit probe for nvim (ADR 0152; contract: PROGRAM_SPEC.md). Runs in
# the user's real config, headless: plugins load, :checkhealth is clean, every
# Language Registry toolchain works (ADR 0141), and every shipped keymap does
# what its expectation says (audit-binds.jsonc, one fresh nvim per bind).
# The lua side reports through $FA_OUT: headless nvim prints its own
# messages on stdout.
fa_require_pkg nvim neovim || return 0
fa_as_user || return 0
export TERM=xterm-256color
fx="$FA_DIR/audit-fixtures"
o="$(mktemp)"

if FA_OUT="$o" timeout 900 nvim --headless -c "luafile $fx/probe.lua" \
     >/dev/null 2>/tmp/fa-nvim.err; then
  cat "$o"
else
  cat "$o"
  fa_fail nvim-probe \
    "headless probe did not finish: $(head -1 /tmp/fa-nvim.err)"
fi

if [[ ! -f "$FA_DIR/binds-plan.jsonl" ]]; then
  fa_skip nvim-binds "no plan staged"; rm -f "$o"; return 0
fi
while IFS=$'\t' read -r key mode effect arg needs; do
  id="bind-nvim-$key"
  if [[ "$effect" == unverifiable ]]; then
    fa_skip "$id" "unverifiable: $arg"; continue
  fi
  : > "$o"
  FA_KEY="$key" FA_MODE="$mode" FA_EFFECT="$effect" FA_ARG="$arg" \
    FA_ID="$id" FA_NEEDS="$needs" FA_OUT="$o" timeout 40 \
    nvim --headless -c "luafile $fx/key.lua" >/dev/null 2>&1
  rc=$?
  if [[ -s "$o" ]]; then cat "$o"
  elif [[ "$effect" == quits && "$rc" == 0 ]]; then fa_pass "$id" "quit nvim"
  elif [[ "$rc" == 124 ]]; then
    fa_fail "$id" "hung (a prompt waiting for input?)"
  else fa_fail "$id" "nvim exited $rc before judging the effect"; fi
done < <(jq -r '[.chord, (.action | split(" ")[0] | split(",")[0]),
                 (.effect // "none"), (.arg // .reason // ""),
                 (.needs // "")] | @tsv' "$FA_DIR/binds-plan.jsonl")
rm -f "$o"
