(eval-when-compile
  (require 'browse-url)
  (require 'simple)
  (require 'cl)
  (require 'ido))

;;=================================================================
;; user options
;;=================================================================

(defvar cclookup-db-file "cclookup.db" "cclookup database file")
(defvar cclookup-program "cclookup.py" "cclookup execution file")

;;=================================================================
;; internal variables
;;=================================================================

(defvar cclookup-html-locations '("http://www.cppreference.com/wiki"))
(defvar cclookup-history nil)
(defvar cclookup-cache nil)
(defvar cclookup-return-window-config nil)
(defvar cclookup-temp-buffer-name "*CClookup Completions*")

(defvar cclookup-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1]  'cclookup-mode-lookup-and-leave)
    (define-key map [mouse-2]  'cclookup-mode-lookup)
    (define-key map "\C-m"     'cclookup-mode-lookup-and-leave)
    (define-key map " "        'cclookup-mode-lookup-and-leave)
    (define-key map "f"        'cclookup-mode-lookup)
    (define-key map "q"        'cclookup-mode-quit-window)
    (define-key map "n"        'cclookup-mode-next-line)
    (define-key map "p"        'cclookup-move-prev-line)

    (define-key map "v"        'scroll-down)
    (define-key map "V"        'scroll-up)
    (define-key map "l"        'recenter)
    (define-key map "<"        'beginning-of-buffer)
    (define-key map ">"        'end-of-buffer)
    (define-key map "v"        'scroll-down)
    
    map)
  "Keymap for `cclookup-mode-mode'.")

(put 'cclookup-mode 'mode-class 'special)

(defvar cclookup-completing-read 
  (if (null ido-mode) 'completing-read 'ido-completing-read)
  "Ido support with convenience")

;;=================================================================
;; cclookup mode specific interactive functions
;;=================================================================

(defun cclookup-trim (desc n)
  "Trim desc string to fit into the length, n"

  (if (> (length desc) (- n 2))
      (concat (substring desc 0 (- n 2)) "..")
    desc))

(defun cclookup-mode ()
  "Major mode for output from \\[cclookup-lookup]."
  (interactive)
  
  (kill-all-local-variables)
  (use-local-map cclookup-mode-map)
  (setq major-mode 'cclookup-mode)
  (setq mode-name "cclookup")
  (setq buffer-read-only t))

(defun cclookup-move-prev-line ()
  "Move to previous entry"
  (interactive)
  
  (when (< 3 (line-number-at-pos))
    (call-interactively 'previous-line)))

(defun cclookup-mode-next-line ()
  "Move to next entry"
  (interactive)
  
  (when (< (line-number-at-pos)
           (- (line-number-at-pos (point-max)) 1))
    (call-interactively 'next-line)))

(defun cclookup-mode-lookup-and-leave ()
  "Lookup the current line in a browser and leave the completions window."
  (interactive)
  
  (call-interactively 'cclookup-mode-lookup)
  (cclookup-mode-quit-window))

(defun cclookup-mode-lookup ()
  "Lookup the current line in a browser."
  (interactive)
  
  (let ((url (get-text-property (point) 'cclookup-target-url)))
    (if url
        (progn
          (beginning-of-line)
          (message "Browsing: \"%s\"" url)
          (browse-url (cclookup-url url)))
      (error "No URL on this line"))))

(defun cclookup-mode-quit-window ()
  "Leave the completions window."
  (interactive)

  (set-window-configuration cclookup-return-window-config))

(defun cclookup-url (url)
  "Change proper url form"

  (let ((default-directory (file-name-directory cclookup-db-file)))
    (concat "file://" (expand-file-name url))))

;;=================================================================
;; execute cclookup
;;=================================================================

(defun cclookup-exec-get-cache ()
  "Run a cclookup process and get a list of cache (db key)"

  (split-string
   (with-output-to-string
     (call-process cclookup-program nil standard-output nil 
           "-d" (expand-file-name cclookup-db-file)
           "-c"))))

(defun cclookup-exec-lookup (search-term)
  "Runs a cclookup process and returns a list of (term, url) pairs."

  (mapcar 
   (lambda (x) (split-string x "\t"))
   (split-string
     (with-output-to-string
         (call-process cclookup-program nil standard-output nil 
                       "-d" (expand-file-name cclookup-db-file) 
               "-l" search-term))
     "\n" t)))

;;=================================================================
;; interactive user interfaces
;;=================================================================

;;;###autoload
(defun cclookup-lookup (search-term)
  "Lookup SEARCH-TERM in the C++ Reference indexes."
  (interactive
   (list 
    (let ((initial (thing-at-point 'word)))
      (funcall cclookup-completing-read
               "Lookup C++ Refernece for: "
               (if cclookup-cache 
                   cclookup-cache 
                 (setq cclookup-cache (cclookup-exec-get-cache)))
               nil nil initial 'cclookup-history))
    ))

  (let ((matches (cclookup-exec-lookup search-term)))
    (cond

      ;; 0. No results.
      ((eq matches nil)
       (message "No matches for \"%s\"." search-term))

      ;; 1. A single result.
      ((= (length matches) 1)  
       ;; Point the browser at the unique result and get rid of the buffer
       (let ((data (car matches)))
         (message "Browsing: \"%s\"" (car data))
         (browse-url (cclookup-url (cadr data)))))

      ;; N. Multiple results.
      (t
       ;; Decorate the temporary buffer lines with appropriate properties for
       ;; selection.
       (let* ((cur-window-conf (current-window-configuration))
              (tmpbuf (get-buffer-create cclookup-temp-buffer-name))
              (index 0))
    
         (display-buffer tmpbuf)
         (pop-to-buffer tmpbuf)

         (setq buffer-read-only nil)
         (erase-buffer)

         ;; Insert the text in the buffer
         (insert (format "C++ Reference matches for %s:\n\n" search-term))
         (dolist (x matches)

            (let* ((key  (car x))
                   (addr (cadr x))
                   (cat  (caddr x))
                   (desc (cadddr x)))

              (incf index)
              (insert (format " %03d) %-15s %-50s [%15s]"
                  index 
                  (cclookup-trim key  15)
                  (cclookup-trim desc 50)
                  (cclookup-trim cat  15)))

              (put-text-property (line-beginning-position)
                                 (line-end-position)
                                 'cclookup-target-url
                                 addr))
            (insert "\n"))

         ;; goto first entry
         (goto-line 3)

         ;; turn mode on
         (cclookup-mode)

         ;; highlighting
         (font-lock-add-keywords nil `((,(format "\\(%s\\|%s\\|%s\\)" 
                         search-term 
                         (upcase search-term)
                         (upcase-initials search-term))
                                         1
                                         font-lock-function-name-face prepend)))

         (font-lock-add-keywords nil '(("\\<\\(stl\\)"
                                         1
                                         font-lock-constant-face prepend)))

         (font-lock-add-keywords nil '(("\\<\\(returns?\\)"
                                         1
                                         font-lock-constant-face prepend)))         

         (font-lock-add-keywords nil '(("\\<[^/]+/\\([^\]]+\\)"
                                         1
                                         font-lock-warning-face prepend)))

         ;; store window configuration
         (set (make-local-variable 'cclookup-return-window-config) cur-window-conf)

         ;; make fit to screen
         (shrink-window-if-larger-than-buffer (get-buffer-window tmpbuf)))))))

;;;###autoload
(defun cclookup-update (src)
  "Run cclookup-update and create the database at `cclookup-db-file'."
  (interactive 
   (list (funcall cclookup-completing-read
                  "C++ Reference Source: "
                  cclookup-html-locations)))
  
  ;; cclookup.py -d /home/myuser/.cclookup/cclookup.db -l <URL>
  (call-process cclookup-program nil standard-output nil 
                       "-d" (expand-file-name cclookup-db-file) 
               "-l" src))

(provide 'cclookup)
;;; cclookup.el ends here
