MODULE VaxDeferredWide;
  (* PLAN.md Phase 16 step 6: a wide element or field at offset 0 of a
     parameter reached by its address, @n(AP) - a HUGEINT or a LONGREAL,
     element 0 of a VAR array, the first field of a VAR record - which
     the VAX backend named @n(AP) and its high longword @n+4(AP), the
     next argument's target. Found by POC.EXE on the guest, in
     ModuleInterface.HashStart (hash[0] := 25H, a VAR ARRAY 8 OF LONGINT
     under -OC). WideOut prints what each gives, on both backends. *)
  TYPE
    Pair* = RECORD h*: HUGEINT; r*: LONGREAL END;
    Reals* = RECORD r*: LONGREAL; k*: INTEGER END;
    Hugeints* = ARRAY 4 OF HUGEINT;

  PROCEDURE SetFirst*(VAR a: Hugeints; x: HUGEINT);
  BEGIN a[0] := x; a[1] := x + 1
  END SetFirst;

  PROCEDURE First*(VAR a: Hugeints): HUGEINT;
  BEGIN RETURN a[0]
  END First;

  PROCEDURE SetPair*(VAR p: Pair; x: HUGEINT; y: LONGREAL);
  BEGIN p.h := x; p.r := y
  END SetPair;

  PROCEDURE PairFirst*(VAR p: Pair): HUGEINT;
  BEGIN RETURN p.h
  END PairFirst;

  PROCEDURE SetReal*(VAR r: Reals; y: LONGREAL);
  BEGIN r.r := y; r.k := 7
  END SetReal;

  PROCEDURE RealFirst*(VAR r: Reals): LONGREAL;
  BEGIN RETURN r.r
  END RealFirst;

  PROCEDURE StartFirst*(VAR a: Hugeints; VAR p: Pair);
  BEGIN a[0] := 0CBF29CE484222325H; p.h := -2
  END StartFirst;

  PROCEDURE IncFirst*(VAR a: Hugeints);
  BEGIN INC(a[0], 100000000000)
  END IncFirst;
END VaxDeferredWide.
