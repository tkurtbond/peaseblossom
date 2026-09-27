MODULE rangechecks;
  (* Phase 12 step 1: poc -range-checks, voc's -r. SHORT of an integer and CHR
     stop the program (status 14) when the value does not fit the result;
     without the switch they keep the value's low bits. test.sh runs each case,
     chosen by the program's argument, under both size models, with and
     without the switch, and compares each with voc (-r and not). Case 0 stays
     in range: the limits themselves, and SHORT of a LONGREAL, which is never
     checked. Values come from variables, so nothing is folded. Cases 7 and 8,
     CHR of -1, stop here but not under voc -r, whose CHR check compares signed
     (SYSTEM.h's __R) and so lets a negative value through. *)
  IMPORT Modules, Out, SYSTEM;
  VAR
    which: LONGINT; l: LONGINT; i: INTEGER; s: SHORTINT; h: SYSTEM.INT64;
    x: LONGREAL; r: REAL; c: CHAR;

  PROCEDURE ShowChar(ch: CHAR);
  BEGIN
    Out.Int(ORD(ch), 0); Out.Ln
  END ShowChar;

BEGIN
  Modules.GetIntArg(1, which);
  CASE which OF
    0: l := MAX(INTEGER); Out.Int(SHORT(l), 0); Out.Ln;
       l := MIN(INTEGER); Out.Int(SHORT(l), 0); Out.Ln;
       i := MAX(SHORTINT); Out.Int(SHORT(i), 0); Out.Ln;
       i := MIN(SHORTINT); Out.Int(SHORT(i), 0); Out.Ln;
       h := 2147483647; Out.Int(SHORT(h), 0); Out.Ln;
       h := -2147483647 - 1; Out.Int(SHORT(h), 0); Out.Ln;
       i := 0; ShowChar(CHR(i));
       i := 255; ShowChar(CHR(i));
       s := 127; ShowChar(CHR(s));
       x := 1.0D300; r := SHORT(x); Out.String("SHORT of a LONGREAL is not checked"); Out.Ln
  | 1: l := MAX(INTEGER); INC(l); Out.Int(SHORT(l), 0); Out.Ln
  | 2: l := MIN(INTEGER); DEC(l); Out.Int(SHORT(l), 0); Out.Ln
  | 3: i := MAX(SHORTINT); INC(i); Out.Int(SHORT(i), 0); Out.Ln
  | 4: i := MIN(SHORTINT); DEC(i); Out.Int(SHORT(i), 0); Out.Ln
  | 5: h := 2147483647; INC(h); Out.Int(SHORT(h), 0); Out.Ln
  | 6: i := 256; ShowChar(CHR(i))
  | 7: i := -1; ShowChar(CHR(i))
  | 8: s := -1; ShowChar(CHR(s))
  | 9: l := 300; c := CHR(l); ShowChar(c)
  END
END rangechecks.
