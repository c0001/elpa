;;; compat-30.el --- Functionality added in Emacs 30 -*- lexical-binding: t; -*-

;; Copyright (C) 2023 Free Software Foundation, Inc.

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

;; Functionality added in Emacs 30, needed by older Emacs versions.

;;; Code:

(eval-when-compile (load "compat-macs.el" nil t t))
(compat-require compat-29 "29.1")

;; TODO Update to 30.1 as soon as the Emacs emacs-30 branch version bumped
(compat-version "30.0.50")

;;;; Defined in buffer.c

(compat-defun find-buffer (variable value) ;; <compat-tests:find-buffer>
  "Return the buffer with buffer-local VARIABLE equal to VALUE.
If there is no such live buffer, return nil."
  (cl-loop for buffer the buffers
           if (equal (buffer-local-value variable buffer) value)
           return buffer))

(compat-defun get-truename-buffer (filename) ;; <compat-tests:get-truename-buffer>
  "Return the buffer with `file-truename' equal to FILENAME (a string).
If there is no such live buffer, return nil.
See also `find-buffer-visiting'."
  (find-buffer 'buffer-file-truename filename))

;;;; Defined in files.el

(compat-defun require-with-check (feature &optional filename noerror) ;; <compat-tests:require-with-check>
  "If FEATURE is not already loaded, load it from FILENAME.
This is like `require' except if FEATURE is already a member of the list
`features’, then we check if this was provided by a different file than the
one that we would load now (presumably because `load-path' has been
changed since the file was loaded).
If it's the case, we either signal an error (the default), or forcibly reload
the new file (if NOERROR is equal to `reload'), or otherwise emit a warning."
  (let ((lh load-history)
        (res (require feature filename (if (eq noerror 'reload) nil noerror))))
    ;; If the `feature' was not yet provided, `require' just loaded the right
    ;; file, so we're done.
    (when (eq lh load-history)
      ;; If `require' did nothing, we need to make sure that was warranted.
      (let ((fn (locate-file (or filename (symbol-name feature))
                             load-path (get-load-suffixes))))
        (cond
         ((assoc fn load-history) nil)  ;We loaded the right file.
         ((eq noerror 'reload) (load fn nil 'nomessage))
         (t (funcall (if noerror #'warn #'error)
                     "Feature provided by other file: %S" feature)))))
    res))

;;;; Defined in minibuffer.el

(compat-defvar completion-lazy-hilit nil ;; <compat-tests:completion-lazy-hilit>
  "If non-nil, request lazy highlighting of completion candidates.

Lisp programs (a.k.a. \"front ends\") that present completion
candidates may opt to bind this variable to a non-nil value when
calling functions (such as `completion-all-completions') which
produce completion candidates.  This tells the underlying
completion styles that they do not need to fontify (i.e.,
propertize with the `face' property) completion candidates in a
way that highlights the matching parts.  Then it is the front end
which presents the candidates that becomes responsible for this
fontification.  The front end does that by calling the function
`completion-lazy-hilit' on each completion candidate that is to be
displayed to the user.

Note that only some completion styles take advantage of this
variable for optimization purposes.  Other styles will ignore the
hint and fontify eagerly as usual.  It is still safe for a
front end to call `completion-lazy-hilit' in these situations.

To author a completion style that takes advantage of this variable,
see `completion-lazy-hilit-fn' and `completion-pcm--hilit-commonality'.")

(compat-defvar completion-lazy-hilit-fn nil ;; <compat-tests:completion-lazy-hilit>
  "Fontification function set by lazy-highlighting completions styles.
When a given style wants to enable support for `completion-lazy-hilit'
\(which see), that style should set this variable to a function of one
argument.  It will be called with each completion candidate, a string, to
be displayed to the user, and should destructively propertize these
strings with the `face' property.")

(compat-defun completion-lazy-hilit (str) ;; <compat-tests:completion-lazy-hilit>
  "Return a copy of completion candidate STR that is `face'-propertized.
See documentation of the variable `completion-lazy-hilit' for more
details."
  (if (and completion-lazy-hilit completion-lazy-hilit-fn)
      (funcall completion-lazy-hilit-fn (copy-sequence str))
    str))

;;;; Defined in subr.el

(compat-defun merge-ordered-lists (lists &optional error-function) ;; <compat-tests:merge-ordered-lists>
  "Merge LISTS in a consistent order.
LISTS is a list of lists of elements.
Merge them into a single list containing the same elements (removing
duplicates), obeying their relative positions in each list.
The order of the (sub)lists determines the final order in those cases where
the order within the sublists does not impose a unique choice.
Equality of elements is tested with `eql'.

If a consistent order does not exist, call ERROR-FUNCTION with
a remaining list of lists that we do not know how to merge.
It should return the candidate to use to continue the merge, which
has to be the head of one of the lists.
By default we choose the head of the first list."
  (let ((result '()))
    (setq lists (remq nil lists))
    (while (cdr (setq lists (delq nil lists)))
      (let* ((next nil)
             (tail lists))
        (while tail
          (let ((candidate (caar tail))
                (other-lists lists))
            (while other-lists
              (if (not (memql candidate (cdr (car other-lists))))
                  (setq other-lists (cdr other-lists))
                (setq candidate nil)
                (setq other-lists nil)))
            (if (not candidate)
                (setq tail (cdr tail))
              (setq next candidate)
              (setq tail nil))))
        (unless next
          (setq next (funcall (or error-function #'caar) lists))
          (unless (funcall
                   (eval-when-compile (if (fboundp 'compat--assoc) 'compat--assoc 'assoc))
                   next lists #'eql)
            (error "Invalid candidate returned by error-function: %S" next)))
        (push next result)
        (setq lists
              (mapcar (lambda (l) (if (eql (car l) next) (cdr l) l))
                      lists))))
    (if (null result) (car lists)
      (append (nreverse result) (car lists)))))

(compat-defun copy-tree (tree &optional vectors-and-records) ;; <compat-tests:copy-tree>
  "Handle copying records when optional arg is non-nil."
  :min-version "26.1" ;; recordp is only available on Emacs 26.1 and newer
  :extended t
  (declare (side-effect-free error-free))
  (if (consp tree)
      (let (result)
        (while (consp tree)
          (let ((newcar (car tree)))
            (if (or (consp (car tree))
                    (and vectors-and-records
                         (or (vectorp (car tree)) (recordp (car tree)))))
                (setq newcar (compat--copy-tree (car tree) vectors-and-records)))
            (push newcar result))
          (setq tree (cdr tree)))
        (nconc (nreverse result)
               (if (and vectors-and-records (or (vectorp tree) (recordp tree)))
                   (compat--copy-tree tree vectors-and-records)
                 tree)))
    (if (and vectors-and-records (or (vectorp tree) (recordp tree)))
        (let ((i (length (setq tree (copy-sequence tree)))))
          (while (>= (setq i (1- i)) 0)
            (aset tree i (compat--copy-tree (aref tree i) vectors-and-records)))
          tree)
      tree)))

(compat-defmacro static-if (condition then-form &rest else-forms) ;; <compat-tests:static-if>
  "A conditional compilation macro.
Evaluate CONDITION at macro-expansion time.  If it is non-nil,
expand the macro to THEN-FORM.  Otherwise expand it to ELSE-FORMS
enclosed in a `progn' form.  ELSE-FORMS may be empty."
  (declare (indent 2) (debug (sexp sexp &rest sexp)))
  (if (eval condition lexical-binding)
      then-form
    (cons 'progn else-forms)))

(provide 'compat-30)
;;; compat-30.el ends here