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
