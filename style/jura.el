;;; jura.el --- AUCTeX style for `jura.cls'  -*- lexical-binding: t; -*-

;; Copyright (C) 2004, 2020 Free Software Foundation, Inc.

;; Author: Frank Küster <frank@kuesterei.ch>
;; Maintainer: auctex-devel@gnu.org
;; Keywords: tex

;; This file is part of AUCTeX.

;; AUCTeX is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the
;; Free Software Foundation; either version 3, or (at your option) any
;; later version.

;; AUCTeX is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This file adds support for `jura.cls'.

;;; Code:

(require 'tex)

(TeX-add-style-hook
 "jura"
 (lambda ()
   (TeX-run-style-hooks "alphanum"))
 TeX-dialect)

;; Local Variables:
;; coding: utf-8
;; End: