MODULE lib;
  (* Phase 11 step 2 / inventory B1: a CONST folded from SIZE(T) of a pointer
     or a size-model MAX is printed in the .sym as its folded VALUE, so the
     .sym text depends on the word size and size model of the run that wrote
     it. That is deliberate: the .sym carries no layout, and every
     whole-program command regenerates each import's .sym for its own target
     and size model, so a client never sees a foreign one. test.sh pins both
     halves. *)
  TYPE
    P* = POINTER TO R;
    R* = RECORD next: P; n: INTEGER END;
  CONST
    PtrSize* = SIZE(P);
    RecSize* = SIZE(R);
    LongMax* = MAX(LONGINT);
    SetMax* = MAX(SET);
END lib.
