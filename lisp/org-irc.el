;;; org-irc.el --- Store links to IRC sessions.
;; Copyright (C) 2008 Phil Jackson
;;
;; Author: Philip Jackson <emacs@shellarchive.co.uk>
;; Keywords: erc, irc, link, org
;; Version: 0.03
;;
;; This file is not yet part of GNU Emacs.
;;
;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;; Link to an IRC session. Only ERC has been implemented at the
;; moment.
;;
;; Place org-irc.el in your load path and add this to your
;; .emacs:
;;
;; (require 'org-irc)
;;
;; Please note that at the moment only ERC is supported. Other clients
;; shouldn't be diffficult to add though.
;;
;; Then set `org-irc-link-to-logs' to non-nil if you would like a
;; file:/ type link to be created to the current line in the logs or
;; to t if you would like to create an irc:/ style link.
;;
;; Links within an org buffer might look like this:
;;
;; [[irc:/irc.freenode.net/#emacs/bob][chat with bob in #emacs on freenode]]
;; [[irc:/irc.freenode.net/#emacs][#emacs on freenode]]
;; [[irc:/irc.freenode.net/]]
;;
;; If, when the resulting link is visited, there is no connection to a
;; requested server then one will be created.
;;
;;; Code:

(require 'org)

(defvar org-irc-client 'erc
  "The IRC client to act on")
(defvar org-irc-link-to-logs t
  "non-nil will store a link to the logs, nil will store an irc: style link")

;; Generic functions/config (extend for other clients)

(add-to-list 'org-store-link-functions
             'org-irc-store-link)

(org-add-link-type "irc" 'org-irc-visit nil)

(defun org-irc-visit (link)
  "Dispatch to the correct visit function based on the client"
  (let ((link (org-irc-parse-link link)))
    (cond
      ((eq org-irc-client 'erc)
       (org-irc-visit-erc link))
      (t
       (error "erc only known client")))))

(defun org-irc-parse-link (link)
  "Get a of irc link attributes where `link' looks like
server:port/chan/user (port, chan and user being optional)."
  (let* ((parts (split-string link "/" t))
         (len (length parts)))
    (when (or (< len 1) (> len 3))
      (error "Failed to parse link needed 1-3 parts, got %d." len))
    (setcar parts (split-string (car parts) ":" t))
    parts))

;;;###autoload
(defun org-irc-store-link ()
  "Dispatch to the appropreate function to store a link to
something IRC related"
  (cond
    ((eq major-mode 'erc-mode)
     (org-irc-erc-store-link))))

;; ERC specific functions

(defun org-irc-erc-get-line-from-log (erc-line)
  "Find the most suitable line to link to from the erc logs. If
the user is on the erc-prompt then search backward for the first
non-blank line, otherwise return the current line."
  (erc-save-buffer-in-logs)
  (with-current-buffer (find-file-noselect (erc-current-logfile))
    (goto-char (point-max))
    (concat
     "file:" (abbreviate-file-name
              buffer-file-name)
     ;; can we get a '::' part?
     (if (equal erc-line (erc-prompt))
         (progn
           (goto-char (point-at-bol))
           (when (search-backward-regexp "^[^ 	]" nil t)
             (concat "::" (buffer-substring-no-properties
                           (point-at-bol)
                           (point-at-eol)))))
         (when (search-backward erc-line nil t)
           (concat "::" (buffer-substring-no-properties
                         (point-at-bol)
                         (point-at-eol))))))))

(defun org-irc-erc-store-link ()
  "Return an org compatible file:/ link which links to a log file
of the current ERC session"
  (if org-irc-link-to-logs
      (let ((erc-line (buffer-substring-no-properties
                       (point-at-bol) (point-at-eol))))
        (if (erc-logging-enabled nil)
            (progn
              (setq cpltxt (org-irc-erc-get-line-from-log erc-line))
              t)
            (error "This ERC session is not being logged")))
      (let ((link (org-irc-get-erc-link)))
        (if link
            (progn
              (setq cpltxt (concat "irc:/" link))
              (org-make-link cpltxt)
              (setq link (org-irc-parse-link link))
              (org-store-link-props :type "irc"
                                    :server (car (car link))
                                    :port (or (cadr (pop link))
                                              erc-default-port)
                                    :nick (pop link))
              t)
            (error "Failed to create (non-log) ERC link")))))

(defun org-irc-get-erc-link ()
  "Return an org compatible irc:/ link from an ERC buffer"
  (let ((link (concat erc-server-announced-name ":"
                      erc-session-port)))
    (concat link "/"
            (if (and (erc-default-target)
                     (erc-channel-p (erc-default-target))
                     (get-text-property (point) 'erc-parsed)
                     (elt (get-text-property (point) 'erc-parsed) 1))
                ;; we can get a nick
                (let ((nick
                       (car
                        (erc-parse-user
                         (elt (get-text-property (point)
                                                 'erc-parsed) 1)))))
                  (concat (erc-default-target) "/"
                          (substring nick 1)))
                (erc-default-target)))))

(defun org-irc-visit-erc (link)
  "Visit an ERC buffer based on criteria from the followed link"
  (let* ((server (car (car link)))
         (port (or (cadr (pop link)) erc-default-port))
         (server-buffer)
         (buffer-list
          (erc-buffer-filter
           (lambda nil
             (let ((tmp-server-buf (erc-server-buffer)))
               (and tmp-server-buf
                    (with-current-buffer tmp-server-buf
                      (and
                       (string= erc-session-port port)
                       (string= erc-server-announced-name server)
                       (setq server-buffer tmp-server-buf)))))))))
    (if buffer-list
        (let ((chan-name (pop link)))
          ;; if we got a channel name then switch to it or join it
          (if chan-name
              (let ((chan-buf (find-if
                               (lambda (x)
                                 (string= (buffer-name x) chan-name))
                               buffer-list)))
                (if chan-buf
                    (progn
                      (switch-to-buffer chan-buf)
                      ;; if we got a nick, and they're in the chan,
                      ;; then start a chat with them
                      (let ((nick (pop link)))
                        (when nick
                          (if (find nick (erc-get-server-nickname-list)
                                    :test 'string=)
                              (progn
                                (goto-char (point-max))
                                (insert (concat nick ": ")))
                              (error "%s not found in %s" nick chan)))))
                    (progn
                      (switch-to-buffer server-buffer)
                      (erc-cmd-JOIN chan-name))))
              (switch-to-buffer server-buffer)))
        ;; no server match, make new connection
        (erc-select :server server :port port))))

(provide 'org-irc)

;;; org-irc.el ends here
