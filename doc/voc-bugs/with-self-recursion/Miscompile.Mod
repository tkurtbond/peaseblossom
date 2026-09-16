MODULE Miscompile;

  (* A second symptom of the same underlying bug (see README.md): here
     the recursive argument is the WITH-guarded variable itself, not a
     field access off it. This passes voc's own Oberon-2 front end (no
     err 113), but voc emits a wrongly-typed C pointer cast for the
     recursive call's argument, which a strict C compiler then rejects.

     Expected: compiles and links cleanly (P's argument node is a Base
     after all, Ptr being an extension of Base).

     Actual (voc 2.1.0, gcc 14+):
       Miscompile.Mod  Compiling Miscompile.  New symbol file.  1088 chars.
       Miscompile.c: In function 'Miscompile_P':
       Miscompile.c:37:31: error: passing argument 1 of 'Miscompile_P'
       from incompatible pointer type [-Wincompatible-pointer-types]
          37 |    Miscompile_P((*(Miscompile_Ptr*)&node));
             |                 ~^~~~~~~~~~~~~~~~~~~~~~~~
             |                  Miscompile_Ptr {aka struct Miscompile_PtrDesc *}
       ... note: expected 'Miscompile_Base' {aka struct Miscompile_BaseDesc *}
                 but argument is of type 'Miscompile_Ptr'
       C compile: gcc ...
       -- failed: status 0, exitcode 1. *)

  TYPE
    Base = POINTER TO BaseDesc;
    BaseDesc = RECORD END;
    Ptr = POINTER TO PtrDesc;
    PtrDesc = RECORD (BaseDesc) END;

  PROCEDURE ^ P(node: Base);

  PROCEDURE P(node: Base);
  BEGIN
    WITH node: Ptr DO
      P(node)
    END
  END P;

BEGIN
END Miscompile.
