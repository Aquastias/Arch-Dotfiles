;;; config.el -*- lexical-binding: t; -*-
;; The Emacs Config (ADR 0160): Doom held to the Neovim Config's parity
;; contract. Where Doom's own binding collides with the nvim map, nvim wins.

;; ── Look ──────────────────────────────────────────────────────────────────
;; The font every seeded editor uses (kitty, nvim, VSCodium); a float size is
;; points, matching their 12.
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12.0))
(setq nerd-icons-font-family "FiraCode Nerd Font")   ; Nerd glyphs, no download

;; Like nvim's theme.lua: a static palette, persisted across sessions
;; (Catppuccin Mocha by default); `SPC u N' switches to following Noctalia.
;; rose-pine, nvim's fifth palette, has no maintained Emacs theme.
(defconst +parity-palettes
  '(catppuccin doom-tokyo-night doom-gruvbox doom-nord))
(defvar +parity-follow-noctalia nil
  "Non-nil: load the theme Noctalia renders instead of the static palette.")
(defvar +parity-palette-file (expand-file-name "palette" doom-state-dir))

(defun +parity--saved-palette ()
  "The persisted static palette, or Catppuccin when none (or unknown)."
  (let ((name (and (file-readable-p +parity-palette-file)
                   (intern (string-trim
                            (with-temp-buffer
                              (insert-file-contents +parity-palette-file)
                              (buffer-string)))))))
    (if (memq name +parity-palettes) name 'catppuccin)))

(setq catppuccin-flavor 'mocha)
(setq doom-theme (+parity--saved-palette))

;; nvim's sapphire accent on the faces nvim overlays (cursor, paren match,
;; search, the completion selection, directories) — Catppuccin only, so a
;; followed Noctalia palette keeps its own accent.
(custom-theme-set-faces! 'catppuccin
  '(cursor :background "#74c7ec")
  '(show-paren-match :foreground "#74c7ec" :weight bold)
  '(isearch :background "#74c7ec" :foreground "#1e1e2e")
  '(lazy-highlight :background "#74c7ec" :foreground "#1e1e2e")
  '(vertico-current :background "#74c7ec" :foreground "#1e1e2e")
  '(corfu-current :background "#74c7ec" :foreground "#1e1e2e")
  '(dired-directory :foreground "#74c7ec"))

;; Doom's evil caches the cursor color early in the theme hook (depth -100),
;; before the overlay above applies: re-read it once the faces are set.
(add-hook 'doom-load-theme-hook
          (defun +parity--evil-cursor-color-h ()
            (when (fboundp '+evil-update-cursor-color-h)
              (+evil-update-cursor-color-h)
              (evil-refresh-cursor)))
          100)

(setq display-line-numbers-type 'relative)

;; Noctalia's built-in `emacs' template renders `noctalia' into the first
;; existing config dir — Doom's — and its apply hook runs
;; `emacsclient -e (load-theme 'noctalia t)' on every palette change.
(defvar +parity-noctalia-theme-file
  (expand-file-name "themes/noctalia-theme.el" doom-user-dir))
(add-to-list 'custom-theme-load-path
             (file-name-directory +parity-noctalia-theme-file))

;; That hook must not force Noctalia's theme while follow is off.
(advice-add #'load-theme :before-while
            (defun +parity--noctalia-gate-a (theme &rest _)
              (or (not (eq theme 'noctalia)) +parity-follow-noctalia)))

(defun +parity--apply-theme ()
  "Load Noctalia's theme when following and rendered, else the static one."
  (mapc #'disable-theme custom-enabled-themes)
  (if (and +parity-follow-noctalia
           (file-readable-p +parity-noctalia-theme-file))
      (load-theme 'noctalia t)
    (load-theme (+parity--saved-palette) t)))

(defun +parity/pick-palette ()
  "Pick a static palette and persist it (nvim's SPC u C)."
  (interactive)
  (let ((name (intern (completing-read "Palette: " +parity-palettes nil t))))
    (with-temp-file +parity-palette-file
      (insert (symbol-name name) "\n"))
    (setq +parity-follow-noctalia nil)
    (+parity--apply-theme)))

(defun +parity/toggle-follow-noctalia ()
  "Flip Noctalia follow and re-apply (nvim's SPC u N)."
  (interactive)
  (setq +parity-follow-noctalia (not +parity-follow-noctalia))
  (+parity--apply-theme)
  (message "follow-noctalia = %s" +parity-follow-noctalia))

;; The Arch Wiki's guarded server start: Noctalia's emacsclient reaches the
;; open Emacs, and no login daemon runs.
(require 'server)
(unless (server-running-p)
  (server-start))

;; ── Languages (the Language Registry, via coverage.txt) ───────────────────
;; Every server is the system binary nvim uses (the Fleet Layer); eglot never
;; downloads one.
(set-eglot-client! '(python-mode python-ts-mode)
                   '("basedpyright-langserver" "--stdio"))
(set-eglot-client! '(nix-mode nix-ts-mode) '("nixd"))
(set-eglot-client! '(php-mode php-ts-mode) '("phpactor" "language-server"))
(set-eglot-client! '(js-mode js-ts-mode typescript-mode typescript-ts-mode
                     tsx-ts-mode rjsx-mode)
                   '("typescript-language-server" "--stdio"))
(set-eglot-client! '(json-mode jsonc-mode json-ts-mode)
                   '("vscode-json-language-server" "--stdio"))
(set-eglot-client! '(css-mode css-ts-mode scss-mode less-css-mode)
                   '("vscode-css-language-server" "--stdio"))
(set-eglot-client! '(yaml-mode yaml-ts-mode)
                   '("yaml-language-server" "--stdio"))
(set-eglot-client! '(sh-mode bash-ts-mode) '("bash-language-server" "start"))
(set-eglot-client! '(go-mode go-ts-mode) '("gopls"))
(set-eglot-client! '(rustic-mode rust-mode rust-ts-mode) '("rust-analyzer"))
(set-eglot-client! '(zig-mode zig-ts-mode) '("zls"))
(set-eglot-client! '(c-mode c++-mode c-ts-mode c++-ts-mode) '("clangd"))

;; Doom maps .tsx/.jsx only with +tree-sitter, and Arch packages no TypeScript
;; grammar: a typescript-mode child (and Emacs' js-jsx-mode) carry nvim's
;; typescriptreact/javascriptreact to the server.
(define-derived-mode typescript-tsx-mode typescript-mode "TypeScript[TSX]"
  "`typescript-mode' for .tsx files, so eglot sends typescriptreact.")
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . typescript-tsx-mode))
(add-to-list 'auto-mode-alist '("\\.jsx\\'" . js-jsx-mode))
(set-eglot-client! '((typescript-tsx-mode :language-id "typescriptreact")
                     (js-jsx-mode :language-id "javascriptreact"))
                   '("typescript-language-server" "--stdio"))

