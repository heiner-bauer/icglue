
;;; icglue-mode.el --- minimal mode for ICGlue files


;;; Commentary:

;; add to load-path and use require
;; add the following to your emacs config for verilog syntax highlighting in code sections:
;; (add-hook 'icglue-mode-hook
;;          (lambda () (add-hook 'after-save-hook 'icglue-fontify-code-sections nil 'local)))

;; possible extensions: even better highlighting, auto-indent, menu, completion


;;; Code:
(defconst icglue-keywords
  '(
    ("#.*"                                                      . font-lock-comment-face)
    ("^ *M \\|^ *P \\|^ *S \\|^ *C \\|^ *R \\|^ *SR \\|^ *RT "  . font-lock-type-face)
    ("-+>\\|<-+>\\|<-+"                                         . font-lock-function-name-face)
    ;; proc S
    ("-w\\(idth\\)?"                                            . font-lock-keyword-face)
    ;; -value (proc S) and -verbatim (proc C)
    ("-v\\(alue\\|erbatim\\)?"                                  . font-lock-keyword-face)
    ("-d\\(imension\\)?"                                        . font-lock-keyword-face)
    ("-b\\(idir\\(ectional\\)?\\)?"                             . font-lock-keyword-face)
    ;; -pin (proc S) and -protected (proc R)
    ("-p\\(in\\|rot\\(ect\\(ed\\)?\\)?\\)?"                     . font-lock-keyword-face)
    ;; proc M
    ("-unit"                                                    . font-lock-keyword-face)
    ("-tree"                                                    . font-lock-keyword-face)
    ;; proc C
    ("-noa\\(dapt\\)?"                                          . font-lock-keyword-face)
    ;; -adapt -align -adapt-selectively -addr
    ("-a\\(dapt\\|l\\(ign\\)?\\|s\\|dapt-selectively\\|ddr\\)?" . font-lock-keyword-face)
    ("-s\\(ubst\\)?"                                            . font-lock-keyword-face)
    ("-nos\\(ubst\\)?"                                          . font-lock-keyword-face)
    ("-e\\(val\\(uate\\)?\\)?"                                  . font-lock-keyword-face)
    ("-noi\\(ndentfix\\)?"                                      . font-lock-keyword-face)
    ;; proc R (-evaluate and -nosubst shared with proc C)
    ("-\\(rf\\|regf\\(ile\\)?\\)"                               . font-lock-keyword-face)
    ("@"                                                        . font-lock-keyword-face)
    ("-handshake"                                               . font-lock-keyword-face)))

(defvar icglue-mode-syntax-table
  (let ((table (make-syntax-table)))
    ;; Populate the syntax TABLE.
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?` "w" table)  ; ` is part of definition symbols in Verilog
    (modify-syntax-entry ?_ "w" table)
    (modify-syntax-entry ?\' "." table)
    ;; comment sytax
    ;; (modify-syntax-entry ?\# ". 12b" table)

    ;; (modify-syntax-entry ?\# ". 14c" table)

    (modify-syntax-entry ?# "< 14b" table)  ; # single-line start

    ;; Set up TABLE to handle block and line style comments.
    (modify-syntax-entry ?/  ". 14b" table)
    (modify-syntax-entry ?*  ". 23"   table)
    (modify-syntax-entry ?\n "> b"  table)
    (modify-syntax-entry ?\^M "> b"   table)
  table)
  "Syntax table used in ICGlue mode buffers.")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: fix '#' comment highlighting from TCL applied *after* verilog highlighting
;; TODO: figure out how to avoid 'modified' buffer state after highlighting verilog syntax
;; Graciously inspired by http://emacs.stackexchange.com/a/5408/227
;; Run Verilog mode for syntax highlighting in temporary buffer
(defun icglue-fontify-verilog (text)
  "Add `font-lock-face' properties to Verilog text. Return a fontified copy of TEXT."
  (with-temp-buffer
    (erase-buffer)
    (insert text)
    ;; Run Verilog mode without any hooks
    (delay-mode-hooks
      (verilog-mode)
      (font-lock-mode))
    (font-lock-ensure)
    ;; Convert `face' to `font-lock-face' to play nicely with font lock
    (goto-char (point-min))
    (while (not (eobp))
      (let ((pos (point)))
        (goto-char (next-single-property-change pos 'face nil (point-max)))
        (put-text-property pos (point) 'font-lock-face
                           (get-text-property pos 'face))))
    (buffer-string)))

(defun icglue-fontify-verilog-section (section)
  "Replace text of SECTION with text fontified by verilog-mode."
  (interactive)
  (when section
    (setq start (nth 0 section))
    (setq end   (nth 1 section))
    (setq text (buffer-substring-no-properties start end))
    (setq fontified-text (icglue-fontify-verilog text))
    (delete-region start end)
    (goto-char start)
    (insert fontified-text)))

(defun icglue-next-code-section ()
  "Return the start / end pair of the next ICGlue code section after point."
  (interactive)
  (when (re-search-forward "^ ?C.+{" nil t)
    (backward-char 1)
    (forward-sexp) ;; move point to the closing '}' of the code section
    (let ((start (match-end 0))
          (end (point)))
      (list start end))))

(defun icglue-print-next-code-section ()
  (interactive)
  (let ((pair (icglue-next-code-section)))
    (if pair
        (message (format "start:%d end:%d" (nth 0 pair) (nth 1 pair))))))

(defun icglue-code-sections ()
  "Return a list with start / end pairs for all ICGlue code sections in the buffer."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((current-section (icglue-next-code-section))
          (section-list ()))
      (while current-section
        (setq section-list (append (list current-section) section-list))
        (setq current-section (icglue-next-code-section)))
      section-list)))

(defun icglue-fontify-code-sections ()
  "Fontify Verilog code sections in the current buffer."
  (interactive)
  (save-excursion
  (let ((code-sections (icglue-code-sections)))
    (while code-sections
      (setq current-section (pop code-sections))
      (icglue-fontify-verilog-section current-section)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require 'compile)

(defvar icglue-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\C-cc" 'compile)
    map)
  "Keymap used in ICGlue mode.")


(define-derived-mode icglue-mode tcl-mode
  (font-lock-add-keywords nil icglue-keywords)
  (setq mode-name "ICGlue Mode")

  (set (make-local-variable 'comment-multi-line) nil)

  (set (make-local-variable 'comment-start) "#")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-start-skip)
       (concat (regexp-quote comment-start) "+\\s *"))
  (set (make-local-variable 'compile-command) (format "icglue %s " (file-name-nondirectory buffer-file-name)))
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map icglue-mode-map)
    )
  (set-syntax-table icglue-mode-syntax-table)
  )

(provide 'icglue-mode)

;;; icglue-mode.el ends here
