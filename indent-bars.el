;;; indent-bars.el --- Highlight indentation with bars -*- lexical-binding: t; -*-
;; Copyright (C) 2023  J.D. Smith

;; Author: J.D. Smith
;; Homepage: https://github.com/jdtsmith/indent-bars
;; Package-Requires: ((emacs "27.1") (compat "29.1.4.1"))
;; Version: 0.2.3
;; Keywords: convenience
;; Prefix: indent-bars
;; Separator: -

;; indent-bars is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.

;; indent-bars is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; indent-bars highlights indentation with configurable font-lock
;; based vertical bars, using stipples.  The color and appearance
;; (weight, pattern, position within the character, zigzag, etc.) are
;; all configurable.  Includes the option for depth-varying colors and
;; highlighting the indentation level of the current line.  Bars span
;; blank lines, by default.  indent-bars works in any mode using fixed tab
;; or space-based indentation.  In the terminal (or on request) it
;; uses vertical bar characters instead of stipple patterns.

;; For Developers:
;;
;; To efficiently accommodate simultaneous alternative bar styling, we
;; do two things:
;;
;;  1. Collect all the style related information (color, stipple
;;     pattern, etc.) into a single struct, operating on one such
;;     "current" style struct at a time.
;;
;;  2. Provide convenience functions for replicating "alternative"
;;     custom variables the user can configure; see
;;     `indent-bars--style'.  These variables can "inherit" nil or
;;     omitted plist variables from their parent var.
;;
;; To temporarily alter the current style, it's enough to bind the
;; variable `indent-bars-current-style' dynamically.
;;
;; Note the shorthand substitution for style related slot
;; (see file-local-variables at the end):
;; 
;;    ibs/  => indent-bars-style-

