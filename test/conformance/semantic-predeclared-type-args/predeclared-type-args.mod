MODULE predeclaredTypeArgs;
  (* Oberon2.pdf §10.3's type-name-argument function procedures: LEN
     (both LEN(v) and LEN(v, n)), MAX, MIN, SIZE. *)

  VAR
    arr: ARRAY 5, 10 OF INTEGER;
    li: LONGINT;
    n: INTEGER;
    s: INTEGER;

BEGIN
  li := LEN(arr);
  li := LEN(arr, 0);
  li := LEN(arr, 1);
  n := MAX(INTEGER);
  n := MIN(INTEGER);
  s := MAX(SET);
  n := SIZE(INTEGER);
  n := SIZE(REAL)
END predeclaredTypeArgs.
