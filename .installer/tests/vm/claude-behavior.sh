#!/usr/bin/env bash
# =============================================================================
# tests/vm/claude-behavior.sh — behavioural seam for the served Claude Code
# config (ADR 0133, claude-code-config ticket 07). Runs on an Agent-Controllable
# VM through vm-agent.sh and proves what an unattended check can prove:
#
#   1. claude is on PATH and runs (--version).
#   2. A bubblewrap sandbox starts (the runtime Claude's Bash sandbox uses),
#      with socat present for its proxies.
#   3. The served settings carry the libvirt allowUnixSockets rule, and virsh
#      reaches libvirt from inside a bwrap sandbox — only via that socket (a
#      negative control hides it). Claude's own seccomp socket filter is not
#      exercised: that needs a logged-in session.
#   4. The served statusline renders its segments from a fixture payload.
#
# Claude's own sandbox and a live statusline need a logged-in session; that
# stays an operator check (credentials never go into a VM).
#
#   claude-behavior.sh [--profile <cat>/<name> | --vm <name>]
#   (default --profile desktop/combined)
# =============================================================================
set -uo pipefail

AGENT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../vm" && pwd)/vm-agent.sh"
sel=(--profile desktop/combined)
(($#)) && sel=("$@")

fails=0
check() { # check <label> <guest-command>
  if bash "$AGENT" "${sel[@]}" ssh "$2" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n' "$1"
    fails=$((fails + 1))
  fi
}

check "claude on PATH and runs" 'command -v claude && claude --version'
check "bwrap sandbox starts; socat present" \
  'command -v socat && bwrap --ro-bind / / --dev /dev --proc /proc \
     --unshare-net true'
check "settings allow the libvirt unix sockets" \
  'jq -e ".sandbox.network.allowUnixSockets
     | index(\"/run/libvirt/libvirt-sock\")" ~/.claude/settings.json'
check "virsh reaches libvirt from inside a bwrap sandbox" \
  'bwrap --ro-bind / / --dev /dev --proc /proc --unshare-net \
     virsh -c qemu:///system list --all'
# Negative control: with the socket hidden the same call fails, so the pass
# above really went through /run/libvirt (not some other path).
check "virsh fails in the sandbox once the libvirt socket is hidden" \
  '! bwrap --ro-bind / / --dev /dev --proc /proc --unshare-net \
     --tmpfs /run/libvirt virsh -c qemu:///system list --all'
# statusline: minimal subscription-style payload; the model + context segments
# must render.
check "statusline renders segments from a payload" \
  'printf %s "{\"model\":{\"display_name\":\"Opus\"},
     \"workspace\":{\"current_dir\":\"/tmp\"},
     \"context_window\":{\"used_percentage\":38,
       \"total_input_tokens\":76000,\"context_window_size\":200000}}" \
   | SANDBOX_RUNTIME=1 bash ~/.claude/scripts/statusline.sh | grep -q Opus'

((fails == 0)) && echo "claude-behavior: all checks passed" \
  || echo "claude-behavior: ${fails} check(s) failed"
exit "$((fails > 0))"
