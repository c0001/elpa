;;; xcb-dpms.el --- X11 DPMS extension  -*- lexical-binding: t -*-

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

;; This file was generated by 'el_client.el' from 'dpms.xml',
;; which you can retrieve from <git://anongit.freedesktop.org/xcb/proto>.

;;; Code:

(require 'xcb-types)

(defconst xcb:dpms:-extension-xname "DPMS")
(defconst xcb:dpms:-extension-name "DPMS")
(defconst xcb:dpms:-major-version 0)
(defconst xcb:dpms:-minor-version 0)

(defclass xcb:dpms:GetVersion
  (xcb:-request)
  ((~opcode :initform 0 :type xcb:-u1)
   (client-major-version :initarg :client-major-version :type xcb:CARD16)
   (client-minor-version :initarg :client-minor-version :type xcb:CARD16)))
(defclass xcb:dpms:GetVersion~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (server-major-version :initarg :server-major-version :type xcb:CARD16)
   (server-minor-version :initarg :server-minor-version :type xcb:CARD16)))

(defclass xcb:dpms:Capable
  (xcb:-request)
  ((~opcode :initform 1 :type xcb:-u1)))
(defclass xcb:dpms:Capable~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (capable :initarg :capable :type xcb:BOOL)
   (pad~1 :initform 23 :type xcb:-pad)))

(defclass xcb:dpms:GetTimeouts
  (xcb:-request)
  ((~opcode :initform 2 :type xcb:-u1)))
(defclass xcb:dpms:GetTimeouts~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (standby-timeout :initarg :standby-timeout :type xcb:CARD16)
   (suspend-timeout :initarg :suspend-timeout :type xcb:CARD16)
   (off-timeout :initarg :off-timeout :type xcb:CARD16)
   (pad~1 :initform 18 :type xcb:-pad)))

(defclass xcb:dpms:SetTimeouts
  (xcb:-request)
  ((~opcode :initform 3 :type xcb:-u1)
   (standby-timeout :initarg :standby-timeout :type xcb:CARD16)
   (suspend-timeout :initarg :suspend-timeout :type xcb:CARD16)
   (off-timeout :initarg :off-timeout :type xcb:CARD16)))

(defclass xcb:dpms:Enable
  (xcb:-request)
  ((~opcode :initform 4 :type xcb:-u1)))

(defclass xcb:dpms:Disable
  (xcb:-request)
  ((~opcode :initform 5 :type xcb:-u1)))

(defconst xcb:dpms:DPMSMode:On 0)
(defconst xcb:dpms:DPMSMode:Standby 1)
(defconst xcb:dpms:DPMSMode:Suspend 2)
(defconst xcb:dpms:DPMSMode:Off 3)

(defclass xcb:dpms:ForceLevel
  (xcb:-request)
  ((~opcode :initform 6 :type xcb:-u1)
   (power-level :initarg :power-level :type xcb:CARD16)))

(defclass xcb:dpms:Info
  (xcb:-request)
  ((~opcode :initform 7 :type xcb:-u1)))
(defclass xcb:dpms:Info~reply
  (xcb:-reply)
  ((pad~0 :initform 1 :type xcb:-pad)
   (~sequence :type xcb:CARD16)
   (length :type xcb:CARD32)
   (power-level :initarg :power-level :type xcb:CARD16)
   (state :initarg :state :type xcb:BOOL)
   (pad~1 :initform 21 :type xcb:-pad)))



(provide 'xcb-dpms)

;;; xcb-dpms.el ends here