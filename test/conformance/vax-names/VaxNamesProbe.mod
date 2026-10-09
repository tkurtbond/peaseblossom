MODULE VaxNamesProbe;
  (* PLAN.md Phase 15 step 1: names the VAX backend makes up
     (doc/developer/vax-macro32-backend.md section 5) - short ones, ones
     that differ only in case, ones longer than the 22-character stem that
     differ only after it, "$" and "_", a type-bound procedure, and
     procedures nested in a procedure and in a type-bound one, two of them
     of one name (Phase 16 step 3, section 14, item 8). *)

  TYPE
    Tree = POINTER TO TreeDesc;
    TreeDesc = RECORD left, right: Tree END;

  VAR
    x, X: INTEGER;
    count, Count, COUNT: LONGINT;
    aVeryLongVariableNameNumberOne, aVeryLongVariableNameNumberTwo: CHAR;
    SS$NORMAL, _private: BOOLEAN;

  PROCEDURE Length(t: Tree): INTEGER;
    PROCEDURE Helper(): INTEGER;
      PROCEDURE Deeper(): INTEGER;
      BEGIN RETURN 0
      END Deeper;
    BEGIN RETURN Deeper()
    END Helper;
  BEGIN RETURN Helper()
  END Length;

  PROCEDURE length(t: Tree): INTEGER;
  BEGIN RETURN 1
  END length;

  PROCEDURE (t: Tree) Length(): INTEGER;
    PROCEDURE Helper(): INTEGER;
    BEGIN RETURN 2
    END Helper;
  BEGIN RETURN Helper()
  END Length;

  PROCEDURE ["VMS", "SYS$EXIT"] Exit(code: LONGINT);
  PROCEDURE ["VMS"] LIB$GET_VM(VAR size, address: LONGINT): LONGINT;

END VaxNamesProbe.
