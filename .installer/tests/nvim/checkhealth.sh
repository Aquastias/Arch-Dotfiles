#!/usr/bin/env bash
# Seam B / ticket 08 (ADR 0135): the acceptance gate for the served Neovim
# config, run on the target (the arch-combined VM verify-block, or an operator
# box). Fails if :checkhealth reports any ERROR, or if an in-scope LSP binary is
# missing from PATH. Benign WARNs (optional Swift, disabled providers) pass.
set -Eeuo pipefail

# Be robust to a bare (non-session) invocation, e.g. over ssh: without a locale
# and TERM, checkhealth reports environmental "Locale does not support UTF-8" /
# "infocmp" ERRORs that are not config defects. Default them so the gate judges
# the config, not the caller's shell.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export TERM="${TERM:-xterm-256color}"

log="$(mktemp)"
# Force-load nvim-dap first so :checkhealth includes the dap section and any
# debug-adapter defect surfaces (ADR 0140); it is otherwise lazy.
nvim --headless "+Lazy! load nvim-dap" "+checkhealth" \
  "+write! ${log}" "+qa!" >/dev/null 2>&1 || true

fails=0

# checkhealth marks failures with an "ERROR" line. Two are environmental (not
# config defects) and pass in a real kitty session: snacks.dashboard's "setup
# did not run" (needs a UI) and snacks.image's kitty-graphics probe (needs a
# graphics terminal). Ignore those; any other ERROR is fatal.
real_errors="$(grep -nE 'ERROR' "${log}" \
  | grep -vE 'setup did not run|kitty graphics protocol' || true)"
if [ -n "${real_errors}" ]; then
  echo "checkhealth reported ERROR(s):" >&2
  echo "${real_errors}" >&2
  fails=1
fi

# Every in-scope LSP server binary must resolve on PATH (lspconfig cmd names).
required=(
  lua-language-server
  basedpyright-langserver
  nixd
  phpactor
  svelteserver
  vue-language-server
  tailwindcss-language-server
  emmet-language-server
  typescript-language-server
  vscode-html-language-server
  vscode-css-language-server
  vscode-json-language-server
  gopls
  rust-analyzer
  zls
  clangd
  bash-language-server
  yaml-language-server
)
for bin in "${required[@]}"; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "missing LSP on PATH: ${bin}" >&2
    fails=1
  fi
done

# Debug adapters that resolve as PATH binaries must be present (ADR 0140).
# debugpy (python module) and vscode-js-debug (node) have no clean PATH binary
# and are validated by the dap section of :checkhealth above, not here.
adapters=(
  codelldb   # rust + c/cpp (codelldb-bin)
  dlv        # go (delve)
)
for bin in "${adapters[@]}"; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "missing debug adapter on PATH: ${bin}" >&2
    fails=1
  fi
done

# Swift is optional (best-effort); note but never fail on it.
command -v sourcekit-lsp >/dev/null 2>&1 \
  || echo "note: sourcekit-lsp absent (Swift optional)" >&2

if [ "${fails}" -eq 0 ]; then
  echo "nvim acceptance: OK"
fi
exit "${fails}"
