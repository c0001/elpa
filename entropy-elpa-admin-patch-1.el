(require 'entropy-elpa-admin-vars)
(defun __adv/around/elpaa--make-one-tarball/for-reset-emacs-repo-head
    (orig-func &rest orig-args)
  (prog1
      (apply orig-func orig-args)
    ;; reset emacs repo head upto upstream prepare for next core
    ;; release
    (let ((pkg-spec (caddr orig-args)))
      (when (plist-get (cdr pkg-spec) :core)
        (let ((default-directory eemacs-elpa-admin/var-emacs-repo-host))
          (with-temp-buffer
            ;; Run it within the true-filename directory holding the mainfile,
            ;; so that for :core packages we properly affect the Emacs tree.
            (elpaa--call t "git" "reset" "--merge" "entropy-master")
            (message
             ">>>>>> Reset emacs repo head to entropy-master"
             )))))))
(advice-add
 'elpaa--make-one-tarball
 :around
 #'__adv/around/elpaa--make-one-tarball/for-reset-emacs-repo-head)

(defun entropy/elpaa--patch-elpaa--make-one-package
    (orig-func &rest orig-args)
  (let ((pkgname (caar orig-args)))
    (cond
     ((string-match-p "^org" pkgname)
      (message "Skip for %s" pkgname))
     (t
      (apply orig-func orig-args)))))
(advice-add 'elpaa--make-one-package
            :around #'entropy/elpaa--patch-elpaa--make-one-package)

(defun entropy/elpaa--patch-elpaa--copyright-check
    (orig-func &rest orig-args)
  "Ignore copyright check while building tarball since its
unnecessary while local building for eemacs. "
  (ignore-errors (apply orig-func orig-args)))
(advice-add 'elpaa--copyright-check
            :around
            #'entropy/elpaa--patch-elpaa--copyright-check)

(provide 'entropy-elpa-admin-patch-1)
