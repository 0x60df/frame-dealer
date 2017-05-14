;;; frame-dealer.el --- set frame position according to any dealing rule.


;; Copyright (C) 2017 by 0x60DF

;; Author: 0x60DF <0x60DF@gmail.com>
;; Version: 0.2.1
;; Keywords: frame
;; URL: https://github.com/0x60df/frame-dealer

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
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

;; ‘frame-dealer’ provides a minor mode to set a window frame position
;; according to any dealing rule when `make-frame'. As the rule, User can
;; specify function which returns position where frame should be placed.

;;; Code:

(require 'frame)
(require 'nadvice)
(require 'seq)

(defgroup frame-dealer nil
  "Set frame position according to any dealing rule when `make-frame'"
  :group 'frames)

;;;###autoload
(defcustom frame-dealer-dealing-rule nil
  "Function accoding to which frame-dealer set frame position.

Specified function should return list whose car and cadr are integer,
otherwise frame-dealer leave control of frame position to window system.
Each element of the list are treated as car:left cadr:top of frame position.

Specified function must take one argument, frame object which can be used
as a model of frame to be dealt. In many cases, passed frame object is usefull
for determinating position. However, passed frame object can be ignored."
  :type 'function
  :group 'frame-dealer)

;;;###autoload
(defcustom frame-dealer-use-hook nil
  "When non-nil `frame-dealer' set frame position by using hook
`after-make-frame-functions' instead of using advice by which frame dealer add
positional parameter to arguments of `make-frame'"
  :type 'boolean
  :group 'frame-dealer)

;;;###autoload
(defcustom frame-dealer-lighter " FD"
  "Lighter for frame-dealer-mode"
  :type 'string)

(defvar frame-dealer--model-frames nil
  "Model frames which could not be deleted instantly for any reason")

(defun frame-dealer--generate-positional-frame-parameters (frame)
  "Generate alist containing positional frame parameters,
i.e. left, top, and user-position.
left, and top value are generated by `frame-dealer-dealing-rule' for FRAME.
If FRAME is nil, it defaults to the selected frame."
  (if (functionp frame-dealer-dealing-rule)
      (let* ((frame (or frame (selected-frame)))
             (position (funcall frame-dealer-dealing-rule frame))
             (left (car position))
             (top (cadr position)))
        (if (and (integerp left)
                 (integerp top))
            `((user-position . t)
              (left . ,left)
              (top . ,top))))))

