;; -*- no-byte-compile: t; -*-
;;; packages.el
;; Packages the Doom modules do not bring (ADR 0160), pinned like Doom's own so
;; a sync is reproducible. Changing this file needs `doom sync`.

(package! catppuccin-theme :pin "56c3cbe1fee8b04dd7331738df1a0b9bdc6f71bd")

;; Linters eglot's one-server-per-buffer leaves out (nvim-lint's ruff, biome).
(package! flymake-ruff :pin "ef4a6caed72bce77a27bda54ffb30e3fdb0e7d76")
(package! flymake-biome :pin "03fa55d23fdc80fb4bc963cd144da460e7da0220")
(package! kdl-mode :pin "e966ed4b53f8a72b88a016e61bcadec42f317e39")

;; Key parity (nvim wins): avy's `s` replaces evil-snipe; harpoon marks;
;; expand-region at Doom's own pin for C-SPC/BS selection growth.
(package! evil-snipe :disable t)
(package! harpoon :pin "631354f24c0bd56daaf8ab613d695c4f1d57949a")
(package! expand-region :pin "351279272330cae6cecea941b0033a8dd8bcc4e8")
