#!/usr/bin/env bats
# dev/emacs program — the Emacs Config's key, theme, org, REST and debugging
# parity with the Neovim Config (ADR 0160). Where Doom's own binding collides
# with the nvim map, nvim wins. Helpers: emacs-program-helpers.bash.

load emacs-program-helpers

# ── key parity with the Neovim Config: nvim wins (ADR 0160) ──────────────────

@test "motions: s is avy with evil-snipe off; gs* is surround" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! evil-snipe :disable t)'
  bound s avy-goto-char-timer
  bound gsa evil-surround-region
  bound gsd evil-surround-delete
  bound gsr evil-surround-change
}

@test "files: - is dired-jump, SPC e toggles treemacs on the right" {
  module_enabled 'treemacs'
  bound - dired-jump
  bound e +treemacs/toggle
  elisp "$DOOMDIR/config.el" | grep -qF "(setq treemacs-position 'right)"
}

@test "core keys match nvim's keymaps.lua" {
  bound w save-buffer
  bound q evil-quit
  bound '<tab>' next-buffer
  bound '<backtab>' previous-buffer
  bound C-h evil-window-left
  bound C-j evil-window-down
  bound C-k evil-window-up
  bound C-l evil-window-right
  bound 'b d' kill-current-buffer
  bound 'y p' +parity/copy-file-path
  bound J +parity/move-lines-down
  bound K +parity/move-lines-up
  # nvim's SPC p dodges Vim's register-clobbering visual paste; evil can
  # simply not clobber, which leaves Doom's SPC p project prefix intact.
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(setq evil-kill-on-visual-paste nil)'
  bound 'r w' +parity/replace-word
  bound C-SPC er/expand-region
  bound '<backspace>' er/contract-region
  bound C-d +parity/scroll-down-centered
  bound C-u +parity/scroll-up-centered
  bound 'c x' +parity/make-executable
  bound RET eval-buffer
}

@test "find/search keys match nvim's snacks + grug-far maps" {
  bound 'f f' +default/find-file-under-here
  bound 'f g' +default/search-project
  bound 'f b' consult-buffer
  bound 'f r' consult-recent-file
  bound 'f h' consult-info
  bound 's s' consult-imenu
  bound 's S' xref-find-apropos
  bound 's c' execute-extended-command
  bound 's k' embark-bindings
  bound 's r' project-query-replace-regexp
}

@test "git keys: lazygit on SPC g g, magit one key away, hunks, history" {
  module_enabled 'magit'
  bound 'g g' +parity/lazygit
  bound 'g l' +parity/lazygit-log
  bound 'g m' magit-status
  bound 'g s' magit-status
  bound 'g d' magit-diff-unstaged
  bound 'g h' magit-log-buffer-file
  bound 'g H' magit-log-current
  bound 'g b' magit-branch-checkout
  bound 'g L' magit-log-all
  bound 'g B' +vc/git-link
  bound 'g t' magit-blame-addition
  bound ']h' +vc-gutter/next-hunk
  bound '[h' +vc-gutter/previous-hunk
}

@test "diagnostics, todo and refactor keys where eglot backs them" {
  bound 'x x' flymake-show-project-diagnostics
  bound 'x X' flymake-show-buffer-diagnostics
  bound 'x t' hl-todo-occur
  bound 'x s' consult-imenu
  bound ']t' hl-todo-next
  bound '[t' hl-todo-previous
  bound 'r e' eglot-code-action-extract
  bound 'r v' eglot-code-action-extract
  bound 'r f' eglot-code-actions
  bound 'r i' eglot-code-action-inline
  bound 'r I' eglot-code-action-inline
  bound 'u h' eglot-inlay-hints-mode
}

@test "harpoon, undo tree and the terminal toggle" {
  elisp "$DOOMDIR/packages.el" | grep -qF '(package! harpoon '
  module_enabled '(undo +tree)'
  module_enabled 'vterm'
  bound a harpoon-add-file
  bound C-e harpoon-toggle-quick-menu
  local i
  for i in 1 2 3 4 5 6 7 8 9; do bound "$i" "harpoon-go-to-$i"; done
  bound U undo-tree-visualize   # +tree installs undo-tree, not vundo
  bound C-/ +vterm/toggle
  # nvim maps it in terminal mode too: vterm sits in insert state
  elisp "$DOOMDIR/config.el" | grep -qE ":map vterm-mode-map :i \"C-/\""
  elisp "$DOOMDIR/config.el" | grep -qF '(setq vterm-always-compile-module t)'
}

@test "install.sh adds vterm's build deps (Doom's vterm README)" {
  # join backslash-continued lines, so a package on line two still counts
  local installs
  installs="$(awk '/\\$/ { sub(/\\$/, ""); printf "%s", $0; next } 1' \
    "$INSTALL")"
  grep -qE -- '--needed .*cmake' <<<"$installs"
  grep -qE -- '--needed .*libvterm' <<<"$installs"
}

# ── theme: static by default, Noctalia follow on SPC u N (ADR 0160) ──────────

@test "the static palettes are nvim's that Emacs has; catppuccin default" {
  # rose-pine has no maintained Emacs theme (ADR 0160 gap).
  elisp "$DOOMDIR/config.el" | grep -qF \
    "'(catppuccin doom-tokyo-night doom-gruvbox doom-nord))"
  elisp "$DOOMDIR/config.el" | grep -qF '(defvar +parity-follow-noctalia nil'
}

