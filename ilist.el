;;; ilist.el --- Display a list in an ibuffer way.   -*- lexical-binding: t; -*-

;; Copyright (C) 2021  Durand

;; Author: Durand <mmemmew@gmail.com>
;; Keywords: convenience, maint

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

;; This is a library package.  That is to say, it should be used by
;; other packages, instead of by end users directly.  So the package
;; defines no interactive functions that can be called by keychords:
;; this is the job of the user-package of this package.

;; This provides a function to display a list in a similar manner to
;; ibuffer.  This means that we can use filters to filter the elements
;; of the list, and to group the elements in various ways.  The
;; original intention is to display bookmarks.

;;; Code:

;;; dependencies

(require 'text-property-search)

;;; column struct

;; This is similar to using `cl-defstruct', but this struct is so
;; simple that depending on the cl library seems unnecessary to me.

;;;; helper to define a column

(defun ilist-define-column (name fun &optional min max align elide)
  "Define a column to be displayed.
NAME is the name of the column.

FUN should be a function with one argument, the element of the
list, which returns the string to display.

MIN specifies the minimal width of the column.  This should be a
nonnegative integer.  Negative values will be converted to
positive values without queries.  If it is omitted or nil, it is
the same as 0.

MAX specifies the maximal width of the column.  This should be an
integer.  If it is less than or equal to zero, then there is no
limit on the width.  If it is omitted or nil, it is the same as
0.

ALIGN specifies how to align the column.  It should be one of
:left, :right, and :center.  If it is omitted or nil, it is the
same as :left.

ELIDE specifies how to elide the column if it is too long.  If it
is a string that string is used.  Any other value means to not
elide.

Note that if the length of ELIDE is greater than MIN, then it is
undefined behaviour.

Also, if the length of NAME is less than the width of the column,
then it is undefined behaviour.  Hence it is recommended to set
the minimum width to be greater than or equal to the length of
NAME, unless one is sure that the lengths of the elements of that
column will be sufficently long."
  (declare (pure t) (side-effect-free t))
  (list
   name
   fun
   (cond
    ((null min) 0)
    ((integerp min) (abs min))
    ((user-error "MIN should be an integer, but got %S" min)))
   (cond
    ((null max) 0)
    ((and (integerp max)
          (> max 0))
     max)
    ((integerp max)
     0)
    ((user-error "MAX should be an integer, but got %S" max)))
   (cond
    ((null align) :left)
    ((car (memq align (list :left :right :center))))
    ((user-error "ALIGN should be :left, :right, or :center, \
but got %S" align)))
   (cond ((stringp elide) elide))))

;;;; column accessors

(defalias 'ilist-column-name 'car
  "Return the NAME of COLUMN.

\(fn COLUMN)")

(defalias 'ilist-column-fun 'cadr
  "Return the FUN in COLUMN.

\(fn COLUMN)")

(defalias 'ilist-column-min 'caddr
  "Return the MIN in COLUMN.

\(fn COLUMN)")

(defalias 'ilist-column-max 'cadddr
  "Return the MAX in COLUMN.

\(fn COLUMN)")

;; Unfortunately (or not) there is no caddddr and cadddddr.
(defun ilist-column-align (column)
  "Return the ALIGN in COLUMN."
  (nth 4 column))

(defun ilist-column-elide (column)
  "Return the ELIDE in COLUMN."
  (nth 5 column))

;;; display a row

(defun ilist-display (ls columns)
  "Return a list of lists of strings displaying the list LS.
COLUMNS is a list of column specificationss, which will be passed
to `ilist-define-column'.  See the documentation string of
`ilist-define-column' for the formats of COLUMNS.

The return value is a cons cell, the `car' of which is the list
of lists of strings and the `cdr' of which is a list of widths of
columns."
  (declare (pure t) (side-effect-free t))
  (setq columns (mapcar (lambda (column)
                          (apply #'ilist-define-column column))
                        columns))
  (let ((column-len (length columns))
        (column-mins (mapcar #'ilist-column-min columns))
        (column-aligns (mapcar #'ilist-column-align columns))
        result column-widths)
    ;; result will be a list each of whose elements corresponds to an
    ;; element in LS.  Each element corresponds to a list, each of
    ;; whose elements corresponds to a column.  Each column
    ;; corresponds to a cons cell of the form (LEN . STR), where LEN
    ;; is the length of STR, and where STR is already elided or
    ;; truncated.  So result is of the form
    ;;
    ;; (((LEN11 . STR11) (LEN12 . STR12) ...)
    ;;  ((LEN21 . STR21) (LEN22 . STR22) ...))
    (setq
     result
     (mapcar
      (lambda (element)
        (mapcar
         (lambda (column)
           (let* ((str (funcall
                        (ilist-column-fun column)
                        element))
                  (str-len (length str))
                  (max-len (ilist-column-max column))
                  (elide (ilist-column-elide column))
                  (str
                   (cond
                    ((and (> max-len 0)
                          (> str-len max-len))
                     (cond
                      ((stringp elide)
                       (concat
                        (substring
                         str
                         0
                         (max (- max-len (length elide))
                              0))
                        elide))
                      ((substring str 0 max-len))))
                    (str))))
             (cons (length str) str)))
         columns))
      ls))
    (setq
     column-widths
     (mapcar
      (lambda (n)
        (let ((len 0))
          (mapc
           (lambda (element)
             (cond
              ((> (car (nth n element)) len)
               (setq len (car (nth n element))))))
           result)
          len))
      (number-sequence 0 (1- column-len))))
    (cons
     (mapcar
      (lambda (element)
        ;; we loop from the end of the columns, so that we can keep
        ;; pushing elements to the front, without having to reverse the
        ;; list afterwards.
        (let ((index (1- column-len))
              temp temp-width temp-align row)
          (while (>= index 0)
            (setq temp (nth index element))
            (setq temp-align (nth index column-aligns))
            ;; if the width is < min-width, then set the width to the
            ;; min-width.
            (cond
             ((< (nth index column-widths)
                 (nth index column-mins))
              (setq temp-width (nth index column-mins))
              (setcar (nthcdr index column-widths) temp-width))
             ((setq temp-width (nth index column-widths))))
            ;; pad according to the alignment.
            (cond
             ((eq temp-align :left)
              (setq
               row
               (cons
                (concat (cdr temp)
                        (make-string
                         (- temp-width
                            (car temp))
                         #x20))
                row)))
             ((eq temp-align :right)
              (setq
               row
               (cons
                (concat (make-string
                         (- temp-width
                            (car temp))
                         #x20)
                        (cdr temp))
                row)))
             ((setq
               row
               (cons
                (let ((pad-left-len (floor (- temp-width
                                              (car temp))
                                           2)))
                  (concat
                   (make-string pad-left-len #x20)
                   (cdr temp)
                   (make-string (- temp-width pad-left-len
                                   (car temp))
                                #x20)))
                row))))
            (setq index (1- index)))
          row))
      result)
     column-widths)))

;;; produce the string

(defun ilist-string (ls columns groups &optional discard-empty-p sorter)
  "Display list LS as the returned string.
COLUMNS will be passed to `ilist-define-column'.

GROUPS is a list of the following form.

\((NAME1 . FUN1) (NAME2 . FUN2) ...)

Here NAMEs are the strings to display as the header of the
groups.

FUNs are the functions to determine if an element belongs to the
group.  It should accept one argument, the element under
consideration, and should return non-nil if that element belongs
to the group.  The group that occurs first in the list GROUPS has
higher priority over those that occur later.

The display of each group is done by `ilist-display'.

If DISCARD-EMPTY-P is non-nil, then empty groups will not be
displayed.

If SORTER is non-nil, it should be a function with two arguments,
X and Y, and should return non-nil if X should come before Y."
  (declare (pure t) (side-effect-free t))
  ;; normalize SORTER
  (cond
   ((null sorter))
   ((not (functionp sorter))
    (user-error "SORTER should be a function, but got %S"
                sorter)))
  ;; we sort the list at the beginning
  (let* ((ls (copy-tree ls))
         (ls (cond ((null sorter) ls) ((sort ls sorter))))
         (temp-groups (copy-tree groups))
         column-widths temp-group group-results group-strs
         all-cols all-cols-indices header title-sep)
    ;; If we want to operate on the displayed list, then we should
    ;; store the original list, and the indices of each displayed
    ;; element.  But we re-order the elements while preparing the
    ;; display (that is sort of the whole point of the preparation),
    ;; so we must store the original indices as well.  As to the
    ;; original list, it is the responsibility of the user-package to
    ;; store the list and do something with it; we are only
    ;; responsible for the indices.
    (setq
     ls
     (let ((index -1))
       (mapcar
        (lambda (element)
          (setq index (1+ index))
          (cons index element))
        ls)))
    (while (consp temp-groups)
      (setq temp-group (car temp-groups))
      ;; NOTE: The order of group-results is reverse to the order we
      ;; want, and we will reverse the order again when we convert
      ;; that to a list of strings later.
      (setq
       group-results
       (cons
        (let ((fun (cdr temp-group))
              res remain)
          (mapc
           (lambda (element)
             (cond
              ;; the car is the original index, and the cdr is the
              ;; original element
              ((funcall fun (cdr element))
               (setq res (cons element res)))
              ((setq remain (cons element remain)))))
           ls)
          (setq ls (reverse remain))
          ;; endow it with a text property so that we can distinguish
          ;; a group header from a normal line
          (list (propertize
                 (format "[ %s ]" (car temp-group))
                 'ilist-group-header (car temp-group))
                (reverse res)))
        group-results))
      (setq temp-groups (cdr temp-groups)))
    ;; group-strs will not be in the final format yet, after this
    ;; `while'.
    (while (consp group-results)
      (setq temp-group (car group-results))
      (setq group-results (cdr group-results))
      (setq all-cols
            ;; NOTE: since the order of group-results is reverse, we
            ;; append it to the front instead to the end.  This
            ;; ensures the worst time complexity is linear.  After
            ;; this step the order of group-strs is the order we want.
            (append (cadr temp-group) all-cols))
      ;; here group-strs only contains the number of elements to
      ;; possess
      (setq
       group-strs
       (cons
        (cons (car temp-group)
              (length (cadr temp-group)))
        group-strs)))
    ;; `ilist-display' has nothing to do with the indices, so we first
    ;; separate the indices from the elements, and then zip them
    ;; together later.
    (setq all-cols-indices (mapcar #'car all-cols))
    (setq all-cols (mapcar #'cdr all-cols))
    ;; `ilist-display' is called on all elements, so that it can
    ;; calculate the maximal width correctly.
    (setq all-cols (ilist-display all-cols columns))
    (setq column-widths (cdr all-cols))
    ;; we zip the indices back
    (setq all-cols
          (let* ((car-all-cols (car all-cols))
                 (len (length car-all-cols))
                 (index (1- len))
                 res)
            (while (>= index 0)
              (setq res
                    (cons
                     (cons
                      (nth index all-cols-indices)
                      (nth index car-all-cols))
                     res))
              (setq index (1- index)))
            res))
    ;; after the following group-strs has indices and strings in the
    ;; cells
    (let ((index 0) step)
      (mapc
       (lambda (cell)
         (setq step (cdr cell))
         (setcdr cell
                 (mapcar (lambda (n) (nth n all-cols))
                         (number-sequence
                          index (+ index -1 step))))
         (setq index (+ index step)))
       group-strs))
    ;; calculate the headers and the titles
    (let ((index 0))
      (setq
       header
       ;; `mapconcat' uses a `mapcar' under the hood, so the order of
       ;; elements will be preserved
       (mapconcat
        (lambda (col)
          ;; pad according to the alignment
          (let* ((width (nth index column-widths))
                 (alignment (ilist-column-align col))
                 (name (ilist-column-name col))
                 (complement (- width (length name)))
                 (floor-len (floor complement 2)))
            ;; we increase the index before the end of the form
            (setq index (1+ index))
            (cond
             ((eq alignment :left)
              (concat
               name
               (make-string complement #x20)))
             ((eq alignment :right)
              (concat
               (make-string complement #x20)
               name))
             ;; :center
             ((concat
               (make-string floor-len #x20)
               name
               (make-string (- complement floor-len) #x20))))))
        columns
        (string #x20)))
      ;; don't forget to reset the index
      (setq index 0)
      ;; mutatis mutandis
      (setq
       title-sep
       (mapconcat
        (lambda (col)
          (let* ((width (nth index column-widths))
                 (alignment (ilist-column-align col))
                 (name (ilist-column-name col))
                 (name-sep (make-string (length name) ?-))
                 (complement (- width (length name)))
                 (floor-len (floor complement 2)))
            (setq index (1+ index))
            (cond
             ((eq alignment :left)
              (concat
               name-sep
               (make-string complement #x20)))
             ((eq alignment :right)
              (concat
               (make-string complement #x20)
               name-sep))
             ((concat
               (make-string floor-len #x20)
               name-sep
               (make-string (- complement floor-len) #x20))))))
        columns
        (string #x20))))
    ;; delete empty groups if demanded
    (cond
     (discard-empty-p
      (setq
       group-strs
       (delq
        nil
        (mapcar
         (lambda (group)
           (cond
            ;; one way of testing if a list has length = 1
            ((null (cdr group)) nil)
            (group)))
         group-strs)))))
    (setq group-strs
          (append
           ;; special properties
           (list (propertize header 'ilist-header t)
                 (propertize title-sep 'ilist-title-sep t))
           ;; transform back to the format we want
           (mapcar
            (lambda (element)
              (concat
               ;; title
               (car element)
               ;; for empty groups don't add a newline
               (cond ((cdr element) (string #xa)))
               ;; rows
               (mapconcat
                (lambda (row)
                  (propertize
                   (mapconcat
                    #'identity (cdr row) (string #x20))
                   'ilist-index (car row)))
                (cdr element)
                (string #xa))))
            group-strs)))
    (mapconcat #'identity group-strs (string #xa))))

;;; map over lines

(defun ilist-map-lines (fun &optional predicate start end)
  "Execute FUN over lines.
If PREDICATE is non-nil, it should be a function to determine
whether to execute FUN on the line.

If START or END is non-nil, it specifies the boundaries of the
execution lines.  It can be an integer or a marker.  If it is a
marker, the buffer of the marker should be the current buffer.

The return value is the list of execution results on the lines
over which the function is executed."
  ;; normalizations
  (cond
   ((not (functionp predicate))
    (setq predicate nil)))
  (cond
   ((not (integer-or-marker-p start))
    (setq start nil))
   ((and
     (markerp start)
     (not (equal (marker-buffer start) (current-buffer))))
    (setq start nil)))
  (cond
   ((not (integer-or-marker-p end))
    (setq end nil))
   ((and
     (markerp end)
     (not (equal (marker-buffer end) (current-buffer))))
    (setq end nil)))
  (save-excursion
    (goto-char (cond (start) ((point-min))))
    (let (res)
      (while (and (not (ilist-boundary-buffer-p t))
                  (or (null end)
                      (< (point) end)))
        (cond
         ((or (null predicate)
              (funcall predicate))
          (setq res
                (cons
                 (funcall fun)
                 res))))
        (ilist-forward-line 1))
      (nreverse res))))

;;; Get index at point

(defun ilist-get-index ()
  "Return the index of the element at point.
If point is not at an element, return nil."
  (declare (side-effect-free t))
  (get-text-property (point) 'ilist-index))

;;; Get group header

(defun ilist-get-group ()
  "Return the group header at point.
If point is not at a group header return nil."
  (declare (side-effect-free t))
  (get-text-property (point) 'ilist-group-header))

;;; marks related

;; It is possible that some user-package does not need the
;; capibilities of marking, so this is provided as an optional
;; feature.  An advantage of this approach is that the user-packages
;; are thus permitted (or encouraged) to implement their own versions
;; of marking, which might better suit their needs.

;;;; mark column

(defun ilist-mark-column-fun (_el)
  "The function that displays the mark.
The function just returns a propertized string, indicating that
the mark column is present.

EL is ignored."
  (declare (pure t) (side-effect-free t))
  (propertize (string #x20) 'ilist-mark-column t))

(defvar ilist-mark-column
  '("" ilist-mark-column-fun nil 1)
  "The column that displays the mark status.
Add this to the list of columns to display marks.")

;;;; find mark columns

(defun ilist-mark-columns (position &optional end)
  "Return the list of mark columns on the same line as POSITION.
The result is in descending order, so the later positions come
first.

If END is non-nil, it specifies the end of the search."
  (declare (side-effect-free t))
  (save-excursion
    (goto-char position)
    (goto-char (line-beginning-position))
    (save-restriction
      (narrow-to-region (point) (or end (line-end-position)))
      (let (res prop-match)
        (while (setq
                prop-match
                ;; search for a non-nil value, and the region ends if
                ;; the value of the property changes, according to the
                ;; doc of the function
                (text-property-search-forward
                 'ilist-mark-column))
          (setq
           res
           (cons
            (cons
             (prop-match-beginning prop-match)
             (prop-match-end prop-match))
            res)))
        res))))

;;;; find marks

(defun ilist-get-marks ()
  "Return the list of marks on the line.
The marks are in descending order, i.e. the mark that occurs
later on the line come earlier in the result list.

It is considered a mark only if the value is not t or nil.
Non-mark values are simply ignored."
  (delq
   nil
   (mapcar
    (lambda (cons-cell)
      (let ((value (get-text-property
                    (car cons-cell) 'ilist-mark-column)))
        (cond
         ((and value
               (not (eq value t)))
          value))))
    (ilist-mark-columns (point)))))

;;;; mark

(defun ilist-mark-with-char (char)
  "Mark the elements under point by CHAR.
This function simply sets the text property of
`ilist-mark-column' to CHAR, and the display property to the
character.  If CHAR is not a character, this removes the display
property.

The return value is the same as `ilist-mark-columns'."
  (let ((position-list (ilist-mark-columns (point))))
    (mapc
     ;; each element of the position is a cons cell
     (lambda (cell)
       (add-text-properties
        (car cell)
        (cdr cell)
        (list 'ilist-mark-column char))
       (cond
        ((characterp char)
         (add-text-properties
          (car cell)
          (cdr cell)
          (list 'display
                (make-string (- (cdr cell)
                                (car cell))
                             char))))
        ((remove-text-properties
          (car cell)
          (cdr cell)
          (list 'display nil)))))
     position-list)))

;;;; unmark

(defun ilist-unmark ()
  "Unmark the line under point.
This just sets the text property of `ilist-mark-column' to t."
  ;; we can mark with "CHAR t"
  (ilist-mark-with-char t))

;;;; list of items and their marks

(defun ilist-current-status ()
  "Return the list of items and their marks."
  (ilist-map-lines
   (lambda ()
     (cons (get-text-property
            (point) 'ilist-index)
           (get-text-property
            (point) 'ilist-mark-column)))
   (lambda ()
     (get-text-property
      (point) 'ilist-index))))

;;;; map over marked items

;; Nothing to do here, since we can call `ilist-map-lines' with a
;; predicate function that tests whether the text property of
;; 'ilist-mark-column is a non-nil value not equal to t.

(defun ilist-is-marked ()
  "Return t if the current line is marked."
  ;; REVIEW: Maybe we shall not find all columns on the line
  (let* ((columns (ilist-mark-columns (point)))
         (value (cond
                 ((consp columns)
                  (get-text-property (caar columns) 'ilist-mark-column)))))
    (and value (not (eq value t)))))

;;; rounded movements

;;;; boundaries of buffer

(defun ilist-boundary-buffer-p (forward-p)
  "Return whether the point is at a boundary of the buffer.
If FORWARD-P is non-nil, then test whether we are at the end of
the buffer.  Otherwise test whether we are at the beginning of
the buffer."
  (declare (side-effect-free t))
  (cond
   (forward-p (eobp))
   ((or (get-text-property (point) 'ilist-header)
        (get-text-property (point) 'ilist-title-sep)
        (bobp)))))

;;;; skip the boundary

;; REVIEW: Maybe we should call it "round-boundary" instead?
(defun ilist-skip-boundary (rounded forwardp other-end)
  "Skip the boundary of the buffer if needed.
If ROUNDED is non-nil, then try not to stay at the boundary of
the buffer.

FORWARDP determines in which direction to move.

OTHER-END specifies where to go when the boundary is
encountered."
  (cond
   ((and rounded (ilist-boundary-buffer-p forwardp))
    (goto-char other-end)
    (let ((continuep t))
      (while (and continuep
                  (ilist-boundary-buffer-p (not forwardp)))
        (forward-line (cond (forwardp 1) (-1)))
        (cond
         ((ilist-boundary-buffer-p forwardp)
          ;; nowhere to stay, so we just stop
          (setq continuep nil))))))))

;;;; skip properties

(defun ilist-skip-properties (skip-groups forwardp properties)
  "Try to skip text PROPERTIES if SKIP-GROUPS is non-nil.
PROPERTIES is a list of text properties to skip.

FORWARDP determines the direction to test for the boundary."
  (while (and skip-groups
              (let ((fake-properties properties)
                    res)
                (while (and (not res)
                            (consp fake-properties))
                  (setq res
                        (get-text-property
                         (point) (car fake-properties)))
                  (setq fake-properties (cdr fake-properties)))
                res)
              ;; check boundaries to prevent infinite loops
              (not (ilist-boundary-buffer-p forwardp)))
    (forward-line (cond (forwardp 1) (-1)))))

;;;; moving between lines

(defun ilist-forward-line (&optional arg rounded skip-groups)
  "Go to ARG th next line.
If ROUNDED is non-nil, assume the top of the buffer is connected
to the bottom of the buffer.

If SKIP-GROUPS is non-nil, try not to stop point on a group
header."
  ;; make sure ARG is a number
  (setq arg (prefix-numeric-value arg))
  (let* ((forwardp (> arg 0))
         (other-end (cond (forwardp (point-min))
                          ((save-excursion
                             (goto-char (point-max))
                             (line-beginning-position)))))
         (original-point (point))
         (arg (abs arg)))
    (ilist-skip-properties t forwardp
                           '(ilist-header
                             ilist-title-sep))
    (ilist-skip-properties skip-groups forwardp
                           '(ilist-group-header))
    (cond ((/= original-point (point))
           (setq arg (1- arg))))
    (while (> arg 0)
      (forward-line (cond (forwardp 1) (-1)))
      ;; skip the group and the boundary twice to ensure that we avoid
      ;; the edges as much as possible.
      (ilist-skip-boundary rounded forwardp other-end)
      (ilist-skip-properties skip-groups forwardp '(ilist-group-header))
      (ilist-skip-boundary rounded forwardp other-end)
      (ilist-skip-properties skip-groups forwardp '(ilist-group-header))
      (setq arg (1- arg)))))

(defun ilist-backward-line (&optional arg rounded skip-groups)
  "Go to ARG th previous line.
If ROUNDED is non-nil, assume the top of the buffer is connected
to the bottom of the buffer.

If SKIP-GROUPS is non-nil, try not to stop point on a group
header."
  (ilist-forward-line (- (prefix-numeric-value arg))
                      rounded skip-groups))

;;;; moving between group headers

(defun ilist-forward-group-header (&optional arg rounded)
  "Go to ARG th next group header.
If ROUNDED is non-nil, assume the top of the buffer is connected
to the bottom of the buffer."
  ;; make sure ARG is a number
  (setq arg (prefix-numeric-value arg))
  (let* ((forwardp (> arg 0))
         (other-end (cond (forwardp (point-min))
                          ((save-excursion
                             (goto-char (point-max))
                             (line-beginning-position)))))
         (original-point (point))
         (arg (abs arg)))
    (ilist-skip-properties
     t forwardp '(ilist-header ilist-title-sep))
    ;; when it moves, it should step on a header
    (cond ((/= original-point (point))
           (setq arg (1- arg))))
    (while (> arg 0)
      (forward-line (cond (forwardp 1) (-1)))
      ;; skip the group and the boundary twice to ensure that we avoid
      ;; the edges as much as possible.
      (ilist-skip-boundary rounded forwardp other-end)
      ;; skip index so that we skip "normal" lines
      (ilist-skip-properties t forwardp '(ilist-index))
      (ilist-skip-boundary rounded forwardp other-end)
      (ilist-skip-properties t forwardp '(ilist-index))
      (setq arg (1- arg)))))

(defun ilist-backward-group-header (&optional arg rounded)
  "Go to ARG th previous group header.
If ROUNDED is non-nil, assume the top of the buffer is connected
to the bottom of the buffer."
  (ilist-forward-group-header
   (- (prefix-numeric-value arg)) rounded))

;;; Delete from ALIST

(defun ilist-delete-from-list (ls elements)
  "Remove ELEMENTS from LS.
ELEMENTS are indices of elements to be removed in LS.

Assumes that ELEMENTS is sorted, so that the larger indices come
later.

And the indices are zero-based.

This does not modify LS or ELEMENTS.  It returns a copy of LS
with ELEMENTS removed."
  (declare (pure t) (side-effect-free t))
  ;; REVIEW: In our case, since both LS and ELEMENTS are sorted, we
  ;; might have a faster implementation which employs the sorted-ness
  ;; of the arguments, but I think it is pre-mature optimisation.
  (let* ((temp (copy-tree ls)))
    ;; NOTE: Using `mapc' is faster than a while loop, as the manual
    ;; says. Since `dolist' is in essence a while loop, using `mapc'
    ;; will be faster. Of course for our purposes this is premature
    ;; optimisation.
    (mapc
     (lambda (index)
       (cond
        ((> index 0)
         ;; Using `setcdr' is more efficient but destructively
         ;; modifies the list. So we used `copy-tree' to prevent the
         ;; destructions.
         (setcdr (nthcdr (1- index) temp)
                 (nthcdr (1+ index) temp)))
        ((setq temp (cdr temp)))))
     (reverse elements))
    temp))

;;; major mode

;; This major mode is the basis that should be derived by
;; user-packages.

(define-derived-mode ilist-mode special-mode "IList"
  "Display a list in a similar fashion to ibuffer."
  (setq truncate-lines t))

;; It is intentional that no key-bindings are defined.

(provide 'ilist)
;;; ilist.el ends here
