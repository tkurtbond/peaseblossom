MODULE VaxWidenNew;
  (* PLAN.md Phase 16 step 5: what tools/vax-suite's first runs found the
     VAX backend doing wrong (doc/developer/vax-macro32-backend.md, section
     16, proposal 7). SHORT of an INT8 is an INT8 again, a move; a longword
     computed into R0 and returned as a quadword LONGINT (under -OC) gets
     its high longword; NEW of an open array of more than 11 dimensions
     skips its length stores by a branch over a JMP; SYSTEM.NEW allocates
     the size it is given, and a size that is not positive traps (7).
     WidenNewOut prints what they give. *)
  IMPORT SYSTEM;
  TYPE
    Deep* = POINTER TO ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF
      ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF CHAR;
  VAR
    s: ARRAY 8 OF CHAR;

  PROCEDURE Shorter*(i: SYSTEM.INT8): SYSTEM.INT8;
  BEGIN RETURN SHORT(i)
  END Shorter;

  PROCEDURE Offset*(): LONGINT;
  BEGIN RETURN SYSTEM.ADR(s[3]) - SYSTEM.ADR(s[0])
  END Offset;

  PROCEDURE MakeDeep*(VAR deep: Deep);
  BEGIN NEW(deep, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3)
  END MakeDeep;

  PROCEDURE RawBlock*(VAR any: SYSTEM.PTR; size: LONGINT);
  BEGIN SYSTEM.NEW(any, size)
  END RawBlock;

END VaxWidenNew.
