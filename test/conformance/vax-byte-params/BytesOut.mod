MODULE BytesOut;
  IMPORT SYSTEM, Out;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14): SYSTEM.BYTE parameters, printed with Out, so that the program
     built by the LLVM backend and the one built for the VAX can be
     compared. A value BYTE takes a CHAR; a VAR BYTE a CHAR variable; a
     VAR ARRAY OF SYSTEM.BYTE any variable, its length the variable's
     size in bytes (Oberon2.pdf, Appendix C): an integer, a record, a
     fixed array, an open array and a two-dimensional one. Only types of
     one size under -O2 and -OC, both little-endian. *)
  TYPE
    Pair = RECORD a, b: CHAR; n: SYSTEM.INT16 END;
  VAR
    c, d: CHAR; i: SYSTEM.INT32; h: HUGEINT; p: Pair;
    v: ARRAY 3 OF SYSTEM.INT16; m: ARRAY 2, 3 OF SYSTEM.INT16; s: ARRAY 6 OF CHAR;

  PROCEDURE Copy(x: SYSTEM.BYTE; VAR y: SYSTEM.BYTE);
  BEGIN
    y := x
  END Copy;

  PROCEDURE ByteAt(VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT; VAR b: SYSTEM.BYTE);
  BEGIN
    b := x[n]
  END ByteAt;

  (* LEN(x) and each byte of x *)
  PROCEDURE Dump(name: ARRAY OF CHAR; VAR x: ARRAY OF SYSTEM.BYTE);
    VAR n: LONGINT; ch: CHAR;
  BEGIN
    Out.String(name); Out.String(" "); Out.Int(LEN(x), 0); Out.String(":");
    FOR n := 0 TO LEN(x) - 1 DO ByteAt(x, n, ch); Out.String(" "); Out.Hex(ORD(ch), 2) END;
    Out.Ln
  END Dump;

  PROCEDURE Fill(VAR x: ARRAY OF SYSTEM.BYTE; b: SYSTEM.BYTE);
    VAR n: LONGINT;
  BEGIN
    FOR n := 0 TO LEN(x) - 1 DO x[n] := b END
  END Fill;

  PROCEDURE Open(VAR a: ARRAY OF SYSTEM.INT16);
  BEGIN
    Dump("open", a)
  END Open;

  PROCEDURE Open2(VAR a: ARRAY OF ARRAY OF SYSTEM.INT16);
  BEGIN
    Dump("open 2", a)
  END Open2;

BEGIN
  c := "A"; Copy(c, d); Out.Char(d); Out.Ln;
  Copy("z", d); Out.Char(d); Out.Ln;
  Copy(CHR(66), d); Out.Char(d); Out.Ln;
  Dump("char", c);
  i := 01020304H; Dump("INT32", i);
  h := -2; Dump("HUGEINT", h);
  p.a := "a"; p.b := "b"; p.n := 258; Dump("record", p);
  v[0] := 1; v[1] := 2; v[2] := 3; Dump("array", v);
  Open(v);
  m[0, 0] := 1; m[1, 2] := -1; Open2(m);
  s := "hello"; Dump("string", s);
  Fill(i, 7FX); Out.Int(i, 0); Out.Ln;
  Fill(v, 1X); Out.Int(v[0], 0); Out.Int(v[2], 4); Out.Ln;
  Fill(s, "x"); s[5] := 0X; Out.String(s); Out.Ln
END BytesOut.
