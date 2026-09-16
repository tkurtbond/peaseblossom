MODULE forwardAlias;
  (* Oberon2.pdf §4 rule 3 allows a forward reference only for the form
     POINTER TO T1; a plain alias like A = B may not name a B declared
     later in the same block. *)
  TYPE
    A = B;
    B = INTEGER;
BEGIN
END forwardAlias.
