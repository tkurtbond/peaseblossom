MODULE rejects;
  (* What stays an error after the 2026-10-02 fixes (llvm-voc-library-fixes
     has what they allow): a read-only field or variable itself, LEN of an
     open array as a constant, a constant LEN of LONGINT type assigned to a
     narrower variable, a module's own name before "." where nothing hides
     it, and NIL where a number is wanted. *)
  IMPORT Ro;
  CONST nothing = NIL;
  VAR a: ARRAY 170 OF INTEGER; i: INTEGER; s: SHORTINT;
  PROCEDURE P(VAR o: ARRAY OF CHAR);
    CONST k = LEN(o);
  END P;
BEGIN
  Ro.x.p := NIL;
  Ro.x := NIL;
  s := LEN(a);
  Ro.r := 1;
  i := nothing + 1;
  i := SHORT(LEN(a))
END rejects.