;; Doom serves html, .svelte and .vue all in web-mode: pick the server nvim
;; attaches for the file's extension.
(defun +parity-web-server (&rest _)
  (pcase (file-name-extension (or buffer-file-name ""))
    ("svelte" '("svelteserver" "--stdio"))
    ("vue" '("vue-language-server" "--stdio"))
    (_ '("vscode-html-language-server" "--stdio"))))
(set-eglot-client! '(web-mode html-mode mhtml-mode html-ts-mode)
                   #'+parity-web-server)

;; Doom's lua module hands the server Doom-local args (a main.lua that does not
;; exist for the system binary), so this override must land after it.
(after! lua-mode
  (set-eglot-client! '(lua-mode lua-ts-mode) '("lua-language-server")))

;; Format on save with conform's formatter per filetype; Doom's own module
;; choices register earlier, so these win.
(after! apheleia
  (setf (alist-get 'phpcbf apheleia-formatters)
        '("apheleia-phpcs" "--standard=PSR12" "-q" "-"))
  (setf (alist-get 'kdlfmt apheleia-formatters) '("kdlfmt" "format" "-"))
  (dolist (pair '((lua-mode . stylua)
                  (python-mode . ruff)
                  (nix-mode . nixfmt)
                  (php-mode . phpcbf)
                  (js-mode . biome)
                  (typescript-mode . biome)
                  (typescript-tsx-mode . biome)
                  (js-jsx-mode . biome)
                  (rjsx-mode . biome)
                  (json-mode . biome)
                  (jsonc-mode . biome)
                  (css-mode . biome)
                  (scss-mode . prettier-scss)
                  (less-css-mode . prettier-css)
                  (nxml-mode . xmllint)
                  (web-mode . prettier)
                  (yaml-mode . prettier-yaml)
                  (markdown-mode . prettier-markdown)
                  (sh-mode . shfmt)
                  (kdl-mode . kdlfmt)
                  (conf-toml-mode . taplo)
                  (go-mode . gofmt)
                  (rustic-mode . rustfmt)
                  (zig-mode . zig-fmt)
                  (c-mode . clang-format)
                  (c++-mode . clang-format)))
    (setf (alist-get (car pair) apheleia-mode-alist) (cdr pair))))

;; Manual-only, as in nvim (ADR 0151): on save they would rewrite the repo's
;; hand-formatted shell, niri and noctalia files. `SPC c f` still formats.
(setq +format-on-save-disabled-modes
      (append '(sh-mode kdl-mode conf-toml-mode)
              +format-on-save-disabled-modes))

;; Linters beside the server (nvim-lint): ruff for python; biome only inside a
;; project that configures it, so a biome-less repo is not flagged.
(add-hook 'eglot-managed-mode-hook
          (defun +parity-linters-h ()
            (when (derived-mode-p 'python-mode)
              (flymake-ruff-load))
            (when (and (derived-mode-p 'js-mode 'typescript-mode)
                       (or (locate-dominating-file default-directory
                                                   "biome.json")
                           (locate-dominating-file default-directory
                                                   "biome.jsonc")))
              (flymake-biome-load))))


;; ── Org: nvim's orgmode files ─────────────────────────────────────────────
;; Both editors work on the same notes. Set before org loads (Doom defaults
;; org-directory to ~/org otherwise).
(setq org-directory "~/orgfiles/")
(setq org-default-notes-file "~/orgfiles/refile.org")

;; nvim's agenda glob `~/orgfiles/**/*' is recursive; a directory in
;; org-agenda-files is not, so refresh the file list before each agenda.
(defun +parity--org-agenda-files-a (&rest _)
  (when (file-directory-p org-directory)
    (setq org-agenda-files
          (directory-files-recursively org-directory "\\.org\\'"))))
(advice-add #'org-agenda :before #'+parity--org-agenda-files-a)

;; ── Debugging: dape on nvim-dap's adapters (ADR 0140) ─────────────────────
;; dape's own python (debugpy) and go (dlv) configs already launch the system
;; tools. codelldb and js-debug would run downloaded adapters, so these run
;; the Fleet Layer binaries, as nvim-dap does.
(after! dape
  (add-to-list 'dape-configs
               `(codelldb
                 modes (c-mode c-ts-mode c++-mode c++-ts-mode
                        rustic-mode rust-mode rust-ts-mode)
                 command "codelldb"
                 command-args ("--port" :autoport)
                 port :autoport
                 :type "lldb"
                 :request "launch"
                 :cwd dape-cwd
                 :program ,(lambda ()
                             (expand-file-name
                              (read-file-name "Path to executable: ")))))
  (add-to-list 'dape-configs
               '(js-debug-dap
                 modes (js-mode js-ts-mode typescript-mode typescript-ts-mode)
                 command "js-debug-dap"
                 command-args (:autoport)
                 port :autoport
                 :type "pwa-node"
                 :request "launch"
                 :cwd dape-cwd
                 :program dape-buffer-default)))

(defun +parity/debug-continue ()
  "Continue the session, or start one (nvim-dap's SPC d c)."
  (interactive)
  (if (bound-and-true-p dape-active-mode)
      (call-interactively #'dape-continue)
    (call-interactively #'dape)))

;; ── Keys: the nvim map wins (ADR 0160) ────────────────────────────────────
;; Where Doom binds a key differently the nvim binding replaces it; Doom keeps
;; every key nvim leaves free. Mirrors nvim's keymaps.lua and plugin keys.

(setq evil-kill-on-visual-paste nil)    ; nvim's SPC p: paste keeps register
(setq treemacs-position 'right)
(setq vterm-always-compile-module t)    ; build vterm's module, no prompt

(defun +parity/copy-file-path ()
  "Copy the file's ~-abbreviated path (nvim's SPC y p)."
  (interactive)
  (let ((path (abbreviate-file-name (or buffer-file-name default-directory))))
    (kill-new path)
    (message "Copied: %s" path)))

(defun +parity--move-lines (address)
  "Move the visual lines to ADDRESS, reindent, keep them selected."
  (evil-ex-execute (concat "'<,'>m " address))
  (evil-visual-restore)
  (evil-indent (region-beginning) (region-end))
  (evil-visual-restore))

(defun +parity/move-lines-down ()
  (interactive)
  (+parity--move-lines "'>+1"))

(defun +parity/move-lines-up ()
  (interactive)
  (+parity--move-lines "'<-2"))

(defun +parity/replace-word ()
  "Prompt a buffer-wide substitution of the word at point (nvim's SPC r w)."
  (interactive)
  (let ((word (thing-at-point 'word t)))
    (evil-ex (format "%%s/\\<%s\\>/%s/gI" word word))))

(defun +parity/scroll-down-centered ()
  (interactive)
  (evil-scroll-down 0)
  (recenter))

(defun +parity/scroll-up-centered ()
  (interactive)
  (evil-scroll-up 0)
  (recenter))

(defun +parity/make-executable ()
  "chmod +x the visited file (nvim's SPC c x)."
  (interactive)
  (set-file-modes buffer-file-name
                  (logior (file-modes buffer-file-name) #o111))
  (message "Executable: %s" buffer-file-name))

(defun +parity--vterm-run (command)
  "Run COMMAND full-buffer in vterm; the buffer dies with it."
  (require 'vterm)        ; vterm-shell must be special before the let
  (let ((vterm-shell command))
    (vterm (format "*%s*" command))))

(defun +parity/lazygit ()
  (interactive)
  (+parity--vterm-run "lazygit"))

(defun +parity/lazygit-log ()
  (interactive)
  (+parity--vterm-run "lazygit log"))

;; These packages do not autoload the commands bound below, so a key pressed
;; before the package loads would hit a void function (nvim lazy-loads on the
;; key). Autoload each on its bind.
(dolist (package-commands
         '(("dape" dape-breakpoint-toggle dape-breakpoint-expression
            dape-step-in dape-next dape-step-out dape-repl dape-restart
            dape-quit dape-info)
           ("eglot" eglot-code-action-organize-imports
            eglot-code-action-extract eglot-code-actions
            eglot-code-action-inline eglot-inlay-hints-mode)
           ("undo-tree" undo-tree-visualize)
           ("restclient" restclient-copy-curl-command)))
  (dolist (command (cdr package-commands))
    (autoload command (car package-commands) nil t)))

(map! :m "]d" #'flymake-goto-next-error
      :m "[d" #'flymake-goto-prev-error
      :m "]h" #'+vc-gutter/next-hunk
      :m "[h" #'+vc-gutter/previous-hunk
      :m "]t" #'hl-todo-next
      :m "[t" #'hl-todo-previous
      :n "s" #'avy-goto-char-timer
      :n "-" #'dired-jump
      :n "<tab>" #'next-buffer
      :n "<backtab>" #'previous-buffer
      :n "C-h" #'evil-window-left
      :n "C-j" #'evil-window-down
      :n "C-k" #'evil-window-up
      :n "C-l" #'evil-window-right
      :n "C-d" #'+parity/scroll-down-centered
      :n "C-u" #'+parity/scroll-up-centered
      :n "C-e" #'harpoon-toggle-quick-menu
      :n "C-/" #'+vterm/toggle
      :nv "C-SPC" #'er/expand-region
      :v "<backspace>" #'er/contract-region
      :v "J" #'+parity/move-lines-down
      :v "K" #'+parity/move-lines-up
      ;; mini.surround's gs* over evil-surround (shadows Doom's gs easymotion)
      :n "gsa" #'evil-surround-region
      :v "gsa" #'evil-surround-region
      :n "gsd" #'evil-surround-delete
      :n "gsr" #'evil-surround-change)

;; nvim maps C-/ in terminal mode too; vterm sits in insert state.
(map! :map vterm-mode-map :i "C-/" #'+vterm/toggle)

;; Doom binds SPC u (universal-argument) and SPC x (scratch) as commands; nvim
;; uses both as prefixes, so they are cleared first.
(map! :leader
      "u" nil
      "x" nil
      :desc "Write buffer" "w" #'save-buffer
      :desc "Quit window" "q" #'evil-quit
      :desc "Explorer" "e" #'+treemacs/toggle
      :desc "Undo tree" "U" #'undo-tree-visualize
      :desc "Source buffer" "RET" #'eval-buffer
      :desc "Harpoon add" "a" #'harpoon-add-file
      "1" #'harpoon-go-to-1
      "2" #'harpoon-go-to-2
      "3" #'harpoon-go-to-3
      "4" #'harpoon-go-to-4
      "5" #'harpoon-go-to-5
      "6" #'harpoon-go-to-6
      "7" #'harpoon-go-to-7
      "8" #'harpoon-go-to-8
      "9" #'harpoon-go-to-9
      :desc "Delete buffer" "b d" #'kill-current-buffer
      :desc "Copy file path" "y p" #'+parity/copy-file-path
      :desc "Organize imports" "c o" #'eglot-code-action-organize-imports
      :desc "Make executable" "c x" #'+parity/make-executable
      :desc "Find files" "f f" #'+default/find-file-under-here
      :desc "Grep" "f g" #'+default/search-project
      :desc "Buffers" "f b" #'consult-buffer
      :desc "Recent files" "f r" #'consult-recent-file
      :desc "Help pages" "f h" #'consult-info
      :desc "Symbols (document)" "s s" #'consult-imenu
      :desc "Symbols (workspace)" "s S" #'xref-find-apropos
      :desc "Commands" "s c" #'execute-extended-command
      :desc "Keymaps" "s k" #'embark-bindings
      :desc "Search & replace" "s r" #'project-query-replace-regexp
      :desc "Lazygit" "g g" #'+parity/lazygit
      :desc "Lazygit log" "g l" #'+parity/lazygit-log
      :desc "Magit" "g m" #'magit-status
      :desc "Git status" "g s" #'magit-status
      :desc "Diff" "g d" #'magit-diff-unstaged
      :desc "File history" "g h" #'magit-log-buffer-file
      :desc "Repo history" "g H" #'magit-log-current
      :desc "Git branches" "g b" #'magit-branch-checkout
      :desc "Git log" "g L" #'magit-log-all
      :desc "Git browse" "g B" #'+vc/git-link
      :desc "Blame" "g t" #'magit-blame-addition
      :desc "Diagnostics" "x x" #'flymake-show-project-diagnostics
      :desc "Buffer diagnostics" "x X" #'flymake-show-buffer-diagnostics
      :desc "Todo list" "x t" #'hl-todo-occur
      :desc "Symbols" "x s" #'consult-imenu
      :desc "Replace word" "r w" #'+parity/replace-word
      :desc "Extract function" "r e" #'eglot-code-action-extract
      :desc "Extract variable" "r v" #'eglot-code-action-extract
      :desc "Extract to file" "r f" #'eglot-code-actions
      :desc "Inline variable" "r i" #'eglot-code-action-inline
      :desc "Inline function" "r I" #'eglot-code-action-inline
      :desc "REST: send request" "R s" #'restclient-http-send-current
      :desc "REST: copy as curl" "R c" #'restclient-copy-curl-command
      :desc "Debug: toggle breakpoint" "d b" #'dape-breakpoint-toggle
      :desc "Debug: conditional breakpoint" "d B" #'dape-breakpoint-expression
      :desc "Debug: continue/start" "d c" #'+parity/debug-continue
      :desc "Debug: step into" "d i" #'dape-step-in
      :desc "Debug: step over" "d o" #'dape-next
      :desc "Debug: step out" "d O" #'dape-step-out
      :desc "Debug: REPL" "d r" #'dape-repl
      :desc "Debug: run last" "d l" #'dape-restart
      :desc "Debug: terminate" "d t" #'dape-quit
      :desc "Debug: UI" "d u" #'dape-info
      :desc "Inlay hints" "u h" #'eglot-inlay-hints-mode
      :desc "Pick palette" "u C" #'+parity/pick-palette
      :desc "Follow Noctalia" "u N" #'+parity/toggle-follow-noctalia)