@test "SPC u C picks a palette, SPC u N toggles Noctalia follow" {
  bound 'u C' +parity/pick-palette
  bound 'u N' +parity/toggle-follow-noctalia
}

@test "the chosen palette persists in Doom's state dir" {
  elisp "$DOOMDIR/config.el" | grep -qF 'doom-state-dir'
}

@test "follow loads Noctalia's emacs template output from the Doom dir" {
  elisp "$DOOMDIR/config.el" | grep -qF '"themes/noctalia-theme.el"'
  grep -qE '^[[:space:]]*"emacs",' "$REPO/.config/noctalia/config.toml"
}

@test "Noctalia's apply hook cannot force its theme while follow is off" {
  elisp "$DOOMDIR/config.el" | grep -qE "advice-add #'load-theme :before-while"
}

@test "a server runs so Noctalia's emacsclient hook reaches open Emacs" {
  # The Arch Wiki's guarded server start; no emacs.service daemon.
  elisp "$DOOMDIR/config.el" | grep -qF '(unless (server-running-p)'
  elisp "$DOOMDIR/config.el" | grep -qF '(server-start)'
  ! grep -rq 'emacs.service' "$PROG"
}

@test "sapphire overlays Catppuccin only, never Noctalia's own accent" {
  elisp "$DOOMDIR/config.el" | grep -qF "(custom-theme-set-faces! 'catppuccin"
}

@test "Noctalia's rendered theme is git-ignored (seed-only, ADR 0104)" {
  git -C "$REPO" check-ignore -q \
    .installer/programs/dev/emacs/home/.config/doom/themes/noctalia-theme.el
}

# ── org and REST (ADR 0160) ──────────────────────────────────────────────────

ORGMODE_REL=.installer/programs/dev/nvim/home/.config/nvim/lua/plugins
ORGMODE_REL=$ORGMODE_REL/orgmode.lua

@test "org shares nvim's org files: directory, agenda tree, refile file" {
  module_enabled 'org'
  # nvim's orgmode paths, read from its config (the source of truth).
  grep -qF 'org_agenda_files = "~/orgfiles/**/*"' "$REPO/$ORGMODE_REL"
  grep -qF 'org_default_notes_file = "~/orgfiles/refile.org"' \
    "$REPO/$ORGMODE_REL"
  elisp "$DOOMDIR/config.el" | grep -qF '(setq org-directory "~/orgfiles/")'
  elisp "$DOOMDIR/config.el" \
    | grep -qF '(setq org-default-notes-file "~/orgfiles/refile.org")'
  # `**/*` is recursive; org-agenda-files directories are not.
  elisp "$DOOMDIR/config.el" | grep -qF 'directory-files-recursively'
}

@test "REST: restclient sends and copies as curl on SPC R s / SPC R c" {
  module_enabled 'rest'
  bound 'R s' restclient-http-send-current
  bound 'R c' restclient-copy-curl-command
}

# ── debugging: dape on nvim-dap's system adapters (ADR 0140, 0160) ───────────

@test "dape is declared, Doom's dap-mode debugger module is not" {
  elisp "$DOOMDIR/packages.el" | grep -A1 -F '(package! dape ' \
    | grep -qE ':pin "[0-9a-f]{40}"'
  ! module_enabled 'debugger'
}

@test "dape adapters are nvim-dap's system binaries, none downloaded" {
  # codelldb (rust/c/cpp) and js-debug-dap (js/ts): the Fleet Layer's
  # codelldb-bin and vscode-js-debug-bin, as nvim-dap launches them.
  elisp "$DOOMDIR/config.el" | grep -qF 'command "codelldb"'
  elisp "$DOOMDIR/config.el" | grep -qF 'command "js-debug-dap"'
  grep -q '"codelldb-bin"' "$REPO/$FLEET_REL"
  grep -q '"vscode-js-debug-bin"' "$REPO/$FLEET_REL"
  # dape's own python (debugpy) and go (dlv) configs already use the
  # system python-debugpy and delve.
  grep -q '"python-debugpy"' "$REPO/$FLEET_REL"
  grep -q '"delve"' "$REPO/$FLEET_REL"
  ! elisp "$DOOMDIR/config.el" | grep -q 'dape-adapter-dir'
}

@test "SPC d keys match nvim-dap's" {
  bound 'd b' dape-breakpoint-toggle
  bound 'd B' dape-breakpoint-expression
  bound 'd c' +parity/debug-continue
  bound 'd i' dape-step-in
  bound 'd o' dape-next
  bound 'd O' dape-step-out
  bound 'd r' dape-repl
  bound 'd l' dape-restart
  bound 'd t' dape-quit
  bound 'd u' dape-info
}

# A bind to a command its package does not autoload is void until that
# package loads (VM probe: SPC d b before any session). nvim lazy-loads on
# the key; these autoload on it.
@test "binds into lazily loaded packages autoload their command" {
  local block
  block="$(elisp "$DOOMDIR/config.el" \
    | awk '/^\(dolist \(package-commands/,/\(autoload command/')"
  local command
  for command in dape-breakpoint-toggle dape-breakpoint-expression \
    dape-step-in dape-next dape-step-out dape-repl dape-restart dape-quit \
    dape-info eglot-code-action-organize-imports eglot-code-action-extract \
    eglot-code-actions eglot-code-action-inline eglot-inlay-hints-mode \
    undo-tree-visualize restclient-copy-curl-command; do
    grep -qw -- "$command" <<<"$block" \
      || { echo "not autoloaded: $command"; false; }
  done
}
