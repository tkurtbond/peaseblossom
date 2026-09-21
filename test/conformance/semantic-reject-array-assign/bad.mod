MODULE bad;
  (* What voc's array assignment (Phase 11, A21) still does not take: a
     longer fixed array into a shorter one, another element type, an open
     array as the target, and a longer or different array passed to a value
     parameter, which is passed by the type it has and not assigned.  Each
     is an error in voc too (err 113). *)
  TYPE
    Row = ARRAY 3 OF INTEGER;
  VAR
    i3: ARRAY 3 OF INTEGER; i5: ARRAY 5 OF INTEGER;
    l3: ARRAY 3 OF LONGINT; c5: ARRAY 5 OF CHAR;
    rows: ARRAY 2 OF Row; grid: ARRAY 2 OF ARRAY 3 OF INTEGER;

  PROCEDURE TakesThree(a: ARRAY 3 OF INTEGER);
  BEGIN END TakesThree;

  PROCEDURE Open(VAR d: ARRAY OF INTEGER);
  BEGIN
    d := i3                    (* an open array is never a target *)
  END Open;

BEGIN
  i3 := i5;                    (* longer into shorter *)
  i5 := l3;                    (* another element type *)
  i5 := c5;                    (* another element type *)
  rows := grid;                (* two anonymous ARRAY 3 OF INTEGERs are not Row *)
  TakesThree(i5)               (* not an assignment: a value parameter takes only its own type *)
END bad.
