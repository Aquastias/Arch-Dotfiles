;;; config.el -*- lexical-binding: t; -*-
;; The Emacs Config (ADR 0160): Doom held to the Neovim Config's parity
;; contract. Where Doom's own binding collides with the nvim map, nvim wins.

;; ── Look ──────────────────────────────────────────────────────────────────
;; The font every seeded editor uses (kitty, nvim, VSCodium); a float size is
;; points, matching their 12.
(setq doom-font (font-spec :family "FiraCode Nerd Font" :size 12.0))

;; Static Catppuccin Mocha with nvim's sapphire accent on the same faces nvim
;; overlays (cursor, paren match, search, the completion selection,
;; directories).
(setq catppuccin-flavor 'mocha)
(setq doom-theme 'catppuccin)
(custom-set-faces!
  '(cursor :background "#74c7ec")
  '(show-paren-match :foreground "#74c7ec" :weight bold)
  '(isearch :background "#74c7ec" :foreground "#1e1e2e")
  '(lazy-highlight :background "#74c7ec" :foreground "#1e1e2e")
  '(vertico-current :background "#74c7ec" :foreground "#1e1e2e")
  '(corfu-current :background "#74c7ec" :foreground "#1e1e2e")
  '(dired-directory :foreground "#74c7ec"))

(setq display-line-numbers-type 'relative)

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

(map! :n "]d" #'flymake-goto-next-error
      :n "[d" #'flymake-goto-prev-error
      :leader
      :desc "Organize imports" "c o" #'eglot-code-action-organize-imports)
