;; company-mode integration
(defvar omnisharp-company-type-separator " : "
  "The string used to visually separate functions/variables from
  their types")

(defcustom omnisharp-company-do-template-completion t
  "Set to t if you want in-line parameter completion, nil
  otherwise."
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-company-template-use-yasnippet t 
  "Set to t if you want completion to happen via yasnippet
  otherwise fall back on company's templating. Requires yasnippet
  to be installed"
  
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-company-ignore-case t
  "If t, case is ignored in completion matches."
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-company-strip-trailing-brackets nil
  "If t, strips trailing <> and () from completions."
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-company-begin-after-member-access t
  "If t, begin completion when pressing '.' after a class, object
  or namespace"
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-company-sort-results t
  "If t, autocompletion results are sorted alphabetically"
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-imenu-support nil
  "If t, activate imenu integration. Defaults to nil."
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defcustom omnisharp-eldoc-support t
  "If t, activate eldoc integration - eldoc-mode must also be enabled for
  this to work. Defaults to t."
  :group 'omnisharp
  :type '(choice (const :tag "Yes" t)
                 (const :tag "No" nil)))

(defun omnisharp-auto-complete (&optional invert-importable-types-setting)
  "If called with a prefix argument, will complete types that are not
present in the current namespace or imported namespaces, inverting the
default `omnisharp-auto-complete-want-importable-types'
value. Selecting one of these will import the required namespace."
  (interactive "P")
  (let* ((json-false :json-false)
         ;; json-false helps distinguish between null and false in
         ;; json. This is an emacs limitation.

         ;; Invert the user configuration value if requested
         (params
          (let ((omnisharp-auto-complete-want-importable-types
                 (if invert-importable-types-setting
                     (not omnisharp-auto-complete-want-importable-types)
                   omnisharp-auto-complete-want-importable-types)))
            (omnisharp--get-auto-complete-params)))

         (display-function
          (omnisharp--get-auto-complete-display-function))

         (json-result-auto-complete-response
          (omnisharp-auto-complete-worker params)))

    (funcall display-function json-result-auto-complete-response)))

(defun omnisharp-add-dot-and-auto-complete ()
  "Adds a . character and calls omnisharp-auto-complete. Meant to be
bound to the dot key so pressing dot will automatically insert a dot
and complete members."
  (interactive)
  (insert ".")
  (omnisharp-auto-complete))

(defun omnisharp--get-auto-complete-params ()
  "Return an AutoCompleteRequest for the current buffer state."
  (append `((WantDocumentationForEveryCompletionResult
             . ,(omnisharp--t-or-json-false
                 omnisharp-auto-complete-want-documentation))

            (WantMethodHeader
             . ,(omnisharp--t-or-json-false
                 omnisharp-company-do-template-completion))

            (WantReturnType . t)

            (WantSnippet
             . ,(omnisharp--t-or-json-false
                 (and omnisharp-company-do-template-completion
                      omnisharp-company-template-use-yasnippet)))

            (WantImportableTypes
             . ,(omnisharp--t-or-json-false
                 omnisharp-auto-complete-want-importable-types))

            (WordToComplete . ,(thing-at-point 'symbol)))

          (omnisharp--get-common-params)))

;; Use this source in your csharp editing mode hook like so:
;; (add-to-list 'ac-sources 'ac-source-omnisharp)
;;
;; Unfortunately there seems to be a limit in the auto-complete
;; library that disallows camel case completions and such fancy
;; completions useless.

;; The library only seems to accept completions that have the same
;; leading characters as results. Oh well.
(defvar ac-source-omnisharp
  '((candidates . omnisharp--get-auto-complete-result-in-popup-format)))

(defun ac-complete-omnisharp nil
  (interactive)
  (auto-complete '(ac-source-omnisharp)))

(defun omnisharp--get-auto-complete-result-in-popup-format ()
  "Returns /autocomplete API results \(autocompletions\) as popup
items."
  (let* ((json-result-auto-complete-response
          (omnisharp-auto-complete-worker
           (omnisharp--get-auto-complete-params)))
         (completions-in-popup-format
          (omnisharp--convert-auto-complete-json-to-popup-format
           json-result-auto-complete-response)))
    completions-in-popup-format))

(defun omnisharp-company--prefix ()
  "Returns the symbol to complete. Also, if point is on a dot,
triggers a completion immediately"
  (let ((symbol (company-grab-symbol)))
    (if symbol
        (if (and omnisharp-company-begin-after-member-access
                 (save-excursion
                   (forward-char (- (length symbol)))
                   (looking-back "\\." (- (point) 2))))
            (cons symbol t)
          symbol)
      'stop)))

(defun company-omnisharp (command &optional arg &rest ignored)
  "`company-mode' completion back-end using OmniSharp."
  (case command
    (prefix (and omnisharp-mode
                 (not (company-in-string-or-comment))
                 (omnisharp-company--prefix)))

    (candidates (omnisharp--get-company-candidates arg))

    ;; because "" doesn't return everything
    (no-cache (equal arg ""))

    (annotation (omnisharp--company-annotation arg))

    (meta (omnisharp--get-company-candidate-data arg 'DisplayText))

    (require-match 'never)

    (doc-buffer (let ((doc-buffer (company-doc-buffer
                                   (omnisharp--get-company-candidate-data
                                    arg 'Description))))
                  (with-current-buffer doc-buffer
                    (visual-line-mode))
                  doc-buffer))

    (ignore-case omnisharp-company-ignore-case)

    (sorted omnisharp-company-sort-results)

    ;; Check to see if we need to do any templating
    (post-completion (let* ((json-result (get-text-property 0 'omnisharp-item arg))
                            (allow-templating (get-text-property 0 'omnisharp-allow-templating arg)))
                       (omnisharp--tag-text-with-completion-info arg json-result)
                       (when allow-templating
                         ;; Do yasnippet completion
                         (if (and omnisharp-company-template-use-yasnippet (fboundp 'yas/expand-snippet))
                             (progn
                               (let ((method-snippet (omnisharp--completion-result-item-get-method-snippet
                                                      json-result)))
                                 (when method-snippet
                                   (omnisharp--snippet-templatify arg method-snippet json-result))))
                           ;; Fallback on company completion but make sure company-template is loaded.
                           ;; Do it here because company-mode is optional
                           (require 'company-template)
                           (let ((method-base (omnisharp--get-method-base json-result)))
                             (when (and method-base
                                        (string-match-p "([^)]" method-base))
                               (company-template-c-like-templatify method-base)))))))))
                       
(defun omnisharp--tag-text-with-completion-info (call json-result)
  "Adds data to the completed text which we then use in ElDoc"
  (add-text-properties (- (point) (length call)) (- (point) 1)
                       (list 'omnisharp-result json-result)))

(defun omnisharp--yasnippet-tag-text-with-completion-info ()
  "This is called after yasnippet has finished expanding a template. 
   It adds data to the completed text, which we later use in ElDoc"
  (when omnisharp-snippet-json-result
    (add-text-properties yas-snippet-beg yas-snippet-end 
                         (list 'omnisharp-result omnisharp-snippet-json-result))
    (remove-hook 'yas-after-exit-snippet-hook 'omnisharp--yasnippet-tag-text-with-completion-info)
    (setq omnisharp-snippet-json-result nil)))
  
(defvar omnisharp-snippet-json-result nil
   "Internal, used by snippet completion callback to tag a yasnippet
    completion with data, used by ElDoc.")

(defun omnisharp--snippet-templatify (call snippet json-result)
  "Does a snippet expansion of the completed text.
   Also sets up a hook which will eventually add data for ElDoc"
  (when (not omnisharp-snippet-json-result)
    (setq omnisharp-snippet-json-result json-result)
    (add-hook 'yas-after-exit-snippet-hook 'omnisharp--yasnippet-tag-text-with-completion-info))
  
  (delete-region (- (point) (length call)) (point))
  (yas/expand-snippet snippet))


(defun omnisharp--get-method-base (json-result)
  "If function templating is turned on, and the method is not a
   generic, return the 'method base' (basically, the method definition
   minus its return type)"
    (when omnisharp-company-do-template-completion
      (let ((method-base (omnisharp--completion-result-item-get-method-header json-result))
            (display (omnisharp--completion-result-item-get-completion-text
                      json-result)))
        (when (and method-base
                   ;; company doesn't expand < properly, so
                   ;; if we're not using yasnippet, disable templating on methods that contain it
                   (or omnisharp-company-template-use-yasnippet
                       (not (string-match-p "<" display)))
                   (not (string= method-base "")))
          method-base))))

(defun omnisharp--make-company-completion (json-result)
  "`company-mode' expects the beginning of the candidate to be
the same as the characters being completed.  This method converts
a function description of 'void SomeMethod(int parameter)' to
string 'SomeMethod' propertized with annotation 'void
SomeMethod(int parameter)' and the original value ITEM."
  (let* ((case-fold-search nil)
         (completion (omnisharp--completion-result-item-get-completion-text json-result))
         (display (omnisharp--completion-result-item-get-display-text json-result))
         (output completion)
         (method-base (omnisharp--get-method-base json-result))
         (allow-templating omnisharp-company-do-template-completion)
         (annotation (concat omnisharp-company-type-separator
                             (omnisharp--completion-result-get-item
                              json-result 'ReturnType))))

    ;; If we have templating turned on, if there is a method header
    ;; use that for completion.  The templating engine will then pick
    ;; up the completion for you
    ;; If we're looking at a line that already has a < or (, don't
    ;; enable templating, and also strip < and ( from our completions
    (cond ((looking-at-p "\\s-*(\\|<")
           (setq allow-templating nil)
           (setq output (car (split-string output "\\.*(\\|<"))))
          ((and (not omnisharp-company-do-template-completion)
                omnisharp-company-strip-trailing-brackets)
           (setq output (car (split-string completion "(\\|<"))))
          (method-base
           (setq output method-base)))
    
    ;; When we aren't templating, show the full description of the
    ;; method, rather than just the return type
    (when (not allow-templating)
      (setq annotation (concat omnisharp-company-type-separator
                               display)))

    ;; Embed in completion into the completion text, so we can use it later
    (add-text-properties 0 (length output)
                         (list 'omnisharp-item json-result
                               'omnisharp-ann annotation
                               'omnisharp-allow-templating allow-templating)
                         output)
    output))

(defun omnisharp--get-company-candidates (pre)
  "Returns completion results in company format.  Company-mode
doesn't make any distinction between the text to be inserted and
the text to be displayed.  As a result, since we want to see
parameters and things, we need to munge 'DisplayText so it's
company-mode-friendly"
  (let* ((json-false :json-false)
         ;; json-false helps distinguish between null and false in
         ;; json. This is an emacs limitation.
         (completion-ignore-case omnisharp-company-ignore-case)
         (params
          (omnisharp--get-auto-complete-params))
         (json-result-auto-complete-response
          (omnisharp-auto-complete-worker params)))
    (all-completions pre (mapcar #'omnisharp--make-company-completion
                                 json-result-auto-complete-response))))

(defun omnisharp--company-annotation (candidate)
  (get-text-property 0 'omnisharp-ann candidate))

(defun omnisharp--get-company-candidate-data (candidate datatype)
  "Return the DATATYPE request (e.g. 'DisplayText) for CANDIDATE."
  (let ((item (get-text-property 0 'omnisharp-item candidate)))
    (cdr (assoc datatype item))))

;;Add this completion backend to company-mode
;; (eval-after-load 'company
;;   '(add-to-list 'company-backends 'company-omnisharp))



(defun omnisharp--get-auto-complete-display-function ()
  "Returns a function that can be fed the output from
omnisharp-auto-complete-worker - the AutoCompleteResponse JSON output
from the omnisharp /autocomplete API.

This function must know how to convert the raw JSON into a format that
the user can choose one completion out of.  Then that function must
handle inserting that result in the way it sees fit (e.g. in the
current buffer)."
  (cdr (assoc omnisharp--auto-complete-display-backend
              omnisharp--auto-complete-display-backends-alist)))

(defun omnisharp--get-last-auto-complete-result-display-function ()
  "Returns a function that can be fed the output from
omnisharp-auto-complete-worker (an AutoCompleteResponse). The function
must take a single argument, the auto-complete result texts to show."
  (cdr (assoc omnisharp--show-last-auto-complete-result-frontend
              omnisharp--show-last-auto-complete-result-frontends-alist)))

(defun omnisharp-auto-complete-worker (auto-complete-request)
  "Takes an AutoCompleteRequest and makes an autocomplete query with
them.

Returns the raw JSON result. Also caches that result as
omnisharp--last-buffer-specific-auto-complete-result."
  (let ((json-result
         (omnisharp-post-message-curl-as-json
          (concat (omnisharp-get-host) "autocomplete")
          auto-complete-request)))
    ;; Cache result so it may be juggled in different contexts easily
    (setq omnisharp--last-buffer-specific-auto-complete-result
          json-result)))

(defun omnisharp-auto-complete-overrides ()
  (interactive)
  (omnisharp-auto-complete-overrides-worker
   (omnisharp--get-common-params)))

(defun omnisharp-auto-complete-overrides-worker (params)
  (let* ((json-result
          (omnisharp--vector-to-list
           (omnisharp-post-message-curl-as-json
            (concat (omnisharp-get-host) "getoverridetargets")
            params)))
         (target-names
          (mapcar (lambda (a)
                    (cdr (assoc 'OverrideTargetName a)))
                  json-result))
         (chosen-override (ido-completing-read
                           "Override: "
                           target-names
                           t)))
    (omnisharp-auto-complete-overrides-run-override
     chosen-override)))

(defun omnisharp-auto-complete-overrides-run-override (override-name)
  (omnisharp-auto-complete-overrides-run-override-worker
   (cons `(OverrideTargetName . ,override-name)
         (omnisharp--get-common-params))))

(defun omnisharp-auto-complete-overrides-run-override-worker (params)
  (let ((json-result (omnisharp-post-message-curl-as-json
                      (concat (omnisharp-get-host) "runoverridetarget")
                      params)))
    (omnisharp--set-buffer-contents-to
     (cdr (assoc 'FileName json-result))
     (cdr (assoc 'Buffer   json-result))
     (cdr (assoc 'Line     json-result))
     (cdr (assoc 'Column   json-result)))))

(defun omnisharp-show-last-auto-complete-result ()
  (interactive)
  (let ((auto-complete-result-in-human-readable-form
         (--map (cdr (assoc 'DisplayText it))
                omnisharp--last-buffer-specific-auto-complete-result)))
    (funcall (omnisharp--get-last-auto-complete-result-display-function)
             auto-complete-result-in-human-readable-form)))

(defun omnisharp--show-last-auto-complete-result-in-plain-buffer
  (auto-complete-result-in-human-readable-form-list)
  "Display function for omnisharp-show-last-auto-complete-result using
a simple 'compilation' like buffer to display the last auto-complete
result."
  (let ((buffer
         (get-buffer-create
          omnisharp--last-auto-complete-result-buffer-name)))
    (omnisharp--write-lines-to-compilation-buffer
     auto-complete-result-in-human-readable-form-list
     buffer
     omnisharp--last-auto-complete-result-buffer-header)))

(defun omnisharp-show-overloads-at-point ()
  (interactive)
  ;; Request completions from API but only cache them - don't show the
  ;; results to the user
  (save-excursion
    (end-of-thing 'symbol)
    (omnisharp-auto-complete-worker
     (omnisharp--get-auto-complete-params))
    (omnisharp-show-last-auto-complete-result)))

(provide 'omnisharp-auto-complete-actions)
