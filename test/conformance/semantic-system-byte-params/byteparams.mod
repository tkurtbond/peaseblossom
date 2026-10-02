MODULE byteparams;
  (* PLAN.md Phase 12 step 5d: a SYSTEM.BYTE parameter takes a CHAR, a
     SHORTINT or a BYTE (the Oakwood Guidelines, 1.2.5), a VAR one a
     BOOLEAN too (voc), but a SHORTINT only where it is one byte (-O2),
     and an integer constant only in -128..127. The lines marked "error"
     are the errors, with -OC's two more; voc's are the same, but for
     R(i8), which voc takes (any one-byte integer). *)
  IMPORT SYSTEM;
  VAR c: CHAR; b: BOOLEAN; s: SHORTINT; y: SYSTEM.BYTE; i: INTEGER; i8: SYSTEM.INT8;
  PROCEDURE R(VAR x: SYSTEM.BYTE); BEGIN x := y END R;
  PROCEDURE W(x: SYSTEM.BYTE); BEGIN y := x END W;
BEGIN
  R(c); R(b); R(y);
  R(s); (* error under -OC only: two bytes *)
  W(c); W(s); W(y); W("A"); W(5); W(-3); (* W(s): error under -OC only *)
  R(i); (* error *)
  R(i8); (* error *)
  W(b); (* error *)
  W(i); (* error *)
  W(200) (* error *)
END byteparams.
