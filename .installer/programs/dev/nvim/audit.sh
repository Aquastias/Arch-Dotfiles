# shellcheck shell=bash
# audit-timeout: 5400
# Feature Audit probe for nvim (ADR 0152; contract: PROGRAM_SPEC.md). Runs in
# the user's real config, headless: plugins load, :checkhealth is clean, every
# Language Registry toolchain works (ADR 0141), and every keymap — parsed
# from the shipped config, plus any only the live dump sees — does what its
# expectation says (audit-binds.jsonc, one fresh nvim per bind). The lua side
# reports through files: headless nvim prints its own messages on stdout.
fa_require_pkg nvim neovim || return 0
fa_as_user || return 0
export TERM=xterm-256color
# probe.lua SKIPs the Host Core toolchain where it is not inherited
fa_host_core && export FA_HOST_CORE=1 || export FA_HOST_CORE=0
fx="$FA_DIR/audit-fixtures"
o="$(mktemp)" live="$(mktemp)"
# Run the lua after VimEnter, as a user's keypress would be: -c runs before
# it, so VeryLazy plugins (bufferline) were never loaded.
# _fa_nvim <timeout> <lua-file> (env passes through to nvim)
_fa_nvim() {
  timeout "$1" nvim --headless -c "autocmd VimEnter * ++once lua
    vim.schedule(function() vim.cmd.luafile('$2') end)"
}

if FA_OUT="$o" FA_LIVE="$live" \
     _fa_nvim 900 "$fx/probe.lua" >/dev/null 2>/tmp/fa-nvim.err
then cat "$o"
else
  cat "$o"
  fa_fail nvim-probe \
    "headless probe did not finish: $(head -1 /tmp/fa-nvim.err)"
fi

if [[ ! -f "$FA_DIR/binds-plan.jsonl" ]]; then
  fa_skip nvim-binds "no plan staged"; rm -f "$o" "$live"; return 0
fi
# live-only maps go through the same matcher as the static plan
_fa_live_plan() {
  local ej
  ej="$(sed -e 's|[[:space:]]//[^"]*$||' -e '/^[[:space:]]*\/\//d' \
    "$FA_DIR/audit-binds.jsonc" | jq -c .)"
  jq -R -c --argjson e "$ej" -f "$FA_DIR/binds-plan.jq" < "$live"
}
# \x1f, not a tab: IFS whitespace collapses an empty field and shifts the rest
while IFS=$'\x1f' read -r key mode effect arg needs; do
  id="bind-nvim-$key"
  case "$effect" in
    none) fa_fail nvim-untested-bind "$mode $key has no audit expectation"
          continue ;;
    unverifiable) fa_skip "$id" "unverifiable: $arg"; continue ;;
  esac
  # an LSP bind needs a server, a host-core one a Host Core tool (rg…):
  # neither is on a host not inheriting Host Core (Probe Gate)
  if [[ "$needs" == *lsp* || "$needs" == *host-core* ]] \
     && [[ "$FA_HOST_CORE" == 0 ]]; then
    fa_skip "$id" "needs $needs: Host Core not inherited"; continue
  fi
  : > "$o"
  FA_KEY="$key" FA_MODE="$mode" FA_EFFECT="$effect" FA_ARG="$arg" \
    FA_ID="$id" FA_NEEDS="$needs" FA_OUT="$o" \
    _fa_nvim 40 "$fx/key.lua" >/dev/null 2>&1
  rc=$?
  if [[ -s "$o" ]]; then cat "$o"
  elif [[ "$effect" == quits && "$rc" == 0 ]]; then fa_pass "$id" "quit nvim"
  elif [[ "$rc" == 124 ]]; then
    fa_fail "$id" "hung (a prompt waiting for input?)"
  else fa_fail "$id" "nvim exited $rc before judging the effect"; fi
done < <({ cat "$FA_DIR/binds-plan.jsonl"; _fa_live_plan; } \
  | jq -r '[.chord, (.action | split(" ")[0] | split(",")[0]),
            (.effect // "none"), (.arg // .reason // ""),
            (.needs // "")] | join("\u001f")')
rm -f "$o" "$live"
