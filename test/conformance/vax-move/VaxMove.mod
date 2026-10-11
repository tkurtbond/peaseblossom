MODULE VaxMove;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): SYSTEM.MOVE, which the VAX backend did not
     lower, with a count of each kind - a LONGINT, a SHORTINT, a HUGEINT,
     a constant. MoveOut prints what each moves, on both backends:
     nothing for a count of zero or less, and blocks that overlap, either
     way and longer than one MOVC3 moves, as through a copy. *)
  IMPORT SYSTEM;

  PROCEDURE Move*(src, dst: SYSTEM.ADDRESS; n: LONGINT);
  BEGIN SYSTEM.MOVE(src, dst, n)
  END Move;

  PROCEDURE MoveByShort*(src, dst: SYSTEM.ADDRESS; n: SHORTINT);
  BEGIN SYSTEM.MOVE(src, dst, n)
  END MoveByShort;

  PROCEDURE MoveByHuge*(src, dst: SYSTEM.ADDRESS; n: HUGEINT);
  BEGIN SYSTEM.MOVE(src, dst, n)
  END MoveByHuge;

  PROCEDURE MoveFour*(src, dst: SYSTEM.ADDRESS);
  BEGIN SYSTEM.MOVE(src, dst, 4)
  END MoveFour;

END VaxMove.
