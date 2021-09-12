(dolist (exec '("tar"
                "makeinfo"
                ;; imagemagick `convert' used to generated svg badge
                ;; file
                "convert"))
  (unless (executable-find exec)
    (error "Please ensure command '%s' installed in your system"
           exec)))

(defvar eemacs-elpa-admin/var-admin-host
  (file-name-directory
   (expand-file-name
    load-file-name)))

(defvar eemacs-elpa-admin/var-elpa-host
  (file-name-directory
   (replace-regexp-in-string
    "/$" ""
    (expand-file-name
     eemacs-elpa-admin/var-admin-host))))

(defvar eemacs-elpa-admin/var-emacs-repo-host
  (expand-file-name
   "emacs"
   eemacs-elpa-admin/var-elpa-host))

(add-to-list 'load-path eemacs-elpa-admin/var-admin-host)

(provide 'entropy-elpa-admin-vars)
