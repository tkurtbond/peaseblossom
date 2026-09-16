MODULE procedureParams;
  (* Oberon2.pdf §10.1/Appendix A: value vs. VAR parameters, an open-array
     value parameter matched via array-compatible (including the
     string-constant special case), and a VAR parameter of record type
     matched by an extension (Ta an extension of Tf). *)

  TYPE
    Base = RECORD x: INTEGER END;
    Extended = RECORD (Base) y: INTEGER END;

  VAR
    a, b: INTEGER;
    line: ARRAY 20 OF CHAR;
    total: INTEGER;
    ext: Extended;

  PROCEDURE Swap(VAR p, q: INTEGER);
    VAR t: INTEGER;
  BEGIN
    t := p; p := q; q := t
  END Swap;

  PROCEDURE Sum(x: ARRAY OF CHAR): INTEGER;
    VAR i, n: INTEGER;
  BEGIN
    n := 0; i := 0;
    WHILE (i < LEN(x)) & (x[i] # 0X) DO n := n + 1; i := i + 1 END;
    RETURN n
  END Sum;

  PROCEDURE Touch(VAR b: Base);
  BEGIN
    b.x := 0
  END Touch;

BEGIN
  a := 1; b := 2;
  Swap(a, b);
  line := "hello";
  total := Sum(line) + Sum("literal");
  Touch(ext)
END procedureParams.
