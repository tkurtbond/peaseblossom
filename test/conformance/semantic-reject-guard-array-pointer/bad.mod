MODULE bad;
  (* A guard, IS or WITH needs a pointer to a record (or a VAR record
     parameter): only records can be extended, so on a pointer to an array
     the only type that could be named is the pointer's own, and there is
     no run-time descriptor to test.  voc rejects each of these (err 85);
     WITH on such a pointer used to compile here and always fail at run
     time (exit 6).  Phase 11, inventory A10. *)
  TYPE
    Arr = ARRAY 5 OF INTEGER;
    ArrPtr = POINTER TO Arr;
    OpenPtr = POINTER TO ARRAY OF INTEGER;
    Rec = RECORD n: INTEGER END;
    RecPtr = POINTER TO Rec;
  VAR
    a: ArrPtr; o: OpenPtr; b: ArrPtr; r: RecPtr; i: INTEGER;

  PROCEDURE Take(x: ArrPtr);
  BEGIN END Take;

BEGIN
  b := a(ArrPtr);                      (* a guard *)
  i := a(ArrPtr)[1];                   (* a guard, then an index *)
  Take(a(ArrPtr));                     (* a guard as an argument *)
  IF a IS ArrPtr THEN i := 1 END;      (* a type test *)
  IF o IS OpenPtr THEN i := 1 END;
  WITH a: ArrPtr DO i := a[1] END;     (* WITH *)
  WITH o: OpenPtr DO i := o[1] END;
  (* a pointer to a record is still fine *)
  IF r IS RecPtr THEN i := r(RecPtr).n END;
  WITH r: RecPtr DO i := r.n END
END bad.
