;;; emacs-keys.el — parser fixture: Doom map! forms (binds-emacs.awk).
(setq unrelated "\"x\" #'not-a-bind")
(map! :m "]d" #'flymake-goto-next-error
      :n "s" #'avy-goto-char-timer
      :nv "C-SPC" #'er/expand-region
      ;; a comment "q" #'ignored
      :v "J" #'+parity/move-lines-down)

(map! :leader
      "u" nil
      :desc "Write buffer" "w" #'save-buffer
      "1" #'harpoon-go-to-1
      :desc "Lazygit" "g g" #'+parity/lazygit)