;;; Code:
;;;; Requires
(require 'cl-lib)
(require 'map)
(require 'color)
(require 'timer)
(require 'face-remap)
(require 'outline)
(require 'font-lock)
(require 'compat)

;;;; Customization
(defgroup indent-bars nil
  "Highlight indentation bars."
  :group 'basic-faces
  :prefix "indent-bars-")

(defgroup indent-bars-style nil
  "Highlight indentation bars."
  :group 'basic-faces
  :prefix "indent-bars-")

;;;;; Stipple Bar Shape

(defcustom indent-bars-width-frac 0.4
  "The width of the indent bar as a fraction of the character width.
Applies to stipple-based bars only."
  :type '(float :tag "Width Fraction"
		:match (lambda (_ val) (and val (<= val 1) (>= val 0)))
		:type-error "Fraction must be between 0 and 1")
  :group 'indent-bars-style)

(defcustom indent-bars-pad-frac 0.1
  "The offset of the bar from the left edge of the character.
A float, the fraction of the character width.  Applies to
 stipple-based bars only."
  :type '(float :tag "Offset Fraction"
	  :match (lambda (_ val) (and val (<= val 1) (>= val 0)))
	  :type-error "Fraction must be between 0 and 1")
  :group 'indent-bars-style)

(defcustom indent-bars-pattern " .   .  "
  "A pattern specifying the vertical structure of indent bars.
Space signifies blank regions, and any other character signifies
filled regions.  The pattern length is scaled to match the
character height.  Example: \". . \" would specify alternating
filled and blank regions each approximately one-quarter of the
character height.  Note that the non-blank characters need not be
the same (e.g., see `indent-bars-zigzag').  Applies to
stipple-based bars only."
  :type '(string :tag "Fill Pattern")
  :group 'indent-bars-style)

(defcustom indent-bars-zigzag nil
  "The zigzag to apply to the bar pattern.
If non-nil, an alternating zigzag offset will be applied to
consecutive groups of identical non-space characters in
`indent-bars-pattern'.  Starting from the top of the pattern,
positive values will zigzag (right, left, right, ..) and negative
values (left, right, left, ...).

Example:

  pattern: \" .**.\"
  width:   0.5
  pad:     0.25
  zigzag: -0.25

would produce a zigzag pattern which differs from the normal
bar pattern as follows:

    |    |            |    |
    | .. | =========> |..  |
    | .. |            |  ..|
    | .. | apply zig- |  ..|
    | .. | zag -0.25  |..  |

Note that the pattern will be truncated at both left and right
boundaries, so (although this is not required) achieving an equal
zigzag left and right requires leaving sufficient padding on each
side of the bar; see `indent-bars-pad-frac' and
`indent-bars-width-frac'.  Applies to stipple-based bars only."
  :type '(choice :tag "Zigzag Options"
		 (const :tag "No Zigzag" :value nil)
		 (float :value 0.1 :tag "Zigzag Fraction"
			:match (lambda (_ val) (and val (<= val 1) (>= val -1)))
			:type-error "Fraction must be between -1 and 1"))
  :group 'indent-bars-style)

;;;;; Bar Colors
(defcustom indent-bars-color
  '(highlight :face-bg t :blend 0.4)
  "The main indent bar color.
The format is a list of 1 required element, followed by an
optional plist (keyword/value pairs):

  (main_color [:face-bg :blend])

where:

  MAIN_COLOR: Specifies the main indentation bar
    color (required).  It is either a face name symbol, from
    which the foreground color will be used as the primary bar
    color, or an explicit color (a string).  If nil, the default
    color foreground will be used.

  FACE-BG: A boolean controlling interpretation of the
    MAIN_COLOR face (if configured).  If non-nil, the background
    color of the face will be used as the main bar color instead
    of its foreground.

  BLEND: an optional blend factor, a float between 0 and 1.  If
    non-nil, the main bar color will be computed as a blend
    between MAIN_COLOR and the frame background color,
    notionally:

      BLEND * MAIN_COLOR + (1 - BLEND) * frame-background

    If BLEND is nil or unspecified, no blending is done, and
    MAIN_COLOR is used as-is."
  :type
  '(list :tag "Color Options"
    (choice :tag "Main Bar Color"
	    color
	    (face :tag "from Face")
	    (const :tag "Use default" nil))
    (plist :tag "Other Options"
	   :inline t
	   :options
	   ((:face-bg (boolean
		       :tag "Use Face's Background Color"
		       :value t))
	    (:blend (float
		     :tag "Blend Factor"
		     :value 0.5
		     :match (lambda (_ val) (and val (<= val 1) (>= val 0)))
		     :type-error "Factor must be between 0 and 1")))))
  :group 'indent-bars-style)

(defcustom indent-bars-color-by-depth
  '(:regexp "outline-\\([0-9]+\\)" :blend 1)
  "Configuration for depth-varying indentation bar coloring.
If non-nil, depth-based coloring is performed.  This should be a
plist with keys:

    ([:regexp [:face-bg] | :palette] [:blend])

with:

  REGEXP: A regular expression string used to match against all
    face names.  For the matching faces, the first match group in
    the regex (if any) will be interpreted as a number, and used
    to sort the resulting list of faces.  The foreground color of
    each matching face will then constitute the depth color
    palette (see also PALETTE, which this option overrides).

  FACE-BG: A boolean.  If non-nil, use the background color
    from the faces matching REGEXP for the palette instead of
    their foreground colors.

  PALETTE: An explicit cyclical palette of colors/faces for
    depth-varying bar colors.  Note that REGEXP takes precedence
    over this setting.  The format is a list of faces (symbols)
    or colors (strings) to be used as a color cycle for coloring
    indentations at increasing levels.  Each face can optionally
    be specified as a cons cell (face . \\='bg) to specify using
    that face's background color instead of its foreground.

      (face_or_color | (face . \\='bg) ...)

    While this list can contain a single element, it makes little
    sense to do so.  The depth palette will be used cyclically,
    i.e. when a bar's indentation depth exceeds the length of the
    palette, colors will be obtained by wrapping around to the
    beginning of the list.

  BLEND: a blend factor (0..1) which controls how palette colors
    are blended with the main color, prior to possibly blending
    with the frame background color (see `indent-bars-color' for
    information on how blend factors are specified).  A nil value
    causes the palette colors to be used as-is.  A unity value
    causes the palette color to be blended directly with the
    background using any blend factor from `indent-bars-color'.

Note that, for this setting to have any effect, one of REGEXP or
PALETTE is required (the former overriding the latter).  If both
are omitted or nil, all bars will have the same color, based on
MAIN_COLOR (aside possibly from the bar at the current
indentation level, if configured; see
`indent-bars-highlight-current-depth')."
  :type '(choice :tag "Depth Palette"
		 (const :tag "No Depth-Coloring" nil)
		 (plist :tag "Depth-Coloring"
			:options
			((:regexp (regexp :tag "Face regexp"))
			 (:face-bg
			  (boolean
			   :value t
			   :tag "Use Matching Face's Background Colors"))
			 (:palette
			  (repeat :tag "Explicit Color/Face List"
				  (choice (color :tag "Color")
					  (face :tag "Foreground from Face")
					  (cons :tag "Background from Face"
						:format "Background from %v"
						face
						(const :format "\n" :value bg)))))
			 (:blend
			  (float :tag "Blend Fraction into Main Color"
				 :value 0.5
				 :match (lambda (_ val)
					  (and val (<= val 1) (>= val 0)))
				 :type-error
				 "Factor must be between 0 and 1")))))
  :group 'indent-bars-style)

;;;;; Depth Highlighting
(defcustom indent-bars-highlight-current-depth
  '(:pattern ".")			; solid bar, no color change
  "Current indentation depth bar highlight configuration.
Use this to configure optional highlighting of the bar at the
current line's indentation depth level.

Format:

    nil | (:color :face :face-bg :background :blend :palette
           :width :pad :pattern :zigzag)

If nil, no highlighting will be applied to bars at the current
depth of the line at point.  Otherwise, a plist describes what
highlighting to apply, which can include changes to color and/or
bar pattern.  At least one of :blend, :color, :palette, :face,
:width, :pad, :pattern, or :zigzag must be set and non-nil for
this setting to take effect.

By default, the highlighted bar's color will be the same as the
underlying bar color.  With PALETTE, COLOR or FACE set, all bars
at the current depth will be highlighted in the appropriate
color, either from an explicit COLOR, a PALETTE list (see
`indent-bars-color-by-depth'), or, if FACE is set, FACE's
foreground or background color (the latter if FACE-BG is
non-nil).  If PALETTE is provided, it overrides any other
foreground color setting for the current depth highlight bar.  If
BACKGROUND is set to a color, this will be used for the
background color of the current depth bar.

If BLEND is provided, it is a blend fraction between 0 and 1 for
blending the specified highlight color with the
existing (depth-based or main) bar color; see `indent-bars-color'
for its meaning.  BLEND=1 indicates using the full, unblended
highlight color (and is the same as omitting BLEND).

As a special case, if BLEND is provided, but neither COLOR nor
FACE is, BLEND is used as a (presumably distinct) blend factor
between the usual color for that bar and the frame background.
The original colors are specified in `indent-bars-color-by-depth'
or `indent-bars-color'.  In this manner the current-depth
highlight can be made a more (or less) prominent version of the
default coloring.

If any of WIDTH, PAD, PATTERN, or ZIGZAG are set, the stipple bar
pattern at the current level will be altered as well.  Note that
`indent-bars-width-frac', `indent-bars-pad-frac',
`indent-bars-pattern', and `indent-bars-zigzag' will be used as
defaults for any missing values; see these variables.

Note: on terminal, or if `indent-bars-prefer-character' is
non-nil, any stipple appearance parameters will be ignored."
  :type '(choice :tag "Highlighting Options"
	  (const :tag "No Current Highlighting" :value nil)
	  (plist :tag "Highlight Current Depth"
		 :options
		 ((:color (color :tag "Highlight Color"))
		  (:face (face :tag "Color from Face"))
		  (:face-bg (boolean :tag "Use Face's Background Color"))
		  (:background (color :tag "Background Color of Current Bar"))
		  (:blend (float :tag "Blend Fraction into Existing Color")
			  :value 0.5
			  :match (lambda (_ val) (and (<= val 1) (>= val 0)))
			  :type-error "Factor must be between 0 and 1")
		  (:palette
		   (repeat :tag "Explicit Color/Face List"
			   (choice (color :tag "Color")
				   (face :tag "Foreground from Face")
				   (cons :tag "Background from Face"
					 :format "Background from %v"
					 face
					 (const :format "\n" :value bg)))))
		  (:width (float :tag "Bar Width"))
		  (:pad (float :tag "Bar Padding (from left)"))
		  (:pattern (string :tag "Fill Pattern"))
		  (:zigzag (float :tag "Zig-Zag")))))
  :group 'indent-bars)

(defcustom indent-bars-depth-update-delay 0.075
  "Minimum delay time in seconds between depth highlight updates.
Has effect only if `indent-bars-highlight-current-depth' is
non-nil.  Set to 0 for instant depth updates."
  :type 'float
  :group 'indent-bars)

;;;;; Other
(defcustom indent-bars-display-on-blank-lines t
  "Whether to display bars on blank lines."
  :type 'boolean
  :group 'indent-bars)

(defcustom indent-bars-prefer-character nil
  "Use characters instead of stipple to draw bars.
Normally characters are used on terminal only.  A non-nil value
specifies using character bars exclusively.  See
`indent-bars-no-stipple-char'."
  :type 'boolean
  :group 'indent-bars)

(defcustom indent-bars-no-stipple-char ?\│
  "Character to display when stipple is unavailable (as in the terminal)."
  :type 'char
  :group 'indent-bars)

(defcustom indent-bars-no-stipple-char-font-weight nil
  "Font weight to use to draw the character bars.
If non-nil, set the no-stipple character font weight accordingly."
  :type `(choice
          (const :tag "Use Default Weight" nil)
          ,@(mapcar (lambda (item) (list 'const (aref item 1)))
                    font-weight-table))
  :group 'indent-bars)

(defcustom indent-bars-unspecified-bg-color "black"
  "Color to use as the frame background color if unspecified.
Unless actively set, most terminal frames do not have a
background color specified.  This setting controls the background
color to use for color blending in that case."
  :type 'color
  :group 'indent-bars)

(defcustom indent-bars-unspecified-fg-color "white"
  "Color to use as the default foreground color if unspecified."
  :type 'color
  :group 'indent-bars)

(defcustom indent-bars-starting-column nil
  "The starting column on which to display the first bar.
Set to nil, for the default behavior (first bar at the first
indent level) or an integer value for some other column."
  :type '(choice (const :tag "Default: 1st indent position" nil)
		 (integer :tag "Specified column"))
  :group 'indent-bars)

(defcustom indent-bars-spacing-override nil
  "Override for default, major-mode based indentation spacing.
Set only if the default guessed spacing is incorrect.  Becomes
buffer-local automatically."
  :local t
  :type '(choice integer (const :tag "Discover automatically" :value nil))
  :group 'indent-bars)

(defcustom indent-bars-treesit-support nil
  "Whether to enable tree-sitter support (if available)."
  :type 'boolean
  :group 'indent-bars)

;;;;; Color Utilities
(defun indent-bars--frame-background-color()
  "Return the frame background color."
  (let ((fb (frame-parameter nil 'background-color)))
    (cond ((not fb) "white")
	  ((string= fb "unspecified-bg") indent-bars-unspecified-bg-color)
	  (t fb))))

(defun indent-bars--blend-colors (c1 c2 fac)
  "Return a fractional color between two colors C1 and C2.
Each is a string color.  The fractional blend point is the
float FAC, with 1.0 matching C1 and 0.0 C2."
  (apply #'color-rgb-to-hex
	 (cl-mapcar (lambda (a b)
		      (+ (* a fac) (* b (- 1.0 fac))))
		    (color-name-to-rgb c1) (color-name-to-rgb c2))))

(defun indent-bars--colors-from-regexp (regexp &optional face-bg)
  "Return a list of colors (strings) for faces matching REGEXP.
The first capture group in REGEXP will be interpreted as a number
and used to sort the list numerically.  A list of the foreground
color of the matching, sorted faces will be returned, unless
FACE-BG is non-nil, in which case the background color is
returned."
  (mapcar (lambda (x) (funcall (if face-bg #'face-background #'face-foreground)
			       (cdr x) nil t))
          (seq-sort-by #'car
		       (lambda (a b) (cond
				      ((not (numberp b)) t)
				      ((not (numberp a)) nil)
				      (t (< a b))))
                       (delq nil
			     (seq-map
			      (lambda (x)
				(let ((n (symbol-name x)))
				  (if (string-match regexp n)
                                      (cons (string-to-number (match-string 1 n))
					    x))))
                              (face-list))))))

(defun indent-bars--unpack-palette (palette)
  "Process a face or color-based PALETTE."
  (delq nil
	(cl-loop for el in palette
		 collect (cond
			  ((and (consp el) (facep (car el)))
			   (face-background (car el)))
			  ((facep el)
			   (face-foreground el))
			  ((color-defined-p el) el)
			  (t nil)))))
;;;; Style
(defvar-local indent-bars-style nil
  "The `indent-bars-style' struct for the main style.")

(defvar indent-bars--styles nil
  "List of known indent-bars style structs.")

(cl-declaim (optimize (safety 0))) ; no need for type check
(cl-defstruct
    (indent-bars-style
     (:copier nil)
     (:conc-name ibs/)	; Note: ibs/ => indent-bars-style- in this file
     (:constructor nil)
     (:constructor ibs/create
		   ( &optional tag &aux
		     (stipple-face
		      (intern (format "indent-bars%s-face"
				      (if tag (concat "-" tag) "")))))))
  "A style configuration structure for indent-bars."
  ( tag nil :type string
    :documentation "An optional tag to include in face name")
  ;; Colors and Faces
  ( main-color nil :type string
    :documentation "The main bar color")
  ( depth-palette nil
    :documentation "Palette of depth colors.
May be nil, a color string or a vector of colors strings.")
  ( faces nil :type vector
    :documentation "Depth-based faces.")
  ;; Stipple
  ( stipple-face nil :type face
    :documentation "A stipple face to inherit from.")
  ( no-stipple-chars nil
    :documentation "A vector of style non-stipple chars.")
  ;; Current depth remapping
  ( remap nil :type list
    :documentation "An active face-remap cookie.")
  ( current-bg-color nil :type color
    :documentation "The background color of the current depth highlight.")
  ( current-depth-palette nil
    :documentation "Depth palette of current highlight colors.")
  ( current-depth-stipple nil :type list
    :documentation "The stipple pattern for the current depth."))

(defun indent-bars--new-style (&optional tag)
  "Create and record a new style struct with TAG."
  (let ((style (ibs/create tag)))
    (push style indent-bars--styles)
    style))

;;;;; Colors
(defun indent-bars--main-color (style &optional tint tint-blend blend-override)
  "Calculate the main bar color for STYLE.
Uses `indent-bars-color' for color and background blend config.
If TINT and TINT-BLEND are passed, first blend the TINT color
into the main color with the requested blend, prior to blending
into the background color.  If BLEND-OVERRIDE is set, use it
instead of the :blend factor in `indent-bars-color'."
  (cl-destructuring-bind (main &key face-bg blend) (indent-bars--style style "color")
    (let ((col (cond ((facep main)
		      (funcall (if face-bg #'face-background #'face-foreground)
			       main))
		     ((color-defined-p main) main)))
	  (blend (or blend-override blend)))
      (if (and tint tint-blend (color-defined-p tint)) ;tint main color
	  (setq col (indent-bars--blend-colors tint col tint-blend)))
      (if blend				;now blend into BG
	  (setq col (indent-bars--blend-colors
		     col (indent-bars--frame-background-color) blend)))
      col)))

(defun indent-bars--depth-palette (style &optional blend-override)
  "Calculate the palette of depth-based colors (a vector) for STYLE.
If BLEND-OVERRIDE is set, the main color's :blend will be ignored
and this value will be used instead, for blending into the frame
background color.  See `indent-bars-color-by-depth'."
  (when-let ((cbd (indent-bars--style style "color-by-depth")))
    (cl-destructuring-bind (&key regexp face-bg palette blend) cbd
      (let ((colors
	     (cond
	      (regexp
	       (indent-bars--colors-from-regexp regexp face-bg))
	      (palette
	       (indent-bars--unpack-palette palette)))))
	(vconcat
	 (if (or blend blend-override)
	     (mapcar (lambda (c)
		       (indent-bars--main-color style c blend blend-override))
		     colors)
	   colors))))))

(defun indent-bars--current-depth-palette (style)
  "Colors for highlighting the current depth bar for STYLE.
A color or palette (vector) of colors is returned, which may be
nil, in which case no special current depth-coloring is used.
See `indent-bars-highlight-current-depth' for configuration."
  (when-let ((hcd (indent-bars--style style "highlight-current-depth")))
    (cl-destructuring-bind (&key color face face-bg
				 blend palette &allow-other-keys)
	hcd
      (let ((color
	     (cond
	      ((facep face)
	       (funcall (if face-bg #'face-background #'face-foreground)
			face))
	      ((and color (color-defined-p color)) color))))
	(cond
	 ;; An explicit palette
	 (palette
	  (vconcat (indent-bars--unpack-palette palette)))

	 ;; A specified color (possibly to blend in)
	 (color
	  (if (string= color "unspecified-fg")
	      (setq color indent-bars-unspecified-fg-color))
	  (if blend
	      (if-let ((palette (indent-bars--depth-palette style))) ; blend into normal depth palette
		  (vconcat
		   (mapcar (lambda (c)
			     (indent-bars--blend-colors color c blend))
			   palette))
		;; Just blend into main color
		(indent-bars--blend-colors color (ibs/main-color style) blend))
	    color))
	 
	 ;; blend-only without a specified color: re-blend originals with BG
	 (blend
	  (or (indent-bars--depth-palette blend)
	      (indent-bars--main-color style nil nil blend))))))))

(defun indent-bars--get-color (style depth  &optional current-highlight)
  "Return the color appropriate for indentation DEPTH in STYLE.
If CURRENT-HIGHLIGHT is non-nil, return the appropriate highlight
color, if setup (see `indent-bars-highlight-current-depth')."
  (let* ((palette (or (and current-highlight
			   (ibs/current-depth-palette style))
		      (ibs/depth-palette style))))
    (cond
     ((vectorp palette)
      (aref palette (mod (1- depth) (length palette))))
     (palette)  ; single color
     (t (ibs/main-color style)))))

;;;;; Faces
(defun indent-bars--create-stipple-face (w h rot)
  "Create and set the stipple face.
Create for character size W x H with offset ROT."
  `((t ( :inherit nil :stipple ,(indent-bars--stipple w h rot)
	 ,@(when indent-bars-no-stipple-char-font-weight
             `(:weight ,indent-bars-no-stipple-char-font-weight))))))

(defun indent-bars--calculate-face-spec (style depth)
  "Calculate the face spec for bar at DEPTH in STYLE.
DEPTH starts at 1."
  `((t . ( :inherit ,(ibs/stipple-face style)
	   :foreground ,(indent-bars--get-color style depth)))))

(defun indent-bars--create-faces (style num &optional redefine)
  "Create bar faces up to depth NUM for STYLE.
Redefine them if REDEFINE is non-nil."
  (vconcat
   (cl-loop
    with tag = (ibs/tag style)
    with tag-s = (if tag (format "-%s" tag) "")
    for i from 1 to num
    for face = (intern (format "indent-bars%s-%d" tag-s i)) do
    (if (and redefine (facep face)) (face-spec-reset-face face))
    (face-spec-set face (indent-bars--calculate-face-spec style i))
    collect face)))

(defsubst indent-bars--face (style depth)
  "Return the bar face for bar DEPTH in STYLE.
The face is created if necessary."
  (when (> depth (length (ibs/faces style)))
    (setf (ibs/faces style)
	  (indent-bars--create-faces style depth)))
  (aref (ibs/faces style) (1- depth)))

;;;;; No stipple characters (e.g. terminal)
(defun indent-bars--no-stipple-char (style depth)
  "Return the no-stipple bar character for DEPTH in STYLE."
  (when (> depth (length (indent-bars-style-no-stipple-chars style)))
    (setf (indent-bars-style-no-stipple-chars style)
	  (indent-bars--create-no-stipple-chars style depth)))
  (aref (ibs/no-stipple-chars style) (1- depth)))

(defun indent-bars--create-no-stipple-chars (style num)
  "Setup bar characters for bar faces up to depth NUM in STYLE.
Used when not using stipple display (on terminal, or by request;
see `indent-bars-prefer-character')."
  (vconcat
   (nreverse
    (cl-loop
     with chars = (ibs/no-stipple-chars style)
     with l = (length chars)
     for d from num downto 1
     collect
     (or (and (< d l) (aref chars (1- d)))
	 (propertize (string indent-bars-no-stipple-char)
		     'face (indent-bars--face style d)))))))

;;;;; Package
(defmacro indent-bars--alt-custom
    (alt opt alt-description std-val &optional add-inherit no-inherit &rest r)
  "Define a custom ALT variable for option OPT.
The new custom options default value is set to STD-VAL.  This
creates a new variable indent-bars-alt-opt, based on
indent-bars-opt (referred to as the parent variable).
ALT-DESCRIPTION will be used to identify the alternate variable
in the customize interface.

If ADD-INHERIT is non-nil, expand the type to a cons:

  (inherit . type)

the former based on the value of NO-INHERIT.  ADD-INHERIT makes
sense only for composite types with multiple underlying options,
some of which can be omitted (e.g. plists).

By default, all variables are configured to inherit unspecified
or omitted underlying options from their composite parent
variable.  If NO-INHERIT is non-nil, the variable will be
configured not to inherit any missing values.

Additional `defcustom` keyword arguments can be given as R."
  (require 'cus-edit)
  (let* ((optname (symbol-name opt))
	 (group (intern (concat "indent-bars-" alt "-style")))
	 (symname (concat "indent-bars-" optname))
	 (sym (intern (concat "indent-bars-" optname)))
	 (tsym (intern (concat "indent-bars-" alt "-" optname)))
	 (type (custom-variable-type sym)))
    ;; Add an unspecified choice
    (let ((unspec `(const :tag ,(concat "No-value (use parent " optname ")")
			  unspecified))
	  (rest type))
      (if (eq (car type) 'choice)
	  (progn			; add a choice option
	    (when-let ((tag-pos (member :tag type)))
	      (setq rest (cdr tag-pos))) ;after tag
	    (setcdr rest (push unspec (cdr rest))))
	(setq type `(choice ,unspec ,type))))
    ;; Add leading inherit flag, if needed
    (when (or no-inherit add-inherit)
      (setq type
	    `(cons :tag ,(concat alt-description " Style")
		   (choice :tag
			   ,(concat "Inherit missing data from `indent-bars-"
				    optname "'")
			   (const :tag "Do not inherit" no-inherit)
			   (const :tag "Inherit" inherit))
		   ,type)
	    std-val `( ,(if no-inherit 'no-inherit 'inherit) . ,std-val )))
    `(defcustom ,tsym ',std-val
       ,(concat "Alternate " alt-description " version of `" symname "'.")
       :type ',type
       :link '(variable-link ,sym)
       :group ',group
       ,@r)))

(defsubst indent-bars--alt (name alt)
  "Find the symbol value of NAME, with alternate style ALT.
NAME is a string, and ALT and be a string or nil."
  (intern (format "indent-bars%s-%s"
		  (if alt (concat "-" alt) "") name)))

(defun indent-bars--style (style name)
  "Return the value of style variable NAME for STYLE.
Determines variables to use based on the style tag.  For style
variable values of the form (\\='inherit|\\='no-inherit . plist),
inheritance of the plist is handled.  If style is the symbol
\\='any, return the first non-nil value for all styles in
`indent-bars--styles'."
  (if (eq style 'any)
      (cl-some (lambda (s) (indent-bars--style1 s name))
	       indent-bars--styles)
    (indent-bars--style1 style name)))


(defun indent-bars--style1 (style name)
  "Return the value of style variable NAME for STYLE."
  (let* ((tag (indent-bars-style-tag style))
	 (sym (indent-bars--alt name tag))
	 (val (symbol-value sym))
	 (inhrt t))			; inherit by default
    (when tag
      ;; Check for the ([no-]inherit . actual-val) form
      (when (and (consp val) (memq (car val) '(inherit no-inherit)))
	(setq inhrt (and (car val) (not (eq (car val) 'no-inherit)))
	      val (cdr val)))
      (when-let (((and inhrt (plistp val) (keywordp (car val)))) ;only :key plists
		 (main-val (symbol-value (indent-bars--alt name nil)))
		 ((plistp main-val)))
	(setq val (map-merge 'plist main-val val))))
    val))

;;;; Indentation and Drawing
(defvar-local indent-bars-spacing nil)
(defvar-local indent-bars--offset nil)
(defvar-local indent-bars--no-stipple nil)

(defsubst indent-bars--depth (len)
  "Number of possible bars for initial blank string of length LEN.
Note that the first bar is expected at `indent-bars-starting-column'."
  (setq len (- len indent-bars--offset))
  (cond ((>= len indent-bars-spacing) (/ (1+ len) indent-bars-spacing))
	((> len 0) 1)
	(t 0)))

(defvar indent-bars--update-depth-function nil)
(defun indent-bars--current-indentation-depth (&optional on-bar)
  "Calculate current indentation depth.
If ON-BAR is non-nil, report a line with content beginning on a
bar position at that position.  If
`indent-bars--update-depth-function' is non-nil, it will be
called with the indentation depth, and can return an updated
depth."
  (let* ((c (current-indentation))
	 (d (indent-bars--depth c)))
    (if indent-bars--update-depth-function
	(setq d (funcall indent-bars--update-depth-function d)))
    (if (and on-bar (= c (+ indent-bars--offset (* d indent-bars-spacing))))
	(1+ d) d)))

(defun indent-bars--blank-string (style off nbars bar-from
					&optional width
					switch-after style2)
  "Return a blank string with bars displayed, using style STYLE.
OFF is the character offset within the string to draw the first
bar, NBARS is the desired number of bars to add, and BAR-FROM is
the starting index of the first bar (>=1).  WIDTH is the total
string width to return, right padding with space if needed.

If SWITCH-AFTER is supplied and is an integer, switch from STYLE
to STYLE2 after drawing that many bars.  If it is t, use
STYLE2 for all bars.

Bars are displayed using stipple properties or characters; see
`indent-bars-prefer-character'."
  (concat (make-string off ?\s)
	  (string-join
	   (cl-loop
	    for i from 0 to (1- nbars)
	    for depth = (+ bar-from i)
	    for sty = (if switch-after
			  (if (or (eq switch-after t)
				  (>= i switch-after))
			      style2
			    style)
			style)
	    collect (if indent-bars--no-stipple
			(indent-bars--no-stipple-char sty depth)
		      (propertize " " 'face (indent-bars--face sty depth))))
	   (make-string (1- indent-bars-spacing) ?\s))
	  (if width
	      (make-string (- width
			      (+ off nbars (* (1- nbars) (1- indent-bars-spacing))))
			   ?\s))))

(defun indent-bars--tab-display (style p off bar-from max &rest r)
  "Display up to MAX bars on the tab at P, offseting them by OFF.
Bars are spaced by `indent-bars-spacing' and displayed with style
STYLE.  BAR-FROM is the bar number for the first bar.  Other
arguments R are passed to `indent-bars--blank-string'.  Returns
the number of bars actually displayed."
  (let* ((nb (min max (/ (- tab-width off -1) indent-bars-spacing)))
	 (str (apply #'indent-bars--blank-string style off nb
		     bar-from tab-width r)))
    (put-text-property p (+ p 1) 'display str)
    nb))

(defun indent-bars--draw-line (style nbars start end &optional
				     invent switch-after style2)
  "Draw NBARS bars on the line between positions START and END.
Bars are drawn in style STYLE, `indent-bars-style' by default
START is assumed to be on a line beginning position.  Drawing
starts at a column determined by `indent-bars-starting-column'.
Tabs at the line beginning have appropriate display properties
applied if `indent-tabs-mode' is enabled.

If SWITCH-AFTER is an integer, switch from STYLE to STYLE2
after drawing that many bars.  If it is t, use STYLE2
exclusively.

If INVENT is non-nil and the line's length is insufficient to
display all NBARS bars (whether by replacing tabs or adding
properties to existing non-tab whitespace), bars will be
\"invented\".  That is, the line's final newline, which is (only
in this case) expected to be located at END, will have its
display properties set to fill out the remaining bars, if any are
needed."
  (let* ((tabs (when (and indent-tabs-mode
			  (save-excursion
			    (goto-char start) (looking-at "^\t+")))
		 (- (match-end 0) (match-beginning 0))))
	 (vp indent-bars--offset)
	 (style (or style indent-bars-style))
	 (bar 1) prop fun tnum bars-drawn)
    (when tabs				; deal with initial tabs
      (while (and (<= bar nbars) (< (setq tnum (/ vp tab-width)) tabs))
	(setq bars-drawn
	      (indent-bars--tab-display style (+ start tnum) (mod vp tab-width)
					bar (- nbars bar -1)
					switch-after style2))
	(when (integerp switch-after)
	  (cl-decf switch-after bars-drawn)
	  (if (<= switch-after 0) (setq switch-after t))) ; switch the rest
	(cl-incf bar bars-drawn)
	(cl-incf vp (* bars-drawn indent-bars-spacing)))
      (cl-incf start (+ (mod vp tab-width) (/ vp tab-width))))
    (when (<= bar nbars)		; still bars to show
      (if indent-bars--no-stipple
	  (setq prop 'display fun #'indent-bars--no-stipple-char)
	(setq prop 'face fun #'indent-bars--face))
      (let ((pos (if tabs start (+ start indent-bars--offset))))
	(while (and (<= bar nbars) (< pos end))
	  (put-text-property pos (1+ pos)
			     prop (funcall fun
					   (cond ((integerp switch-after)
						  (cl-decf switch-after)
						  (if (<= switch-after 0)
						      (setq switch-after t))
						  style2)
						 ((eq switch-after t) style2)
						 (t style))
					   bar))
	  (cl-incf bar)
	  (cl-incf pos indent-bars-spacing))
	(if (and invent (<= bar nbars)) ; STILL bars to show: invent them
	    (put-text-property
	     end (1+ end) 'display
	     (concat (indent-bars--blank-string
		      style (- pos end) (- nbars bar -1) bar nil
		      switch-after style2)
		     "\n")))))))

;;;; Stipple Display
(defsubst indent-bars--block (n)
  "Create a block of N low-order 1 bits."
  (- (ash 1 n) 1))

(defun indent-bars--stipple-rot (w)
  "Return the stipple rotation for pattern with W for the current window."
  (mod (car (window-edges nil t nil t)) w))

(defun indent-bars--rot (num w n)
  "Shift number NUM of W bits up by N bits, carrying around to the low bits.
N should be strictly less than W and the returned value will fit
within W bits."
  (logand (indent-bars--block w) (logior (ash num n) (ash num (- n w)))))

(defun indent-bars--row-data (w pad rot width-frac)
  "Calculate stipple row data to fit in character of width W.
The width of the pattern of filled pixels is determined by
WIDTH-FRAC.  The pattern itself is shifted up by PAD bits (which
shifts the pattern to the right, for positive values of PAD).
Subsequently, the value is shifted up (with W-bit wrap-around) by
ROT bits, and returned.  ROT is the starting bit offset of a
character within the closest stipple repeat to the left; i.e. if
pixel 1 of the stipple aligns with pixel 1 of the chacter, ROT=0.
ROT should be less than W."
  (let* ((bar-width (max 1 (round (* w width-frac))))
	 (num (indent-bars--rot
	       (ash (indent-bars--block bar-width) pad) w rot)))
    (apply #'unibyte-string
	   (cl-loop for boff = 0 then (+ boff 8) while (< boff w)
		    for nbits = (min 8 (- w boff))
		    collect (ash (logand num
					 (ash (indent-bars--block nbits) boff))
				 (- boff))))))

;; ** Notes on the stipples:
;;
;; indent-bars by default uses a selectively-revealed stipple pattern
;; with a width equivalent to the (presumed fixed) width of individual
;; characters to efficiently draw bars.  A stipple pattern is drawn as
;; a fixed repeating bit pattern, with its lowest bits and earlier
;; bytes leftmost.  It is drawn with respect to the *entire frame*,
;; with its first bit aligned with the first (leftmost) frame pixel.
;; 
;; Turning on :stipple for a character merely "opens a window" on that
;; frame-filling, repeating stipple pattern.  Since the pattern starts
;; outside the body (in literally the first frame pixel, typically in
;; the fringe), you must consider the shift between the first pixel of
;; a character and the first pixel of the repeating stipple block at
;; that pixel position or above:
;; 
;;     |<-frame edge |<---buffer/window edge
;;     |<--w-->|<--w-->|<--w-->|     w = pattern width
;;     | marg/fringe |<-chr->|     chr = character width = w
;;             |<-g->|               g = gutter offset of chr start, g<w
;;
;; Or, when the character width exceeds the margin/fringe offset:
;; 
;;     |<-frame edge |<---buffer/window edge
;;     |<--------w-------->|<---------w-------->|
;;     | marg/fringe |<-------chr------->|
;;     |<-----g----->|
;;
;; So g = (mod marg/fringe w).
;; 
;; When the block/zigzag/whatever pattern is made, to align with
;; characters, it must get shifted up (= right) by g bits, with carry
;; over (wrap) around w=(window-font-width) bits (i.e the width of the
;; bitmap).  The byte/bit pattern is first-lowest-leftmost.
;;
;; Note that different window sides will often have different g
;; values, which means the same bitmap cannot work for the buffer in
;; both windows.  So showing the same buffer side by side can lead to
;; mis-alignment in the non-active buffer.
;;
;; Solution: use window hooks to update the stipple bitmap as focus or
;; windows change.  So at least the focused buffer looks correct.  If
;; this is insufficient, use C-x 4 c
;; (clone-indirect-buffer-other-window).  A bug in Emacs <29 means
;; `face-remapping-alist' is unintentionally shared between indirect
;; and master buffers.  Fixed in Emacs 29.

(defun indent-bars--stipple (w h rot
			       &optional width-frac pad-frac pattern zigzag)
  "Calculate stipple bitmap pattern for char width W and height H.
ROT is the number of bits to rotate the pattern around to the
right (with wrap).

Uses configuration variables `indent-bars-width-frac',
`indent-bars-pad-frac', `indent-bars-pattern', and
`indent-bars-zigzag', unless PAD-FRAC, WIDTH-FRAC, PATTERN,
and/or ZIGZAG are set (the latter overriding the config
variables, which see)."
  (unless (or (not (display-graphic-p)) indent-bars-prefer-character)
    (let* ((rowbytes (/ (+ w 7) 8))
	   (pattern (or pattern indent-bars-pattern))
	   (pat (if (< h (length pattern)) (substring pattern 0 h) pattern))
	   (plen (length pat))
	   (chunk (/ (float h) plen))
	   (small (floor chunk))
	   (large (ceiling chunk))
	   (pad-frac (or pad-frac indent-bars-pad-frac))
	   (pad (round (* w pad-frac)))
	   (zigzag (or zigzag indent-bars-zigzag))
	   (zz (if zigzag (round (* w zigzag)) 0))
	   (zeroes (make-string rowbytes ?\0))
	   (width-frac (or width-frac indent-bars-width-frac))
	   (dlist (if (and (= plen 1) (not (string= pat " "))) ; solid bar
		      (list (indent-bars--row-data w pad rot width-frac)) ; one row
		    (cl-loop for last-fill-char = nil then x
			     for x across pat
			     for n = small then (if (and (/= x ?\s) (= n small))
						    large
						  small)
			     for zoff = zz then (if (and last-fill-char
							 (/= x ?\s)
							 (/= x last-fill-char))
						    (- zoff) zoff)
			     for row = (if (= x ?\s) zeroes
					 (indent-bars--row-data w (+ pad zoff)
								rot width-frac))
			     append (cl-loop repeat n collect row)))))
      (list w (length dlist) (string-join dlist)))))

;;;; Font Lock
(defvar-local indent-bars--font-lock-keywords nil)
(defvar indent-bars--font-lock-blank-line-keywords nil)

(defvar indent-bars-orig-unfontify-region nil)
(defun indent-bars--unfontify (beg end)
  "Unfontify region between BEG and END.
Removes the display properties in addition to the normal managed
font-lock properties."
  (let ((font-lock-extra-managed-props
         (append '(display) font-lock-extra-managed-props)))
    (funcall indent-bars-orig-unfontify-region beg end)))

;; local variables to be dynamically bound
(defvar-local indent-bars--switch-after nil)

(defun indent-bars--display (&optional style switch-after style2)
  "Draw indentation bars based on line contents.
STYLE, SWITCH-AFTER and STYLE2 are as in
`indent-bars--draw-line'.  If STYLE is not passed, uses
`indent-bars-style' for drawing."
  (let* ((b (match-beginning 1))
	 (e (match-end 1))
	 (n (save-excursion
	      (goto-char b)
	      (indent-bars--current-indentation-depth))))
    (when (> n 0) (indent-bars--draw-line style n b e nil
					  switch-after style2))))

(defsubst indent-bars--context-bars (end)
  "Maximum number of bars at point and END.
Moves point."
  (max (indent-bars--current-indentation-depth)
       (progn
	 (goto-char (1+ end))		; end is always eol
	 (indent-bars--current-indentation-depth))))

(defun indent-bars--handle-blank-lines (&optional style switch-after style2)
  "Display the appropriate bars on regions of one or more blank-only lines.
The region is the full match region of the last match.  Only
called by font-lock if `indent-bars-display-on-blank-lines' is
non-nil.  Called on complete multi-line blank line regions.  Uses
the surrounding line indentation to determine additional bars to
display on each line, using `indent-bars--draw-line'.  STYLE,
SWITCH-AFTER and STYLE2 are as in `indent-bars--draw-line'.

Note: blank lines at the very beginning or end of the buffer are
not indicated, even if they otherwise would be.  This function is
configured by default in `indent-bars--handle-blank-lines-form'."
  (let* ((beg (match-beginning 0))
	 (end (match-end 0))
	 ctxbars)
    (save-excursion
      (goto-char (1- beg))
      (beginning-of-line 1)
      (when (> (setq ctxbars (indent-bars--context-bars end)) 0)
	(goto-char beg)
	(while (< (point) end) ;note: end extends 1 char beyond blank line range
	  (let* ((bp (line-beginning-position))
		 (ep (line-end-position))
		 (pm (point-max)))
	    (unless (= ep pm)
	      (indent-bars--draw-line style ctxbars bp ep 'invent
				      switch-after style2))
	    (beginning-of-line 2)))))))

(defvar font-lock-beg) (defvar font-lock-end) ; Dynamic font-lock variables!
(defun indent-bars--extend-blank-line-regions ()
  "Extend the region about to be font-locked to include stretches of blank lines."
  ;; (message "request to extend: %d->%d" font-lock-beg font-lock-end)
  (let ((changed nil) (chars " \t\n"))
    (goto-char font-lock-beg)
    (when (< (skip-chars-backward chars) 0)
      (unless (bolp) (beginning-of-line 2)) ; spaces at end don't count
      (when (< (point) font-lock-beg)
	(setq changed t font-lock-beg (point))))
    (goto-char font-lock-end)
    (when (> (skip-chars-forward chars) 0)
      (unless (bolp) (beginning-of-line 1))
      (when (> (point) font-lock-end)
	(setq changed t font-lock-end (point))))
    ;; (if changed (message "expanded to %d->%d" font-lock-beg font-lock-end))
    changed))

;;;; Current indentation depth highlighting
(defvar-local indent-bars--current-depth 0)

(defun indent-bars--current-bg-color (style)
  "Return the current bar background color appropriate for STYLE."
  (when-let ((hcd
	      (indent-bars--style style "highlight-current-depth")))
    (plist-get hcd :background)))

(defun indent-bars--current-depth-stipple (style &optional w h rot)
  "Return the current depth stipple highlight (if any) for STYLE.
One of the keywords :width, :pad, :pattern, or :zigzag must be
set in `indent-bars-highlight-current-depth' config.  W, H, and
ROT are as in `indent-bars--stipple', and have similar default values."
  (cl-destructuring-bind (&key width pad pattern zigzag &allow-other-keys)
      (indent-bars--style style "highlight-current-depth")
    (when (or width pad pattern zigzag)
      (let* ((w (or w (window-font-width)))
	     (h (or h (window-font-height)))
	     (rot (or rot (indent-bars--stipple-rot w))))
	(indent-bars--stipple w h rot width pad pattern zigzag)))))

(defun indent-bars--update-current-depth-highlight (depth)
  "Update highlight for the current DEPTH.
Works by remapping the appropriate indent-bars[-style]-N face for
all styles in the `indent-bars--styles' list.  DEPTH should be
greater than zero."
  (dolist (s indent-bars--styles)
    (if (ibs/remap s)			; out with the old
	(face-remap-remove-relative (ibs/remap s)))
    (let* ((face (indent-bars--face s depth))
	   (hl-col (and (ibs/current-depth-palette s)
			(indent-bars--get-color depth 'highlight)))
	   (hl-bg (ibs/current-bg-color s)))
      (when (or hl-col hl-bg (ibs/current-depth-stipple s))
	(setf (ibs/remap s)
	      (apply #'face-remap-add-relative face
		     `(,@(when hl-col `(:foreground ,hl-col))
		       ,@(when hl-bg `(:background ,hl-bg))
		       ,@(when-let ((st (ibs/current-depth-stipple s)))
			   `(:stipple ,st)))))))))

(defvar-local indent-bars--highlight-timer nil)
(defun indent-bars--highlight-current-depth ()
  "Refresh current indentation depth highlight.
Rate limit set by `indent-bars-depth-update-delay'."
  (let* ((depth (indent-bars--current-indentation-depth 'on-bar)))
    (when (and depth (not (= depth indent-bars--current-depth)) (> depth 0))
      (setq indent-bars--current-depth depth)
      (if (zerop indent-bars-depth-update-delay)
	  (indent-bars--update-current-depth-highlight depth)
	(if-let ((tmr indent-bars--highlight-timer))
	    (progn
	      (timer-set-function
	       tmr #'indent-bars--update-current-depth-highlight (list depth))
	      (timer-set-time
	       tmr (time-add (current-time) indent-bars-depth-update-delay))
	      (unless (memq tmr timer-list) (timer-activate tmr)))
	  (setq indent-bars--highlight-timer
		(run-with-timer
		 indent-bars-depth-update-delay nil
		 #'indent-bars--update-current-depth-highlight depth)))))))

;;;; Text scaling and window hooks
(defvar-local indent-bars--remap-stipple nil)
(defvar-local indent-bars--gutter-rot 0)
(defun indent-bars--window-change (win)
  "Update the stipple for buffer in window WIN, if selected."
  (when (eq win (selected-window))
    (let* ((w (window-font-width))
	   (rot (indent-bars--stipple-rot w)))
      (when (/= indent-bars--gutter-rot rot)
	(setq indent-bars--gutter-rot rot)
	(indent-bars--resize-stipple w rot)))))

(defun indent-bars--resize-stipple (&optional w rot)
  "Recreate stipple(s) with updated size.
W is the optional `window-font-width' and ROT is the number of
bits to rotate the pattern.  If W and ROT are not passed they
will be calculated."
  (dolist (s indent-bars--styles)
    (if (ibs/remap s)
	(face-remap-remove-relative (ibs/remap s)))
    (let* ((w (or w (window-font-width)))
	   (rot (or rot (indent-bars--stipple-rot w)))
	   (h (window-font-height)))
      (setf (ibs/remap s)
	    (face-remap-add-relative
	     (ibs/stipple-face s)
	     :stipple (indent-bars--stipple w h rot)))
      (when (ibs/current-depth-stipple s)
	(setf (ibs/current-depth-stipple s)
	      (indent-bars--current-depth-stipple s w h rot))
	(setq indent-bars--current-depth 0)
	(indent-bars--highlight-current-depth)))))

;;;; Setup and mode
(defun indent-bars--guess-spacing ()
  "Get indentation spacing of current buffer.
Adapted from `highlight-indentation-mode'."
  (cond
   (indent-bars-spacing-override)
   ((and (derived-mode-p 'python-mode) (boundp 'py-indent-offset))
    py-indent-offset)
   ((and (derived-mode-p 'python-mode) (boundp 'python-indent-offset))
    python-indent-offset)
   ((and (derived-mode-p 'ruby-mode) (boundp 'ruby-indent-level))
    ruby-indent-level)
   ((and (derived-mode-p 'scala-mode) (boundp 'scala-indent:step))
    scala-indent:step)
   ((and (derived-mode-p 'scala-mode) (boundp 'scala-mode-indent:step))
    scala-mode-indent:step)
   ((and (or (derived-mode-p 'scss-mode) (derived-mode-p 'css-mode))
	 (boundp 'css-indent-offset))
    css-indent-offset)
   ((and (derived-mode-p 'nxml-mode) (boundp 'nxml-child-indent))
    nxml-child-indent)
   ((and (derived-mode-p 'coffee-mode) (boundp 'coffee-tab-width))
    coffee-tab-width)
   ((and (derived-mode-p 'js-mode) (boundp 'js-indent-level))
    js-indent-level)
   ((and (derived-mode-p 'js2-mode) (boundp 'js2-basic-offset))
    js2-basic-offset)
   ((and (derived-mode-p 'sws-mode) (boundp 'sws-tab-width))
    sws-tab-width)
   ((and (derived-mode-p 'web-mode) (boundp 'web-mode-markup-indent-offset))
    web-mode-markup-indent-offset)
   ((and (derived-mode-p 'web-mode) (boundp 'web-mode-html-offset)) ; old var
    web-mode-html-offset)
   ((and (local-variable-p 'c-basic-offset) (numberp c-basic-offset))
    c-basic-offset)
   ((and (derived-mode-p 'yaml-mode) (boundp 'yaml-indent-offset))
    yaml-indent-offset)
   ((and (derived-mode-p 'elixir-mode) (boundp 'elixir-smie-indent-basic))
    elixir-smie-indent-basic)
   ((and (derived-mode-p 'lisp-data-mode) (boundp 'lisp-body-indent))
    lisp-body-indent)
   ((and (derived-mode-p 'cobol-mode) (boundp 'cobol-tab-width))
    cobol-tab-width)
   ((or (derived-mode-p 'go-ts-mode) (derived-mode-p 'go-mode))
    tab-width)
   ((and (boundp 'standard-indent) standard-indent))
   (t 4))) 				; backup

(defvar indent-bars--display-form
  '(indent-bars--display))
(defvar indent-bars--handle-blank-lines-form
  '(indent-bars--handle-blank-lines))
(defun indent-bars--setup-font-lock ()
  "Setup font lock keywords and functions for indent-bars."
  (unless (eq font-lock-unfontify-region-function #'indent-bars--unfontify)
    (setq indent-bars-orig-unfontify-region font-lock-unfontify-region-function))
  (setq-local font-lock-unfontify-region-function #'indent-bars--unfontify)
  (setq indent-bars--font-lock-keywords ; basic blank prefix detection
	`((,(rx-to-string `(seq bol
				(group
				 ,(if (not indent-tabs-mode)
				      `(>= ,(1+ indent-bars--offset) ?\s)
				    '(+ (any ?\t ?\s))))
				(not (any ?\t ?\s ?\n))))
	   (1 ,indent-bars--display-form))))
  (font-lock-add-keywords nil indent-bars--font-lock-keywords t)
  (if indent-bars-display-on-blank-lines
      (let ((re (rx bol (* (or ?\s ?\t ?\n)) ?\n))) ; multi-line blank regions
	(setq indent-bars--font-lock-blank-line-keywords
	      `((,re (0 ,indent-bars--handle-blank-lines-form))))
	(font-lock-add-keywords nil indent-bars--font-lock-blank-line-keywords t)
	(add-hook 'font-lock-extend-region-functions
		  #'indent-bars--extend-blank-line-regions 95 t))))

(declare-function indent-bars-ts-setup "indent-bars-ts")
(defun indent-bars--initialize-style (style)
  "Initialize STYLE."
  ;; Colors
  (setf (ibs/main-color style)
	(indent-bars--main-color style)
	(ibs/depth-palette style)
	(indent-bars--depth-palette style)
	(ibs/current-depth-palette style)
	(indent-bars--current-depth-palette style)
	
	(ibs/faces style) (indent-bars--create-faces style 7 'reset)
	(ibs/no-stipple-chars style) (indent-bars--create-no-stipple-chars style 7))
  
  ;; Faces/stipple
  (face-spec-set (ibs/stipple-face style)
		 (indent-bars--create-stipple-face
		  (frame-char-width) (frame-char-height)
		  (indent-bars--stipple-rot (frame-char-width))))
  
  ;; Current depth highlight faces/stipple
  (when (indent-bars--style style "highlight-current-depth")
    (setf (ibs/current-bg-color style)
	  (indent-bars--current-bg-color style)
	  (ibs/current-depth-stipple style)
	  (indent-bars--current-depth-stipple style))))

(defun indent-bars-setup ()
  "Setup all face, color, bar size, and indentation info for the current buffer."
  ;; Spacing
  (setq indent-bars-spacing (indent-bars--guess-spacing)
	indent-bars--offset (or indent-bars-starting-column indent-bars-spacing))

  ;; No Stipple (e.g. terminal)
  (setq indent-bars--no-stipple
	(or (not (display-graphic-p)) indent-bars-prefer-character))

  ;; Style (color + stipple)
  (indent-bars--initialize-style	; default style
   (setq indent-bars-style (indent-bars--new-style)))

  ;; Window state: selection/size
  (add-hook 'window-state-change-functions #'indent-bars--window-change nil t)

  ;; Resize
  (add-hook 'text-scale-mode-hook #'indent-bars--resize-stipple nil t)
  (indent-bars--resize-stipple)		; just in case

  ;; Treesitter
  (if indent-bars-treesit-support (indent-bars-ts-setup)) ; autoloads

  ;; Current depth
  (when (indent-bars--style 'any "highlight-current-depth")
    (add-hook 'post-command-hook
	      #'indent-bars--highlight-current-depth nil t)
    (setq indent-bars--current-depth 0)
    (indent-bars--highlight-current-depth))
  
  ;; Font-lock
  (indent-bars--setup-font-lock)
  (font-lock-flush))

(defun indent-bars-teardown ()
  "Tears down indent-bars."
  (dolist (s indent-bars--styles)
    (if (ibs/remap s)
	(face-remap-remove-relative (ibs/remap s)))
    (face-spec-set (ibs/stipple-face s) nil 'reset)
    (cl-loop for f in (ibs/faces s)
	     do (face-spec-set f nil 'reset)))
  
  (font-lock-remove-keywords nil indent-bars--font-lock-keywords)
  (font-lock-remove-keywords nil indent-bars--font-lock-blank-line-keywords)
  (font-lock-flush)
  (font-lock-ensure)
  
  (when indent-bars-orig-unfontify-region
    (setq font-lock-unfontify-region-function
	  indent-bars-orig-unfontify-region))
  (setq indent-bars--gutter-rot 0
	indent-bars--current-depth 0
	indent-bars--styles nil)
  (remove-hook 'text-scale-mode-hook #'indent-bars--resize-stipple t)
  (remove-hook 'post-command-hook #'indent-bars--highlight-current-depth t)
  (remove-hook 'font-lock-extend-region-functions
	       #'indent-bars--extend-blank-line-regions t))

(defun indent-bars-reset ()
  "Reset indent-bars config."
  (interactive)
  (indent-bars-teardown)
  (indent-bars-setup))

(defun indent-bars-setup-and-remove ()
  "Setup indent bars and remove from `after-make-frame-functions'."
  (remove-hook 'after-make-frame-functions #'indent-bars-setup-and-remove)
  (indent-bars-setup))

(defvar indent-bars-mode)
;;;###autoload
(define-minor-mode indent-bars-mode
  "Indicate indentation with configurable bars."
  :global nil
  :group 'indent-bars
  (if indent-bars-mode
      (if (and (daemonp) (not (frame-parameter nil 'client)))
	  (let ((buf (current-buffer))) ;careful with frameless daemon emacs
	    (add-hook 'after-make-frame-functions
		      (lambda () (with-current-buffer buf
				   (indent-bars-setup-and-remove)))
		      nil t))
	(indent-bars-setup))
    (indent-bars-teardown)))

(provide 'indent-bars)

;;; indent-bars.el ends here
;; Local Variables:
;; read-symbol-shorthands: (("ibs/" . "indent-bars-style-"))
;; End: