MODULE callNotProcedure;
  (* Oberon2.pdf §9.2: a call statement's designator must denote a
     procedure (here, a Types.ProcedureType value) - i is INTEGER. *)

  VAR i, j: INTEGER;
BEGIN
  i(j)
END callNotProcedure.
