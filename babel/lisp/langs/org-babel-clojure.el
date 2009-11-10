;;; org-babel-clojure.el --- org-babel functions for clojure evaluation

;; Copyright (C) 2009 Joel Boehland

;; Author: Joel Boehland
;; Keywords: literate programming, reproducible research
;; Homepage: http://orgmode.org
;; Version: 0.01

;;; License:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;;; Org-Babel support for evaluating clojure code

;;; Requirements:

;;; A working clojure install. This also implies a working java executable
;;; clojure-mode
;;; slime
;;; swank-clojure

;;; By far, the best way to install these components is by following
;;; the directions as set out by Phil Hagelberg (Technomancy) on the
;;; web page: http://technomancy.us/126

;;; Code:
(require 'org-babel)
(require 'cl)
(require 'slime)
(require 'swank-clojure)


(org-babel-add-interpreter "clojure")

(add-to-list 'org-babel-tangle-langs '("clojure" "clj"))

(defvar org-babel-clojure-wrapper-method
  "
(defn spit
  [f content]
  (with-open [#^java.io.PrintWriter w 
                 (java.io.PrintWriter. 
                   (java.io.BufferedWriter. 
                     (java.io.OutputStreamWriter. 
                       (java.io.FileOutputStream. 
                         (java.io.File. f)))))]
      (.print w content)))

(defn main
  []
  %s)

(spit \"%s\" (str (main)))") ;;" <-- syntax highlighting is messed without this double quote

;;taken mostly from clojure-test-mode.el
(defun org-babel-clojure-clojure-slime-eval (string &optional handler)
  (slime-eval-async `(swank:eval-and-grab-output ,string)
                    (or handler #'identity)))

(defun org-babel-clojure-slime-eval-sync (string)
  (slime-eval `(swank:eval-and-grab-output ,string)))

;;taken from swank-clojure.el
(defun org-babel-clojure-babel-clojure-cmd ()
  "Create the command to start clojure according to current settings."
  (if (and (not swank-clojure-binary) (not swank-clojure-jar-path))
      (error "You must specifiy either a `swank-clojure-binary' or a `swank-clojure-jar-path'")
    (if swank-clojure-binary
        (if (listp swank-clojure-binary)
            swank-clojure-binary
          (list swank-clojure-binary))
      (delete-if
       'null
       (append
        (list swank-clojure-java-path)
        swank-clojure-extra-vm-args
        (list
         (when swank-clojure-library-paths
           (concat "-Djava.library.path="
                   (swank-clojure-concat-paths swank-clojure-library-paths)))
         "-classpath"
         (swank-clojure-concat-paths
          (append (list swank-clojure-jar-path
                        (concat swank-clojure-path "src/main/clojure/"))
                  swank-clojure-extra-classpaths))
         "clojure.main"))))))

(defun org-babel-clojure-table-or-string (results)
  "If the results look like a table, then convert them into an
Emacs-lisp table, otherwise return the results as a string."
  (org-babel-read
   (if (string-match "^\\[.+\\]$" results)
       (org-babel-read
        (replace-regexp-in-string
         "\\[" "(" (replace-regexp-in-string
                    "\\]" ")" (replace-regexp-in-string
                               ", " " " (replace-regexp-in-string
                                         "'" "\"" results)))))
     results)))

(defun org-babel-clojure-var-to-clojure (var)
  "Convert an elisp var into a string of clojure source code
specifying a var of the same value."
  (if (listp var)
      (format "'%s" var)
    (format "%s" var)))

(defun org-babel-clojure-build-full-form (body vars)
  "Construct a clojure let form with vars as the let vars"
  (let ((vars-forms (mapconcat ;; define any variables
                      (lambda (pair)
                        (format "%s %s" (car pair) (org-babel-clojure-var-to-clojure (cdr pair))))
                      vars "\n      ")))
    (format "(let [%s]\n  %s)" vars-forms (org-babel-trim body))))

(defun org-babel-prep-session:clojure (session params)
  "Prepare SESSION according to the header arguments specified in PARAMS."

  (let* ((session-buf (org-babel-clojure-initiate-session session))
         (vars (org-babel-ref-variables params))
         (var-lines (mapcar ;; define any top level session variables
                     (lambda (pair)
                       (format "(defn %s %s)\n" (car pair) (org-babel-clojure-var-to-clojure (cdr pair))))
                     vars)))
    session-buf))

(defun org-babel-clojure-initiate-session (&optional session)
  "If there is not a current inferior-process-buffer in SESSION
then create.  Return the initialized session."
  (unless (string= session "none")
    (if (comint-check-proc "*inferior-lisp*")
        (get-buffer "*inferior-lisp*")
      (let ((session-buffer (save-window-excursion (slime 'clojure) (current-buffer))))      
        (sit-for 5)
        (if (slime-connected-p)
            session-buffer
          (error "Couldn't create slime clojure *inferior lisp* process"))))))

(defun org-babel-clojure-evaluate-external-process (buffer body &optional result-type)
  "Evaluate the body in an external process."
  (save-window-excursion
    (case result-type
      (output
       (with-temp-buffer
         (insert body)
         (shell-command-on-region
          (point-min) (point-max)
          (format "%s - " (mapconcat #'identity (org-babel-clojure-babel-clojure-cmd) " "))
          'replace)
         (buffer-string)))
      (value
       (let ((tmp-src-file (make-temp-file "clojure_babel_input_"))
             (tmp-results-file (make-temp-file "clojure_babel_results_")))                 
         (with-temp-file tmp-src-file
           (insert (format org-babel-clojure-wrapper-method body tmp-results-file tmp-results-file)))
         (shell-command
          (format "%s %s" (mapconcat #'identity (org-babel-clojure-babel-clojure-cmd) " ")
                  tmp-src-file))
         (org-babel-clojure-table-or-string
          (with-temp-buffer (insert-file-contents tmp-results-file) (buffer-string))))))))

(defun org-babel-clojure-evaluate-session (buffer body &optional result-type)
  "Evaluate the body in the context of a clojure session"
  (let ((raw nil)
        (results nil))
    (setq raw (org-babel-clojure-slime-eval-sync body))
    (setq results (reverse (mapcar #'org-babel-trim raw)))
    (case result-type
      (output (mapconcat #'identity (reverse (cdr results)) "\n"))
      (value (org-babel-clojure-table-or-string (car results))))))

(defun org-babel-clojure-evaluate (buffer body &optional result-type)
  "Pass BODY to the Clojure process in BUFFER.  If RESULT-TYPE equals
'output then return a list of the outputs of the statements in
BODY, if RESULT-TYPE equals 'value then return the value of the
last statement in BODY, as elisp."
  (if session
      (org-babel-clojure-evaluate-session buffer body result-type)
    (org-babel-clojure-evaluate-external-process buffer body result-type)))

(defun org-babel-execute:clojure (body params)
  "Execute a block of Clojure code with org-babel.  This function
is called by `org-babel-execute-src-block' with the following
variables pre-set using `multiple-value-bind'.

  (session vars result-params result-type)"
  
  (let* ((body (org-babel-clojure-build-full-form body vars))     
         (session (org-babel-clojure-initiate-session session)))  
    (org-babel-clojure-evaluate session body result-type)))

(provide 'org-babel-clojure)
