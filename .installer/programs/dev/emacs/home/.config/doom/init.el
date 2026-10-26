;;; init.el -*- lexical-binding: t; -*-
;; The Emacs Config's Doom modules (ADR 0160): the opt-in parity twin of the
;; Neovim Config. Changing this block needs `doom sync`. The :lang set follows
;; the Language Registry through coverage.txt.

(doom! :completion
       (corfu +orderless)
       vertico

       :ui
       doom
       hl-todo
       ligatures
       modeline
       ophints
       treemacs
       (popup +defaults)
       (vc-gutter +pretty)
       vi-tilde-fringe
       workspaces

       :editor
       (evil +everywhere)
       fold
       (format +onsave)        ; no +lsp: conform's formatters, not the server's
       snippets

       :emacs
       dired
       electric
       (undo +tree)
       vc

       :term
       vterm

       :checkers
       (syntax +flymake)

       :tools
       lookup
       (lsp +eglot)            ; servers from PATH only, never downloaded
       magit

       :lang
       (cc +lsp)
       data
       emacs-lisp
       (go +lsp)
       (javascript +lsp)
       (json +lsp)
       (lua +lsp)
       markdown
       (nix +lsp)
       (php +lsp)
       org
       (python +lsp)
       rest
       (rust +lsp)
       (sh +lsp)
       (web +lsp)
       (yaml +lsp)
       (zig +lsp)

       :config
       (default +bindings +smartparens))
