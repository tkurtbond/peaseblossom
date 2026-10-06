MODULE VaxNamesProbe;
  (* PLAN.md Phase 15 step 1: names the VAX backend makes up
     (doc/developer/vax-macro32-backend.md section 5) - short ones, ones
     that differ only in case, ones longer than the 22-character stem that
     differ only after it, "$" and "_", and a type-bound procedure. *)

  TYPE
    Tree = POINTER TO TreeDesc;
    TreeDesc = RECORD left, right: Tree END;

  VAR
    x, X: INTEGER;
    count, Count, COUNT: LONGINT;
    aVeryLongVariableNameNumberOne, aVeryLongVariableNameNumberTwo: CHAR;
    SS$NORMAL, _private: BOOLEAN;

  PROCEDURE Length(t: Tree): INTEGER;
  BEGIN RETURN 0
  END Length;

  PROCEDURE length(t: Tree): INTEGER;
  BEGIN RETURN 1
  END length;

  PROCEDURE (t: Tree) Length(): INTEGER;
  BEGIN RETURN 2
  END Length;

  PROCEDURE ["VMS", "SYS$EXIT"] Exit(code: LONGINT);
  PROCEDURE ["VMS"] LIB$GET_VM(VAR size, address: LONGINT): LONGINT;

END VaxNamesProbe.
