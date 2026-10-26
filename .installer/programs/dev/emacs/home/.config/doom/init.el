;;; init.el -*- lexical-binding: t; -*-
;; The Emacs Config's Doom modules (ADR 0160): the opt-in parity twin of the
;; Neovim Config. Changing this block needs `doom sync`.

(doom! :completion
       (corfu +orderless)
       vertico

       :ui
       doom
       hl-todo
       ligatures
       modeline
       ophints
       (popup +defaults)
       (vc-gutter +pretty)
       vi-tilde-fringe
       workspaces

       :editor
       (evil +everywhere)
       fold
       snippets

       :emacs
       dired
       electric
       undo
       vc

       :tools
       lookup

       :lang
       emacs-lisp

       :config
       (default +bindings +smartparens))