(defun frame-dealer--prepend-positional-frame-parameters (args)
  "Filter for `make-frame' arguments. This function is intended to be used as
:fileter-args for `make-frame' in `nadvice' frame work.

This function take `make-frame' arguments and return arguments prepended by
positional parameters. In order to generate positional parameters,
`frame-dealer--generate-positional-frame-parameters' is called with dummy frame
object which is generated by `make-frame' with passed arguments ARGS."
  (with-temp-buffer
    (let* ((param (car args))
           (selected-frame (selected-frame))
           (model-frame
            (unless (or (assq 'left param)
                        (assq 'top param))
              (advice-remove 'make-frame #'frame-dealer--filtering-dipatcher)
              (unwind-protect
                  (make-frame `((visibility . nil) (wait-for-wm . nil) ,@param))
                (select-frame selected-frame)
                (advice-add 'make-frame
                            :filter-args #'frame-dealer--filtering-dipatcher))))
           (positional-parameters
            (unwind-protect
                (if (and model-frame
                         (assq 'display (frame-parameters model-frame)))
                    (frame-dealer--generate-positional-frame-parameters
                     model-frame))
              (if model-frame
                  (if (frame-dealer--single-frame-client-p
                       (frame-parameter model-frame 'client))
                      (add-to-list 'frame-dealer--model-frames model-frame)
                    (delete-frame model-frame 'force))))))
      `((,@positional-parameters ,@param)))))

(defun frame-dealer--prepend-visibility-nil (args)
  "Filter for `make-frame' arguments. This function is intended to be used as
:fileter-args for `make-frame' in `nadvice' frame work.

This function take `make-frame' arguments and return arguments prepended by
\(visibility . nil\). When this function added to make-frame, made frame is
forced to be invisible."
  `(((visibility . nil) ,@(car args))))

(defun frame-dealer--make-visible (frame)
  "Set FRAME visibility visible."
  (modify-frame-parameters frame '((visibility . t))))

(defun frame-dealer--single-frame-client-p (client)
  "Return t if passed argument CLIENT has just one frame, otherwise return nil"
  (let ((find-client-frame (lambda (fl fn)
                (cond ((null fl) t)
                      ((eq (frame-parameter (car fl) 'client) client)
                       (if (< 0 fn)
                           nil
                         (funcall find-client-frame (cdr fl) (+ 1 fn))))
                      (t (funcall find-client-frame (cdr fl) fn))))))
    (funcall find-client-frame (frame-list) 0)))

(defun frame-dealer--clean-model-frames (frame)
  "Delete frames stored in `frame-dealer--model-frames' if each frame does not
satisfy some exceptional condition."
  (let ((check-and-delete
         (lambda (fl)
           (cond ((null fl) nil)
                 ((frame-dealer--single-frame-client-p
                   (frame-parameter (car fl) 'client))
                  (cons (car fl) (funcall check-and-delete (cdr fl))))
                 (t (delete-frame (car fl) 'force)
                    (funcall check-and-delete (cdr fl)))))))
    (setq frame-dealer--model-frames
          (funcall check-and-delete frame-dealer--model-frames))))

(defun frame-dealer--filtering-dipatcher (args)
  "Filtering dispatcher for advice as filter-args on `make-frame'."
  (if frame-dealer-use-hook
      (frame-dealer--prepend-visibility-nil args)
    (frame-dealer--prepend-positional-frame-parameters args)))

(defun frame-dealer--post-processing-dispatcher (frame)
  "Post processing dispatcher for hook `after-make-frame-functions'"
  (if frame-dealer-use-hook
      (progn (frame-dealer-deal-frame frame)
             (frame-dealer--make-visible frame))
    (frame-dealer--clean-model-frames frame)))

;;;###autoload
(define-minor-mode frame-dealer-mode
  "Toggle `frame-dealer-mode'.

In `frame-dealer-mode', frame position is set according to
`frame-dealer-dealing-rule' automatically when `make-frame'."
  :group 'frame-dealer
  :global t
  :lighter frame-dealer-lighter
  (if frame-dealer-mode
      (progn
        (advice-add 'make-frame
                    :filter-args #'frame-dealer--filtering-dipatcher)
        (add-hook 'after-make-frame-functions
                  #'frame-dealer--post-processing-dispatcher))
    (advice-remove 'make-frame
                   #'frame-dealer--filtering-dipatcher)
    (remove-hook 'after-make-frame-functions
                 #'frame-dealer--post-processing-dispatcher)))

;;;###autoload
(defun frame-dealer-random (frame)
  "Dealing rule to set frame position randomly."
  (let ((left-limit (- (display-pixel-width (frame-parameter frame 'display))
                       (if frame
                           (frame-pixel-width frame)
                         0)))
        (top-limit (- (display-pixel-height (frame-parameter frame 'display))
                      (if frame
                          (frame-pixel-height frame)
                        0))))
    `(,(random left-limit) ,(random top-limit))))

;;;###autoload
(defun frame-dealer-deal-frame (&optional frame)
  "Set FRAME position according to `frame-dealer-dealing-rule'
If FRAME is nil, it defaults to the selected frame."
  (interactive)
  (if (assq 'display (frame-parameters frame))
      (let ((alist (frame-dealer--generate-positional-frame-parameters frame)))
        (if alist (modify-frame-parameters frame alist)))))

(provide 'frame-dealer)

;;; frame-dealer.el ends here
