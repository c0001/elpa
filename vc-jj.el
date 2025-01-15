;;; vc-jj.el --- A vc.el backend for Jujutsu VCS  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  Wojciech Siewierski

;; Author: Wojciech Siewierski

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A backend for vc.el to handle Jujutsu repositories.

;;; Code:

(require 'seq)

(autoload 'vc-switches "vc")

(add-to-list 'vc-handled-backends 'JJ)

(defun vc-jj-revision-granularity () 'repository)
(defun vc-jj-checkout-model (_files) 'implicit)
(defun vc-jj-update-on-retrieve-tag () nil)


(defun vc-jj--file-tracked (file)
  (with-temp-buffer
    (and (= 0 (call-process "jj" nil t nil "file" "list" "--" file))
         (not (= (point-min) (point-max))))))

(defun vc-jj--file-modified (file)
  (with-temp-buffer
    (and (= 0 (call-process "jj" nil t nil "diff" "--name-only" "--" file))
         (not (= (point-min) (point-max))))))


;;;###autoload (defun vc-jj-registered (file)
;;;###autoload   "Return non-nil if FILE is registered with jj."
;;;###autoload   (if (and (vc-find-root file ".jj")   ; Short cut.
;;;###autoload            (executable-find "jj"))
;;;###autoload       (progn
;;;###autoload         (load "vc-jj" nil t)
;;;###autoload         (vc-jj-registered file))))

(defun vc-jj-registered (file)
  (when (executable-find "jj")
    (unless (not (file-exists-p default-directory))
      (with-demoted-errors "Error: %S"
        (when-let ((root (vc-jj-root file)))
          (let ((relative (file-relative-name file root))
                (default-directory root))
            (vc-jj--file-tracked relative)))))))

(defun vc-jj-state (file)
  (when-let ((root (vc-jj-root file)))
    (let ((relative (file-relative-name file root))
          (default-directory root))
      (cond
       ((vc-jj--file-modified relative)
        'edited)
       ((vc-jj--file-tracked relative)
        'up-to-date)))))

(defun vc-jj-dir-status-files (dir _files update-function)
  ;; TODO: should be async!
  (let ((files (apply #'process-lines "jj" "file" "list" "--" dir))
        (modified (apply #'process-lines "jj" "diff" "--name-only" "--" dir)))
    (let ((result
           (mapcar (lambda (file)
                     (let ((vc-state (if (member file modified)
                                         'edited
                                       'up-to-date)))
                       (list file vc-state))))))
      (funcall update-function result nil))))

(defun vc-jj-dir-extra-headers (dir)
  "Return extra headers for DIR.
Always add the first line of the description, the change ID, and
the git commit ID of the current change.  If the current change
is named by one or more bookmarks, also add a Bookmarks header.
If the current change is conflicted, divergent or hidden, also
add a Status header.  (We do not check for emptiness of the
current change since the user can see that via the list of files
below the headers anyway.)"
  (let* ((default-directory dir)
         (info (process-lines "jj" "log" "--no-graph" "-r" "@" "-T"
                              "concat(
self.change_id().short(), \"\\n\",
self.change_id().shortest(), \"\\n\",
self.commit_id().short(), \"\\n\",
self.commit_id().shortest(), \"\\n\",
description.first_line(), \"\\n\",
bookmarks.join(\",\"), \"\\n\",
self.conflict(), \"\\n\",
self.divergent(), \"\\n\",
self.hidden(), \"\\n\"
)")))
    (seq-let [change-id change-id-short commit-id commit-id-short
                        description bookmarks conflict divergent hidden]
        info
      (cl-flet ((fmt (key value &optional prefix)
                  (concat
                   (propertize (format "% -11s: " key) 'face 'vc-dir-header)
                   ;; there is no header value emphasis face, so we
                   ;; use vc-dir-status-up-to-date for the prefix.
                   (when prefix (propertize prefix 'face 'vc-dir-status-up-to-date))
                   (propertize value 'face 'vc-dir-header-value))))
        (let ((status (concat
                       (when (string= conflict "true") "(conflict)")
                       (when (string= divergent "true") "(divergent)")
                       (when (string= hidden "true") "(hidden)")))
              (change-id-suffix (substring change-id (length change-id-short)))
              (commit-id-suffix (substring commit-id (length commit-id-short))))
          (string-join (seq-remove
                        #'null
                        (list
                         (fmt "Description" (if (string= description "") "(no description set)" description))
                         (fmt "Change ID" change-id-suffix change-id-short)
                         (fmt "Commit" commit-id-suffix commit-id-short)
                         (unless (string= bookmarks "") (fmt "Bookmarks" bookmarks))
                         (unless (string= status "")
                           ;; open-code this line instead of adding a face parameter to `fmt'
                           (concat
                            (propertize (format "% -11s: " "Status") 'face 'vc-dir-header)
                            (propertize status 'face 'vc-dir-status-warning)))))
                       "\n"))))))

(defun vc-jj-working-revision (file)
  (when-let ((root (vc-jj-root file)))
    (let ((relative (file-relative-name file root))
          (default-directory root))
      (let ((rev (if (vc-jj--file-modified relative)
                     "@"
                   "@-")))
        (car (process-lines "jj" "log" "--no-graph"
                            "-r" rev
                            "-T" "self.change_id().short() ++ \"\\n\""))))))

(defun vc-jj-create-repo ()
  (if current-prefix-arg
      (call-process "jj" nil nil nil "git" "init" "--colocate")
    (call-process "jj" nil nil nil "git" "init")))

(defun vc-jj-register (_files &optional _comment)
  ;; No action needed.
  )

(defun vc-jj-delete-file (file)
  (when (file-exists-p file)
    (delete-file file)))

(defun vc-jj-rename-file (old new)
  (rename-file old new))

(defun vc-jj-checkin (files comment &optional _rev)
  (setq comment (replace-regexp-in-string "\\`Summary: " "" comment))
  (let ((args (append (vc-switches 'jj 'checkin) (list "--") files)))
    (apply #'call-process "jj" nil nil nil "commit" "-m" comment "--" args)))

(defun vc-jj-find-revision (file rev buffer)
  (call-process "jj" nil buffer nil "file" "show" "-r" rev "--" file))

(defun vc-jj-checkout (file &optional rev)
  (let ((args (if rev
                  (list "--from" rev "--" file)
                (list "--" file))))
    (call-process "jj" nil nil nil "restore" args)))

(defun vc-jj-revert (file &optional _contents-done)
  (call-process "jj" nil nil nil "restore" "--" file))

(defun vc-jj-print-log (files buffer &optional _shortlog start-revision limit)
  (let ((inhibit-read-only t)
        (erase-buffer)
        (args (append
               (when limit
                 (list "-n" (number-to-string limit)))
               (when start-revision
                 (list "-r" (concat ".." start-revision)))
               (list "--")
               files)))
    (apply #'call-process "jj" nil buffer nil "log" args))
  (goto-char (point-min)))

(defun vc-jj-show-log-entry (revision)
  (goto-char (point-min))
  (when (search-forward-regexp
         (concat "^[^|]\\s-+\\(" (regexp-quote revision) "\\)\\s-+")
         nil t)
    (goto-char (match-beginning 1))))

;; (defun vc-jj-log-outgoing (buffer remote-location)
;;   ;; TODO
;;   )
;; (defun vc-jj-log-incoming (buffer remote-location)
;;   ;; TODO
;;   )

(defun vc-jj-root (_file)
  (with-temp-buffer
    (when (= 0 (call-process "jj" nil (list t nil) nil "root"))
      (buffer-substring (point-min) (1- (point-max))))))

(defalias 'vc-jj-responsible-p #'vc-jj-root)

(defun vc-jj-find-ignore-file (file)
  (expand-file-name ".gitignore"
		            (vc-jj-root file)))


(defvar vc-jj-diff-switches '("--git"))

(defun vc-jj-diff (files &optional rev1 rev2 buffer _async)
  ;; TODO: handle async
  (setq buffer (get-buffer-create (or buffer "*vc-diff*")))
  (cond
   ((and (null rev1)
         (null rev2))
    (setq rev1 "@-"))
   ((null rev1)
    (setq rev1 "root()")))
  (setq rev2 (or rev2 "@"))
  (let ((inhibit-read-only t)
        (args (append (vc-switches 'jj 'diff) (list "--") files)))
    (with-current-buffer buffer
      (erase-buffer))
    (apply #'call-process "jj" nil buffer nil "diff" "--from" rev1 "--to" rev2 args)
    (if (seq-some #'vc-jj--file-modified files)
        1
      0)))

(defun vc-jj-revision-completion-table (files)
  (let ((revisions
         (apply #'process-lines
                "jj" "log" "--no-graph"
                "-T" "self.change_id() ++ \"\\n\"" "--" files)))
    (lambda (string pred action)
      (if (eq action 'metadata)
          `(metadata . ((display-sort-function . ,#'identity)))
        (complete-with-action action revisions string pred)))))


(provide 'vc-jj)
;;; vc-jj.el ends here
