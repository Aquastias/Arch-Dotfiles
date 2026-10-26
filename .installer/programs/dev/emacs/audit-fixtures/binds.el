;;; binds.el --- Feature Audit bind judge for emacs -*- lexical-binding: t; -*-
;; Loaded into the user's Doom (a throwaway daemon) by audit.sh (ADR 0152,
;; 0160). Reads a TSV plan — states, chord, wanted command, check id — and
;; writes one `PASS|FAIL <id> <message>' line per bind: the chord's
;; key-binding, asked in a buffer in that evil state, must be the command
;; the shipped config binds.

(defun fa-emacs--state-buffer (states)
  "A scratch buffer in STATES' evil state (visual for `v…', else normal —
normal sees motion binds and the SPC leader too)."
  (let ((buffer (generate-new-buffer " *fa-emacs-probe*")))
    (with-current-buffer buffer
      (insert "alpha beta gamma\ndelta epsilon zeta\n")
      (goto-char (point-min))
      (evil-local-mode 1)
      (evil-normal-state)
      (when (string-prefix-p "v" states)
        (evil-visual-char)
        (forward-char 3)))
    buffer))

(defun fa-emacs--resolve (states chord)
  "The command CHORD runs in STATES, unremapped, as a string."
  (let ((buffer (fa-emacs--state-buffer states)))
    (unwind-protect
        (with-current-buffer buffer
          (format "%s" (key-binding (kbd chord) nil t)))
      (kill-buffer buffer))))

(defun fa-emacs-binds (plan-file out-file)
  "Judge every bind in PLAN-FILE, writing the results to OUT-FILE."
  (with-temp-file out-file
    (dolist (line (split-string
                   (with-temp-buffer
                     (insert-file-contents plan-file)
                     (buffer-string))
                   "\n" t))
      (pcase-let* ((`(,states ,chord ,want ,id) (split-string line "\t"))
                   (got (condition-case err
                            (fa-emacs--resolve states chord)
                          (error (format "error: %s"
                                         (error-message-string err))))))
        (insert (if (equal got want)
                    (format "PASS %s %s runs %s\n" id chord want)
                  (format "FAIL %s %s runs %s, want %s\n"
                          id chord got want)))))))
