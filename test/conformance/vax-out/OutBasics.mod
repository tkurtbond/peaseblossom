MODULE OutBasics;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 2): the minimal Out of rtl/vax, against the LLVM backend's,
     one source and, for each size model, one expected output for both:
     characters, strings, integers in decimal, right-aligned, and in
     hexadecimal, at the edges of each integer type. MIN(HUGEINT) also
     checks the high longword of a quadword constant, which the voc-built
     poc wrote wrong until 2026-10-09. *)
  IMPORT Out;
  VAR s: ARRAY 8 OF CHAR; i: INTEGER; l: LONGINT; h: HUGEINT;
BEGIN
  Out.Open;
  Out.String("hello, world"); Out.Ln;
  Out.Char("A"); Out.Char(" "); Out.Char("z"); Out.Ln;
  s := "abc"; Out.String(s); Out.String("|"); Out.Ln;
  Out.Int(0, 0); Out.Char(" "); Out.Int(42, 0); Out.Char(" "); Out.Int(-7, 0); Out.Ln;
  Out.String("["); Out.Int(123, 6); Out.String("]["); Out.Int(-45, 6);
  Out.String("]["); Out.Int(12345, 2); Out.String("]"); Out.Ln;
  i := MAX(INTEGER); Out.Int(i, 0); Out.Char(" "); i := MIN(INTEGER); Out.Int(i, 0); Out.Ln;
  l := MAX(LONGINT); Out.Int(l, 0); Out.Char(" "); l := MIN(LONGINT); Out.Int(l, 0); Out.Ln;
  h := MAX(HUGEINT); Out.Int(h, 0); Out.Ln;
  h := MIN(HUGEINT); Out.Int(h, 22); Out.Ln;
  Out.Hex(0, 1); Out.Char(" "); Out.Hex(255, 1); Out.Char(" "); Out.Hex(255, 4); Out.Char(" ");
  Out.Hex(-1, 4); Out.Char(" "); Out.Hex(-1, 20); Out.Char(" "); Out.Hex(48879, 0); Out.Ln;
  h := MIN(HUGEINT); Out.Hex(h, 16); Out.Char(" "); h := MAX(HUGEINT); Out.Hex(h, 1); Out.Ln;
  Out.Ln;
  Out.String("the end"); Out.Flush; Out.Ln
END OutBasics.
