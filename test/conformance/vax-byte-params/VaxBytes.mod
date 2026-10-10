MODULE VaxBytes;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14): SYSTEM.BYTE parameters, each lowering once. A value BYTE takes a
     CHAR or a SHORTINT, as a longword; a VAR BYTE a byte variable's
     address; a VAR ARRAY OF SYSTEM.BYTE any variable's address, with its
     size in bytes as the length (Oberon2.pdf, Appendix C): a constant for
     a variable of fixed size, an open array's lengths multiplied by its
     element's size. *)
  IMPORT SYSTEM;
  VAR c: CHAR; si: SHORTINT; l: LONGINT; r: RECORD a: CHAR; n: INTEGER END;
    m: ARRAY 2, 3 OF INTEGER;

  PROCEDURE Copy(x: SYSTEM.BYTE; VAR y: SYSTEM.BYTE);
  BEGIN
    y := x
  END Copy;

  PROCEDURE Fill(VAR x: ARRAY OF SYSTEM.BYTE; b: SYSTEM.BYTE);
    VAR n: LONGINT;
  BEGIN
    FOR n := 0 TO LEN(x) - 1 DO x[n] := b END
  END Fill;

  PROCEDURE Open(VAR a: ARRAY OF ARRAY OF INTEGER);
  BEGIN
    Fill(a, 0X)
  END Open;

BEGIN
  Copy(c, c); Copy(si, si); Copy("A", c); Copy(-1, si);
  Fill(l, c); Fill(r, 1X); Fill(m, si);
  Open(m)
END VaxBytes.
