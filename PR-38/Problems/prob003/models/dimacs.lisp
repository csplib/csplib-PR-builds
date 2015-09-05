;;; -*- Mode: LISP; Syntax: Common-Lisp -*-
;;; File: qga.lsp

;;; this code can be used to generate the sets of clauses for
;;; quasigroup examples used in H. Zhang and M.E. Stickel,
;;; "Implementing the Davis-Putnam Method", submitted to the
;;; SAT 2000 special issue of Journal of Automated Reasoning
;;;
;;; to write a set of quasigroup example files in DIMACS format:
;;; (compile-file "qga.lsp")
;;; (load "qga")
;;;
;;; written by Mark E. Stickel (stickel@ai.sri.com)

(defmacro COLLECT (item place)
  ;; like (setf place (nconc place (list item)))
  ;; except last cell of list is remembered in place-last
  ;; so that operation is O(1)
  ;; collect can be used instead of (push item place) + (nreverse place) loop idiom
  ;; user must declare place-last variable or slot
  (let* ((args (if (atom place) nil (mapcar #'(lambda (arg) (list (gensym) arg)) (rest place))))
         (place (if (atom place) place (cons (first place) (mapcar #'first args))))
         (place-last (if (atom place)
                         (intern (concatenate 'string (symbol-name place) "-LAST"))
                         (cons (intern (concatenate 'string (symbol-name (first place)) "-LAST"))
                               (rest place))))
         (v (gensym))
         (l (gensym)))
    `(let* ((,v (cons ,item nil)) ,@args (,l ,place))
       (cond
        ((null ,l)
         (setf ,place (setf ,place-last ,v)))
        (t
         (rplacd ,place-last (setf ,place-last ,v))
         ,l)))))

(defstruct DP-CLAUSE-SET
  (atoms nil)
  (number-of-atoms 0) ;; in atom-hash-table, may not all appear in clauses
  (number-of-clauses 0)
  (number-of-literals 0)
  (p-clauses nil)  ;; clauses that initially contained only positive literals
  (n-clauses nil)  ;; clauses that initially contained only negative literals
  (m1-clauses nil) ;; clauses that initially were mixed Horn clauses
  (m2-clauses nil) ;; clauses that initially were mixed non-Horn clauses
  (atom-hash-table (make-hash-table :test #'equal))
  (atoms-last nil)
  (p-clauses-last nil)
  (n-clauses-last nil)
  (m1-clauses-last nil)
  (m2-clauses-last nil)
  (number-to-atom-hash-table (make-hash-table)))

(defstruct DP-CLAUSE
  (number-of-unresolved-positive-literals 0 :type fixnum)
  (number-of-unresolved-negative-literals 0 :type fixnum)
  (positive-literals nil)
  (negative-literals nil)
  (next nil))

(defstruct DP-ATOM
  name
  number
  (value nil)
  (contained-positively-clauses nil)
  (contained-negatively-clauses nil)
  (next nil)
  (number-of-occurrences 0))

(defvar *DEFAULT-DIMACS-CNF-FORMAT* :p)
(defvar *DEFAULT-PRINT-WARNINGS* nil)

(defun DP-INSERT (clause clause-set &optional (print-warnings *default-print-warnings*))
  (cl:assert (not (null clause)) ()
	     "Cannot insert the empty clause.")
  (cl:assert (not (member 0 clause)) ()
	     "Clause ~S contains 0, which cannot be used as a literal." clause)
  (if clause-set
      (assert-dp-clause-set-p clause-set)
      (setq clause-set (make-dp-clause-set)))
  (unless (eq print-warnings :safe)
    (let ((v (clause-contains-repeated-atom clause)))
      (cond
	((eq v :tautology)
	 (when print-warnings
	   (warn "Complementary literals in clause ~A." clause))
	 (return-from dp-insert
	   clause-set))
	(v
	 (when print-warnings
	   (warn "Duplicate literals in clause ~A." clause))
	 (setq clause (delete-duplicates clause :test #'equal))))))
  (let ((cl (make-dp-clause))
        (nlits 0)
        (p 0)
        (n 0)
        (positive-literals nil)
        (negative-literals nil)
        positive-literals-last
        negative-literals-last)
    (dolist (lit clause)
      (let* ((pos (positive-literal-p lit))
             (atom0 (if pos lit (complementary-literal lit)))
             (atom (if (dp-atom-p atom0)
                       atom0
                       (atom-named atom0
                                   clause-set
                                   :if-does-not-exist :create))))
	(incf (dp-atom-number-of-occurrences atom))
	(incf nlits)
	(cond
	  (pos
	   (unless (eq :false (dp-atom-value atom))
             (incf p))
           (collect atom positive-literals)
	   (push cl (dp-atom-contained-positively-clauses atom)))
	  (t
	   (unless (eq :true (dp-atom-value atom))
             (incf n))
           (collect atom negative-literals)
	   (push cl (dp-atom-contained-negatively-clauses atom))))))
    (incf (dp-clause-set-number-of-clauses clause-set))
    (incf (dp-clause-set-number-of-literals clause-set) nlits)
    (when positive-literals
      (setf (dp-clause-number-of-unresolved-positive-literals cl) p)
      (setf (dp-clause-positive-literals cl) positive-literals))
    (when negative-literals
      (setf (dp-clause-number-of-unresolved-negative-literals cl) n)
      (setf (dp-clause-negative-literals cl) negative-literals))
    (cond
     ((null negative-literals)
      (if (dp-clause-set-p-clauses clause-set)
          (let ((temp (dp-clause-set-p-clauses-last clause-set)))
            (setf (dp-clause-next temp)
                  (setf (dp-clause-set-p-clauses-last clause-set) cl)))
          (setf (dp-clause-set-p-clauses clause-set)
                (setf (dp-clause-set-p-clauses-last clause-set) cl))))
     ((null positive-literals)
      (if (dp-clause-set-n-clauses clause-set)
          (let ((temp (dp-clause-set-n-clauses-last clause-set)))
            (setf (dp-clause-next temp)
                  (setf (dp-clause-set-n-clauses-last clause-set) cl)))
          (setf (dp-clause-set-n-clauses clause-set)
                (setf (dp-clause-set-n-clauses-last clause-set) cl))))
     ((null (rest positive-literals))
      (if (dp-clause-set-m1-clauses clause-set)
          (let ((temp (dp-clause-set-m1-clauses-last clause-set)))
            (setf (dp-clause-next temp)
                  (setf (dp-clause-set-m1-clauses-last clause-set) cl)))
          (setf (dp-clause-set-m1-clauses clause-set)
                (setf (dp-clause-set-m1-clauses-last clause-set) cl))))
     (t
      (if (dp-clause-set-m2-clauses clause-set)
          (let ((temp (dp-clause-set-m2-clauses-last clause-set)))
            (setf (dp-clause-next temp)
                  (setf (dp-clause-set-m2-clauses-last clause-set) cl)))
          (setf (dp-clause-set-m2-clauses clause-set)
                (setf (dp-clause-set-m2-clauses-last clause-set) cl))))))
  clause-set)

(defvar *DP-READ-STRING*)
(defvar *DP-READ-INDEX*)

(defun DP-READ (s dimacs-cnf-format print-warnings)
  ;; reads a single clause if dimacs-cnf-format = nil
  ;; reads a single literal if dimacs-cnf-format = t
  (loop
    (cond
     (dimacs-cnf-format
      (multiple-value-bind (x i)
	  (read-from-string *dp-read-string* nil :eof :start *dp-read-index*)
        (cond
         ((eq :eof x)
          (if (eq :eof (setq *dp-read-string* (read-line s nil :eof)))
              (return :eof)
              (setq *dp-read-index* 0)))
         ((integerp x)
          (setq *dp-read-index* i)
          (return x))
         ((eql 0 *dp-read-index*)		;ignore DIMACS problem/comment line
          (when print-warnings
            (warn "Skipping line ~A" *dp-read-string*))
          (if (eq :eof (setq *dp-read-string* (read-line s nil :eof)))
              (return :eof)
              (setq *dp-read-index* 0)))
         (t
          (when print-warnings
            (warn "Skipping noninteger ~A" x))
          (setq *dp-read-index* i)))))
     (t
      (let ((x (read s nil :eof)))
        (cond
         ((or (eq :eof x) (consp x))
          (return x))			;no syntax checking
         (print-warnings
          (warn "Skipping nonclause ~A" x))))))))

(defmacro CLAUSE-CONTAINS-TRUE-POSITIVE-LITERAL (clause)
  (let ((atom (gensym)))
    `(dolist (,atom (dp-clause-positive-literals ,clause) nil)
       (when (eq :true (dp-atom-value ,atom))
         (return t)))))

(defmacro CLAUSE-CONTAINS-TRUE-NEGATIVE-LITERAL (clause)
  (let ((atom (gensym)))
    `(dolist (,atom (dp-clause-negative-literals ,clause))
       (when (eq :false (dp-atom-value ,atom))
         (return t)))))

(defun DP-COUNT (clause-set &optional print-p)
  ;; (dp-count clause-set) returns and optionally prints the
  ;; clause and literal count of clauses stored in clause-set
  (let ((nclauses 0) (nliterals 0) (natoms 0) (assigned nil))
    (when clause-set
      (dolist (atom (dp-clause-set-atoms clause-set))
	(when (or (dp-atom-contained-positively-clauses atom)	;atom appears in clause-set
		  (dp-atom-contained-negatively-clauses atom))
	  (if (dp-atom-value atom)
	      (setq assigned t)
	      (incf natoms))))
      (cond
	((not assigned)
	 (setq nclauses (dp-clause-set-number-of-clauses clause-set))
	 (setq nliterals (dp-clause-set-number-of-literals clause-set)))
	(t
         (do ((clause (dp-clause-set-p-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (clause-contains-true-positive-literal clause)
             (incf nclauses)
             (incf nliterals (dp-clause-number-of-unresolved-positive-literals clause))))
         (do ((clause (dp-clause-set-n-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (clause-contains-true-negative-literal clause)
             (incf nclauses)
             (incf nliterals (dp-clause-number-of-unresolved-negative-literals clause))))
         (do ((clause (dp-clause-set-m1-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (or (clause-contains-true-positive-literal clause)
                       (clause-contains-true-negative-literal clause))
             (incf nclauses)
             (incf nliterals (dp-clause-number-of-unresolved-positive-literals clause))
             (incf nliterals (dp-clause-number-of-unresolved-negative-literals clause))))
         (do ((clause (dp-clause-set-m2-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (or (clause-contains-true-positive-literal clause)
                       (clause-contains-true-negative-literal clause))
             (incf nclauses)
             (incf nliterals (dp-clause-number-of-unresolved-positive-literals clause))
             (incf nliterals (dp-clause-number-of-unresolved-negative-literals clause)))))))
    (when print-p
      (format t "~&Clause set contains ~D clauses with ~D literals formed from ~D atoms~A."
	      nclauses nliterals natoms (if (stringp print-p) print-p "")))
    (values nclauses nliterals natoms)))

(defun DP-CLAUSES (map-fun clause-set &optional decode-fun)
  ;; either return or apply map-fun to all clauses in clause-set
  (when clause-set
    (cond
      (map-fun
       (do ((clause (dp-clause-set-p-clauses clause-set) (dp-clause-next clause)))
           ((null clause))
         (unless (clause-contains-true-positive-literal clause)
           (funcall map-fun (decode-dp-clause clause decode-fun))))
       (do ((clause (dp-clause-set-n-clauses clause-set) (dp-clause-next clause)))
           ((null clause))
         (unless (clause-contains-true-negative-literal clause)
           (funcall map-fun (decode-dp-clause clause decode-fun))))
       (do ((clause (dp-clause-set-m1-clauses clause-set) (dp-clause-next clause)))
           ((null clause))
         (unless (or (clause-contains-true-positive-literal clause)
                     (clause-contains-true-negative-literal clause))
           (funcall map-fun (decode-dp-clause clause decode-fun))))
       (do ((clause (dp-clause-set-m2-clauses clause-set) (dp-clause-next clause)))
           ((null clause))
         (unless (or (clause-contains-true-positive-literal clause)
                     (clause-contains-true-negative-literal clause))
           (funcall map-fun (decode-dp-clause clause decode-fun)))))
      (t
       (let ((result nil) result-last)
         (do ((clause (dp-clause-set-p-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (clause-contains-true-positive-literal clause)
             (collect (decode-dp-clause clause decode-fun) result)))
	 (do ((clause (dp-clause-set-n-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (clause-contains-true-negative-literal clause)
             (collect (decode-dp-clause clause decode-fun) result)))
	 (do ((clause (dp-clause-set-m1-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (or (clause-contains-true-positive-literal clause)
                       (clause-contains-true-negative-literal clause))
             (collect (decode-dp-clause clause decode-fun) result)))
	 (do ((clause (dp-clause-set-m2-clauses clause-set) (dp-clause-next clause)))
             ((null clause))
           (unless (or (clause-contains-true-positive-literal clause)
                       (clause-contains-true-negative-literal clause))
             (collect (decode-dp-clause clause decode-fun) result)))
         result)))))

(defun DP-OUTPUT-CLAUSES-TO-FILE (filename clause-set &key (dimacs-cnf-format *default-dimacs-cnf-format*))
  ;; write clauses in clause-set to a file
  (with-open-file (s filename :direction :output :if-exists :new-version)
    (cond
      (dimacs-cnf-format
       (when (eq :p dimacs-cnf-format)
	 (format s "p cnf ~D ~D~%" (dp-clause-set-number-of-atoms clause-set) (dp-count clause-set)))
       (dp-clauses #'(lambda (clause)
		       (dolist (lit clause)
			 (princ lit s)
			 (princ " " s))
		       (princ 0 s)
		       (terpri s))
		   clause-set
		   (if (dolist (atom (dp-clause-set-atoms clause-set) t)
                         (unless (and (integerp (dp-atom-name atom))
                                      (plusp (dp-atom-name atom)))
                           (return nil)))
		       nil
		       #'dp-atom-number)))
      (t
       (dp-clauses #'(lambda (clause)
		       (prin1 clause s)
		       (terpri s))
		   clause-set))))
  nil)

(defun ASSERT-DP-CLAUSE-SET-P (clause-set)
  (cl:assert (dp-clause-set-p clause-set) ()
	     "~S is not a dp-clause-set." clause-set))

(defun ATOM-NAMED (x clause-set &key (if-does-not-exist :error))
  (cl:assert (not (null x)) ()
	     "~A cannot be used as an atomic formula." x)
  (let ((table (dp-clause-set-atom-hash-table clause-set)))
    (or (gethash x table)
	(ecase if-does-not-exist
	  (:create
	    (let ((atom (make-dp-atom
			  :name x
			  :number (incf (dp-clause-set-number-of-atoms clause-set)))))
	      (if (dp-clause-set-atoms clause-set)
		  (let ((temp (dp-clause-set-atoms-last clause-set)))
		    (setf (cdr temp)
			  (setf (dp-clause-set-atoms-last clause-set)
				(cons atom nil))))
		  (setf (dp-clause-set-atoms clause-set)
			(setf (dp-clause-set-atoms-last clause-set)
			      (cons atom nil))))
	      (setf (gethash (dp-atom-number atom) (dp-clause-set-number-to-atom-hash-table clause-set)) atom)
	      (setf (gethash x table) atom)))
	  (:error
	    (error "Unknown atom ~A." x))
	  ((nil)
	   nil)))))

(defun POSITIVE-LITERAL-P (lit)
  (cond
    ((numberp lit)
     (plusp lit))
    ((and (consp lit) (eq 'not (first lit)))
     nil)
    (t
     t)))

(defun COMPLEMENTARY-LITERAL (lit)
  (cond
    ((numberp lit)
     (- lit))
    ((and (consp lit) (eq 'not (first lit)))
     (second lit))
    (t
     (list 'not lit))))

(defun CLAUSE-CONTAINS-REPEATED-ATOM (clause)
  (do* ((dup nil)
        (lits clause (rest lits))
        (lit (first lits) (first lits))
        (clit (complementary-literal lit) (complementary-literal lit)))
       ((null (rest lits))
        dup)
    (dolist (lit2 (rest lits))
      (cond
       ((equal lit lit2)
        (setq dup t))
       ((equal clit lit2)
        (return-from clause-contains-repeated-atom
          :tautology))))))

(defun DECODE-DP-CLAUSE (clause &optional decode-fun)
  (let ((result nil) result-last)
    (dolist (atom (dp-clause-negative-literals clause))
      (unless (dp-atom-value atom)
        (collect (let ((atom (if decode-fun
                                 (funcall decode-fun atom)
                                 (dp-atom-name atom))))
                   (cond
                    ((numberp atom)
                     (- atom))
                    (t
                     (list 'not atom))))
                 result)))
    (dolist (atom (dp-clause-positive-literals clause))
      (unless (dp-atom-value atom)
        (collect (if decode-fun
                     (funcall decode-fun atom)
                     (dp-atom-name atom))
                 result)))
    result))

(defun ENCODE-QG-ATOM (n i j k)
  (declare (ignore n))
  `(,i * ,j = ,k))

(defun NEGATE (atom)
  `(not ,atom))

(defvar USE-ROW-AND-COLUMN-SURJECTIVITY t)

(defun QG (v &key (isomorphism-reducing-constraint 'last-column)
	     not-necessarily-idempotent (clause-set (make-dp-clause-set)))
  (cond
   ((not not-necessarily-idempotent)
    (loop for i from 1 upto v
	  do (dp-insert
	      (list (encode-qg-atom v i i i))
	      clause-set))))
  (unless (eq isomorphism-reducing-constraint 'none)
    (loop for i from 1 upto v
	  do (loop for j from 1 upto v
		   when (< (1+ j) i)
		   do (dp-insert
		       (list (negate (ecase isomorphism-reducing-constraint
					    (first-row
					     (encode-qg-atom v 1 i j))
					    (last-row
					     (encode-qg-atom v v i j))
					    (first-column
					     (encode-qg-atom v i 1 j))
					    (last-column
					     (encode-qg-atom v i v j))
					    (first-value
					     (encode-qg-atom v i j 1))
					    (last-value
					     (encode-qg-atom v i j v)))))
		       clause-set))))
  (loop for i from 1 upto v
	do (loop for j from 1 upto v
		 do (dp-insert
		     (loop for k from 1 upto v
			   collect (encode-qg-atom v i j k))
		     clause-set)))
  (when use-row-and-column-surjectivity
    (loop for i from 1 upto v
	  do (loop for j from 1 upto v
		   do (dp-insert
		       (loop for k from 1 upto v
			     collect (encode-qg-atom v i k j))
		       clause-set)
		   (dp-insert
		    (loop for k from 1 upto v
			  collect (encode-qg-atom v k i j))
		    clause-set))))
  (loop for i from 1 upto v
	do (loop for j from 1 upto v
		 do (loop for k1 from 1 upto v
			  do (loop for k2 from (1+ k1) upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v i j k1))
					     (negate (encode-qg-atom v i j k2)))
				       clause-set)
				   (dp-insert
				    (list (negate (encode-qg-atom v i k1 j))
					  (negate (encode-qg-atom v i k2 j)))
				    clause-set)
				   (dp-insert
				    (list (negate (encode-qg-atom v k1 i j))
					  (negate (encode-qg-atom v k2 i j)))
				    clause-set)))))
  clause-set)

(defun ADD-QG1-CONSTRAINT (clause-set v)
  (loop for a from 1 upto v
	do (loop for b from 1 upto v
		 do (loop for c from a upto v ;symmetric in a,c, so skip c in [1,a)
			  do (loop for d from 1 upto v
				   unless (and (= a c) (= b d))
				   do (loop for ab from 1 upto v
					    do (loop for x from 1 upto v
						     do (dp-insert
							 (list (negate (encode-qg-atom v a b ab))
							       (negate (encode-qg-atom v c d ab))
							       (negate (encode-qg-atom v x b a))
							       (negate (encode-qg-atom v x d c)))
							 clause-set)))))))
  clause-set)

(defun ADD-QG2-CONSTRAINT (clause-set v)
  (loop for a from 1 upto v
	do (loop for b from 1 upto v
		 do (loop for c from a upto v ;symmetric in a,c, so skip c in [1,a)
			  do (loop for d from 1 upto v
				   unless (and (= a c) (= b d))
				   do (loop for ab from 1 upto v
					    do (loop for x from 1 upto v
						     do (dp-insert
							 (list (negate (encode-qg-atom v a b ab))
							       (negate (encode-qg-atom v c d ab))
							       (negate (encode-qg-atom v b x a))
							       (negate (encode-qg-atom v d x c)))
							 clause-set)))))))
  clause-set)

(defun ADD-QG3-CONSTRAINT (clause-set v no-extra-equation-clauses)
  (loop for a from 1 upto v
	do (loop for b from 1 upto v
		 do (loop for ab from 1 upto v
			  do (loop for ba from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v a b ab))
					     (negate (encode-qg-atom v b a ba))
					     (encode-qg-atom v ab ba a))
				       clause-set)
				   (unless no-extra-equation-clauses
				     (dp-insert
				      (list (encode-qg-atom v a b ab)
					    (negate (encode-qg-atom v b a ba))
					    (negate (encode-qg-atom v ab ba a)))
				      clause-set)
				     (dp-insert
				      (list (negate (encode-qg-atom v a b ab))
					    (encode-qg-atom v b a ba)
					    (negate (encode-qg-atom v ab ba a)))
				      clause-set))))))
  ;; Slaney: if a.ax=x or xa.a=x then a=x
  (loop for a from 1 upto v
	do (loop for x from 1 upto v
		 unless (= a x)
		 do (loop for u from 1 upto v
			  do (dp-insert
			      (list (negate (encode-qg-atom v a x u))
				    (negate (encode-qg-atom v a u x)))
			      clause-set)
			  (dp-insert
			   (list (negate (encode-qg-atom v x a u))
				 (negate (encode-qg-atom v u a x)))
			   clause-set))))
  clause-set)

(defun ADD-QG4-CONSTRAINT (clause-set v no-extra-equation-clauses)
  (loop for a from 1 upto v
	do (loop for b from 1 upto v
		 do (loop for ab from 1 upto v
			  do (loop for ba from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v a b ab))
					     (negate (encode-qg-atom v b a ba))
					     (encode-qg-atom v ba ab a))
				       clause-set)
				   (unless no-extra-equation-clauses
				     (dp-insert
				      (list (encode-qg-atom v a b ab)
					    (negate (encode-qg-atom v b a ba))
					    (negate (encode-qg-atom v ba ab a)))
				      clause-set)
				     (dp-insert
				      (list (negate (encode-qg-atom v a b ab))
					    (encode-qg-atom v b a ba)
					    (negate (encode-qg-atom v ba ab a)))
				      clause-set))))))
  clause-set)

(defun ADD-QG5-CONSTRAINT (clause-set v no-extra-equation-clauses)
  (loop for a from 1 upto v
	do (loop for b from 1 upto v
		 do (loop for ba from 1 upto v
			  do (loop for ba.b from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v b a ba))
					     (negate (encode-qg-atom v ba b ba.b))
					     (encode-qg-atom v ba.b b a))
				       clause-set)
				   ;; suggested by Fujita
				   ;; also Slaney's y(xy.y)=x and (y.xy)y=x (6/28/93)
				   (unless no-extra-equation-clauses
				     (dp-insert
				      (list (encode-qg-atom v b a ba)
					    (negate (encode-qg-atom v ba b ba.b))
					    (negate (encode-qg-atom v ba.b b a)))
				      clause-set)
				     (dp-insert
				      (list (negate (encode-qg-atom v b a ba))
					    (encode-qg-atom v ba b ba.b)
					    (negate (encode-qg-atom v ba.b b a)))
				      clause-set))))))
  clause-set)

(defun ADD-QG6-CONSTRAINT (clause-set v)
  (loop for x from 1 upto v
	do (loop for a from 1 upto v
		 do (loop for b from 1 upto v
			  do (loop for ab from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v a b ab))
					     (negate (encode-qg-atom v ab b x))
					     (encode-qg-atom v a ab x))
				       clause-set)
				   (dp-insert
				    (list (negate (encode-qg-atom v a b ab))
					  (negate (encode-qg-atom v a ab x))
					  (encode-qg-atom v ab b x))
				    clause-set)))))
  clause-set)

(defun ADD-QG7A-CONSTRAINT (clause-set v no-extra-equation-clauses)
  ;;finds (132) conjugate equivalents, as suggested by Slaney
  ;;note: constraint on rightmost column not translated to conjugate equivalent, so number of models differs from qg7
  ;; (xy.x)y=x
  (loop for x from 1 upto v
	do (loop for y from 1 upto v
		 do (loop for xy from 1 upto v
			  do (loop for xy.x from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v x y xy))
					     (negate (encode-qg-atom v xy x xy.x))
					     (encode-qg-atom v xy.x y x))
				       clause-set)
				   (unless no-extra-equation-clauses
				     (dp-insert
				      (list (encode-qg-atom v x y xy)
					    (negate (encode-qg-atom v xy x xy.x))
					    (negate (encode-qg-atom v xy.x y x)))
				      clause-set)
				     (dp-insert
				      (list (negate (encode-qg-atom v x y xy))
					    (encode-qg-atom v xy x xy.x)
					    (negate (encode-qg-atom v xy.x y x)))
				      clause-set))))))
  ;; (xy.y).xy=x
  (loop for x from 1 upto v
	do (loop for y from 1 upto v
		 do (loop for xy from 1 upto v
			  do (loop for xy.y from 1 upto v
				   do (dp-insert
				       (list (negate (encode-qg-atom v x y xy))
					     (negate (encode-qg-atom v xy y xy.y))
					     (encode-qg-atom v xy.y xy x))
				       clause-set)))))
  clause-set)

(defun QG1 (v &key (isomorphism-reducing-constraint 'last-column) not-necessarily-idempotent)
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint
			:not-necessarily-idempotent not-necessarily-idempotent)))
    (add-qg1-constraint clause-set v)
    clause-set))

(defun QG2 (v &key (isomorphism-reducing-constraint 'last-column) not-necessarily-idempotent)
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint
			:not-necessarily-idempotent not-necessarily-idempotent)))
    (add-qg2-constraint clause-set v)
    clause-set))

(defun QG3 (v &key (isomorphism-reducing-constraint 'last-value) not-necessarily-idempotent (no-extra-equation-clauses t))
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint
			:not-necessarily-idempotent not-necessarily-idempotent)))
    (add-qg3-constraint clause-set v no-extra-equation-clauses)
    clause-set))

(defun QG4 (v &key (isomorphism-reducing-constraint 'last-value) not-necessarily-idempotent (no-extra-equation-clauses t))
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint
			:not-necessarily-idempotent not-necessarily-idempotent)))
    (add-qg4-constraint clause-set v no-extra-equation-clauses)
    clause-set))

(defun QG5 (v &key (isomorphism-reducing-constraint 'last-column) not-necessarily-idempotent (no-extra-equation-clauses nil))
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint
			:not-necessarily-idempotent not-necessarily-idempotent)))
    (add-qg5-constraint clause-set v no-extra-equation-clauses)
    clause-set))

(defun QG6 (v &key (isomorphism-reducing-constraint 'last-column))
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint)))
    (add-qg6-constraint clause-set v)
    clause-set))

(defun QG7A (v &key (isomorphism-reducing-constraint 'last-column) (no-extra-equation-clauses t))
  (let ((clause-set (qg v
			:isomorphism-reducing-constraint isomorphism-reducing-constraint)))
    (add-qg7a-constraint clause-set v no-extra-equation-clauses)
    clause-set))

(dp-output-clauses-to-file "qg1-07.cnf" (qg1  7))
(dp-output-clauses-to-file "qg1-08.cnf" (qg1  8))
(dp-output-clauses-to-file "qg2-07.cnf" (qg2  7))
(dp-output-clauses-to-file "qg2-08.cnf" (qg2  8))
(dp-output-clauses-to-file "qg3-08.cnf" (qg3  8))
(dp-output-clauses-to-file "qg3-09.cnf" (qg3  9))
(dp-output-clauses-to-file "qg4-08.cnf" (qg4  8))
(dp-output-clauses-to-file "qg4-09.cnf" (qg4  9))
(dp-output-clauses-to-file "qg5-09.cnf" (qg5  9))
(dp-output-clauses-to-file "qg5-10.cnf" (qg5 10))
(dp-output-clauses-to-file "qg5-11.cnf" (qg5 11))
(dp-output-clauses-to-file "qg5-12.cnf" (qg5 12))
(dp-output-clauses-to-file "qg5-13.cnf" (qg5 13))
(dp-output-clauses-to-file "qg6-09.cnf" (qg6  9))
(dp-output-clauses-to-file "qg6-10.cnf" (qg6 10))
(dp-output-clauses-to-file "qg6-11.cnf" (qg6 11))
(dp-output-clauses-to-file "qg6-12.cnf" (qg6 12))
(dp-output-clauses-to-file "qg7-09.cnf" (qg7a  9))
(dp-output-clauses-to-file "qg7-10.cnf" (qg7a 10))
(dp-output-clauses-to-file "qg7-11.cnf" (qg7a 11))
(dp-output-clauses-to-file "qg7-12.cnf" (qg7a 12))
(dp-output-clauses-to-file "qg7-13.cnf" (qg7a 13))

;;; qga.lsp EOF
