;;; xcb-xinerama.el --- X11 Xinerama extension  -*- lexical-binding: t -*-

;; Copyright (C) 2015-2024 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file was generated by 'el_client.el' from 'xinerama.xml',
;; which you can retrieve from <git://anongit.freedesktop.org/xcb/proto>.

;;; Code:

(require 'xcb-types)

(defconst xcb:xinerama:-extension-xname "XINERAMA")
(defconst xcb:xinerama:-extension-name "Xinerama")
(defconst xcb:xinerama:-major-version 1)
(defconst xcb:xinerama:-minor-version 1)

(require 'xcb-xproto)

(defclass xcb:xinerama:ScreenInfo
  (xcb:-struct)
  ((x-org :initarg :x-org :type xcb:INT16)
   (y-org :initarg :y-org :type xcb:INT16)
   (width :initarg :width :type xcb:CARD16)
   (height :initarg :height :type xcb:CARD16)))

(defclass xcb:xinerama:QueryVersion
  (xcb:-request)
  ((~opcode :initform 0 :type xcb:-u1)
   (major :initarg :major :type xcb:CARD8)
   (minor :initarg :minor :type xcb:CARD8)))
(defclass xcb:xinerama:QueryVersion~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (major :initarg :major :type xcb:CARD16)
   (minor :initarg :minor :type xcb:CARD16)))

(defclass xcb:xinerama:GetState
  (xcb:-request)
  ((~opcode :initform 1 :type xcb:-u1)
   (window :initarg :window :type xcb:WINDOW)))
(defclass xcb:xinerama:GetState~reply
  (xcb:-reply)
  ((state :initarg :state :type xcb:BYTE)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (window :initarg :window :type xcb:WINDOW)))

(defclass xcb:xinerama:GetScreenCount
  (xcb:-request)
  ((~opcode :initform 2 :type xcb:-u1)
   (window :initarg :window :type xcb:WINDOW)))
(defclass xcb:xinerama:GetScreenCount~reply
  (xcb:-reply)
  ((screen-count :initarg :screen-count :type xcb:BYTE)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (window :initarg :window :type xcb:WINDOW)))

(defclass xcb:xinerama:GetScreenSize
  (xcb:-request)
  ((~opcode :initform 3 :type xcb:-u1)
   (window :initarg :window :type xcb:WINDOW)
   (screen :initarg :screen :type xcb:CARD32)))
(defclass xcb:xinerama:GetScreenSize~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (width :initarg :width :type xcb:CARD32)
   (height :initarg :height :type xcb:CARD32)
   (window :initarg :window :type xcb:WINDOW)
   (screen :initarg :screen :type xcb:CARD32)))

(defclass xcb:xinerama:IsActive
  (xcb:-request)
  ((~opcode :initform 4 :type xcb:-u1)))
(defclass xcb:xinerama:IsActive~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (state :initarg :state :type xcb:CARD32)))

(defclass xcb:xinerama:QueryScreens
  (xcb:-request)
  ((~opcode :initform 5 :type xcb:-u1)))
(defclass xcb:xinerama:QueryScreens~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (number :initarg :number :type xcb:CARD32)
   (pad~1 :initform 20 :type xcb:-pad)
   (screen-info~ :initform
		 '(name screen-info type xcb:xinerama:ScreenInfo size
			(xcb:-fieldref 'number))
		 :type xcb:-list)
   (screen-info :initarg :screen-info :type xcb:-ignore)))



(provide 'xcb-xinerama)

;;; xcb-xinerama.el ends here