;;; dtache-eshell.el --- Dtache integration for eshell -*- lexical-binding: t -*-

;; Copyright (C) 2021-2022  Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This is a `dtache' extension which provides integration for `eshell'.

;;; Code:

;;;; Requirements

(require 'dtache)
(require 'eshell)
(require 'esh-mode)
(require 'esh-ext)
(require 'em-hist)

;;;; Variables

(defcustom dtache-eshell-session-action
  '(:attach dtache-shell-command-attach-session
            :view dtache-view-dwim
            :run dtache-shell-command)
  "Actions for a session created with `dtache-eshell'."
  :group 'dtache
  :type 'plist)

;;;; Functions

(defun dtache-eshell-select-session ()
  "Return selected session."
  (let* ((host-name (car (dtache--host)))
         (sessions
          (thread-last (dtache-get-sessions)
                       (seq-filter (lambda (it)
                                     (string= (car (dtache--session-host it)) host-name)))
                       (seq-filter (lambda (it) (eq 'active (dtache--determine-session-state it)))))))
    (dtache-completing-read sessions)))

(defun dtache-eshell-get-dtach-process ()
  "Return `eshell' process if `dtache' is running."
  (when-let* ((process (and eshell-process-list (caar eshell-process-list))))
    (and (string= (process-name process) "dtach")
         process)))

;;;; Commands

;;;###autoload
(defun dtache-eshell-send-input (&optional detach)
  "Create a session and attach to it.

If prefix-argument directly DETACH from the session."
  (interactive "P")
  (let* ((dtache-session-origin 'eshell)
         (dtache-session-mode (if detach 'create 'create-and-attach))
         (dtache-enabled t)
         (dtache--current-session nil))
    (advice-add #'eshell-external-command :around #'dtache-eshell-external-command)
    (call-interactively #'eshell-send-input)))

;;;###autoload
(defun dtache-eshell-attach-session (session)
  "Attach to SESSION."
  (interactive
   (list (dtache-eshell-select-session)))
  (when (dtache-valid-session session)
    (if (and (eq 'active (dtache--determine-session-state session))
             (dtache--session-attachable session))
        (cl-letf* ((dtache-session-mode 'attach)
                   (input
                    (dtache-dtach-command session t))
                   ((symbol-function #'eshell-add-to-history) #'ignore))
          (eshell-kill-input)
          ;; Hide the input from the user
          (let ((begin (point))
                (end))
            (insert input)
            (setq end (point))
            (overlay-put (make-overlay begin end) 'invisible t)
            (overlay-put (make-overlay end end) 'before-string "[attached]")
            (insert " "))
          (setq dtache--buffer-session session)
          (call-interactively #'eshell-send-input))
      (dtache-open-session session))))

;;;; Support functions

;;;###autoload
(defun dtache-eshell-external-command (orig-fun &rest args)
  "Advice `eshell-external-command' to optionally use `dtache'."
  (let* ((dtache-session-action dtache-eshell-session-action)
         (command (string-trim-right
                   (mapconcat #'identity
                              (flatten-list args)
                              " ")))
         (session (dtache-create-session command))
         (command (dtache-dtach-command session)))
    (advice-remove #'eshell-external-command #'dtache-eshell-external-command)
    (setq dtache--buffer-session session)
    (setq dtache-enabled nil)
    (apply orig-fun `(,(seq-first command) ,(seq-rest command)))))

;;;; Minor mode

(defvar dtache-eshell-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<S-return>") #'dtache-eshell-send-input)
    (define-key map (kbd "<C-return>") #'dtache-eshell-attach-session)
    (define-key map (kbd dtache-detach-key) #'dtache-detach-session)
    map)
  "Keymap for `dtache-eshell-mode'.")

;;;###autoload
(define-minor-mode dtache-eshell-mode
  "Integrate `dtache' in `eshell-mode'."
  :lighter " dtache-eshell"
  :keymap (let ((map (make-sparse-keymap)))
            map)
  (make-local-variable 'eshell-preoutput-filter-functions)
  (if dtache-eshell-mode
      (progn
        (add-hook 'eshell-preoutput-filter-functions #'dtache--dtache-env-message-filter)
        (add-hook 'eshell-preoutput-filter-functions #'dtache--dtach-eof-message-filter))
    (remove-hook 'eshell-preoutput-filter-functions #'dtache--dtache-env-message-filter)
    (remove-hook 'eshell-preoutput-filter-functions #'dtache--dtach-eof-message-filter)))

(provide 'dtache-eshell)

;;; dtache-eshell.el ends here
