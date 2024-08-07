;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil . ((tab-width . 8)
         (sentence-end-double-space . t)
         (fill-column . 70)
         (bug-reference-url-format . "https://debbugs.gnu.org/%s")))
 (change-log-mode . ((add-log-time-zone-rule . t)
                     (fill-column . 74)
                     (mode . bug-reference)))
 (css-mode . ((css-indent-offset . 2)))
 (diff-mode . ((mode . whitespace)))
 (lisp-data-mode . ((indent-tabs-mode . nil)
                    (electric-quote-comment . nil)
                    (electric-quote-string . nil)
                    (mode . bug-reference-prog)))
 (log-edit-mode . ((log-edit-font-lock-gnu-style . t)
                   (log-edit-setup-add-author . t))))
