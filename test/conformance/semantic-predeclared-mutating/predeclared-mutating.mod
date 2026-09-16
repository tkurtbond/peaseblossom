MODULE predeclaredMutating;
  (* Oberon2.pdf §10.3's proper procedures: COPY DEC EXCL HALT INC INCL
     NEW - both NEW(v) (pointer to a fixed record) and NEW(v, x0) (a
     pointer to an open array). *)

  TYPE
    Rec = RECORD x: INTEGER END;

  VAR
    n: INTEGER;
    s: SET;
    line: ARRAY 20 OF CHAR;
    rp: POINTER TO Rec;
    ap: POINTER TO ARRAY OF INTEGER;

BEGIN
  COPY("hello", line);
  n := 0;
  INC(n); DEC(n); INC(n, 2); DEC(n, 2);
  INCL(s, 3); EXCL(s, 3);
  NEW(rp);
  NEW(ap, 10);
  IF n < 0 THEN HALT(1) END
END predeclaredMutating.
