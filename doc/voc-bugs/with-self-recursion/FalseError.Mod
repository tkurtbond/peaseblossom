MODULE FalseError;

  (* Minimal reproduction of a voc 2.1.0 bug: a procedure that calls
     itself from inside one of its own WITH branches gets a bogus
     "incompatible assignment" error, even though the actual argument's
     type is exactly the formal parameter's declared type. See README.md
     in this directory for the full explanation.

     Expected: compiles cleanly (P's argument node.base is of type Base,
     matching P's own formal parameter type exactly).

     Actual (voc 2.1.0):
       FalseError.Mod  Compiling FalseError.
         32:       P(node.base)
                             ^
           pos   962  err 113  incompatible assignment
       Module compilation failed. *)

  TYPE
    Base = POINTER TO BaseDesc;
    BaseDesc = RECORD END;
    Ptr = POINTER TO PtrDesc;
    PtrDesc = RECORD (BaseDesc)
      base: Base
    END;

  PROCEDURE ^ P(node: Base);

  PROCEDURE P(node: Base);
  BEGIN
    WITH node: Ptr DO
      P(node.base)
    END
  END P;

BEGIN
END FalseError.
