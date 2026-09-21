MODULE bad;
  (* Things that would stop the program at run time whatever it does, when
     the compiler can already see them: a constant index outside a fixed
     array, a constant NEW length that is not positive, HALT with an argument
     outside 0..255 (the exit status keeps only 8 bits on every host), a
     constant CHR/SHORT argument that does not fit, and a constant real
     division by zero.  Phase 11, C9 findings.  Each line marked "ok" must
     stay accepted. *)
  IMPORT SYSTEM;
  CONST Four = 4;
  TYPE
    Grid = ARRAY 3 OF ARRAY 4 OF INTEGER;
    ArrPtr = POINTER TO ARRAY 4 OF INTEGER;
  VAR
    a: ARRAY 4 OF INTEGER; g: Grid; ap: ArrPtr; ip: POINTER TO ARRAY OF INTEGER;
    om: POINTER TO ARRAY OF ARRAY OF INTEGER;
    c: CHAR; r: REAL; d: LONGREAL; p: SYSTEM.PTR; k: INTEGER;

  PROCEDURE Take(i: INTEGER);
  BEGIN END Take;

  PROCEDURE Open(VAR o: ARRAY OF INTEGER);
  BEGIN
    o[100] := 0                       (* ok: an open array has no length to compare *)
  END Open;

BEGIN
  a[3] := 0; a[Four - 1] := 0;        (* ok *)
  a[4] := 0;                          (* error *)
  a[-1] := 0;                         (* error *)
  a[Four] := 0;                       (* error: a named constant *)
  a[2 + 2] := 0;                      (* error: a constant expression *)
  g[2][3] := 0; g[2, 3] := 0;         (* ok *)
  g[3][0] := 0;                       (* error: the first index *)
  g[0][4] := 0;                       (* error: the second *)
  g[1, 4] := 0;                       (* error: in the comma form too *)
  ap[4] := 0;                         (* error: through a pointer to a fixed array *)
  ap^[3] := 0;                        (* ok *)
  k := 7; a[k] := 0;                  (* ok: not constant *)
  NEW(ip, 3); NEW(om, 2, 3);          (* ok *)
  NEW(ip, 0);                         (* error *)
  NEW(ip, -1);                        (* error *)
  NEW(om, 2, 0);                      (* error: the second length *)
  SYSTEM.NEW(p, 8);                   (* ok *)
  SYSTEM.NEW(p, 0);                   (* error *)
  IF k = 100 THEN HALT(255) END;      (* ok *)
  IF k = 101 THEN HALT(0) END;        (* ok *)
  IF k = 102 THEN HALT(256) END;      (* error *)
  IF k = 103 THEN HALT(-1) END;       (* error *)
  IF k = 104 THEN HALT(30000) END;    (* error *)
  c := CHR(255); c := CHR(0);         (* ok *)
  c := CHR(256);                      (* error *)
  c := CHR(300);                      (* error *)
  c := CHR(-1);                       (* error *)
  k := SHORT(100000);                 (* error *)
  Take(SHORT(100000));                (* error: as an argument, where nothing is assigned *)
  Take(ORD("a"));                     (* ok *)
  r := 1.0 / 4.0; d := 1.0D0 / 3.0D0; (* ok *)
  r := 1.0 / 0.0;                     (* error *)
  d := 1.0D0 / 0.0D0;                 (* error *)
  r := 1.0 + 1.0 / 0.0                (* error: once *)
END bad.
