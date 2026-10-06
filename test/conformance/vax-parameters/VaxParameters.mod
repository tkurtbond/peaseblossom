MODULE VaxParameters;
  (* PLAN.md Phase 15 step 5: parameters, the n-th at n*4(AP) of the
     argument list. A value parameter of a longword or less is its value
     there, read at its own width; one the body changes (assigns, passes
     as VAR, uses as a FOR variable) is copied to the frame on entry, the
     list being read-only to the callee (CallStd 2.3; decided with the
     user 2026-10-06). A VAR parameter is its variable's address, used as
     @n(AP). A HUGEINT value parameter is the address of a copy, copied
     again on entry; a read-only one, x-, is used where it is; a HUGEINT
     by address is reached through a register, its two longwords being
     0(Rn) and 4(Rn) *)

  PROCEDURE Scale(b: SHORTINT; w: INTEGER; VAR result: LONGINT);
  BEGIN
    result := b * w
  END Scale;

  PROCEDURE Down(n: INTEGER): INTEGER;
    VAR steps: INTEGER;
  BEGIN
    WHILE n > 0 DO n := n DIV 2; steps := steps + 1 END;
    RETURN steps
  END Down;

  PROCEDURE Upto(limit: INTEGER; VAR sum: LONGINT);
  BEGIN
    FOR limit := limit TO 10 DO sum := sum + limit END
  END Upto;

  PROCEDURE Swap(VAR a, b: INTEGER);
    VAR t: INTEGER;
  BEGIN
    t := a; a := b; b := t
  END Swap;

  PROCEDURE Pass(n: INTEGER; VAR m: INTEGER);
  BEGIN
    Swap(n, m)
  END Pass;

  PROCEDURE Double(x: HUGEINT; VAR y: HUGEINT);
  BEGIN
    y := x + x
  END Double;

  PROCEDURE High(x-: HUGEINT; flags-: SET): BOOLEAN;
  BEGIN
    RETURN (x > 0) & (3 IN flags)
  END High;

END VaxParameters.
