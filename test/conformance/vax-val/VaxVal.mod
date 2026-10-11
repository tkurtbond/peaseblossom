MODULE VaxVal;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): SYSTEM.VAL into a HUGEINT from anything
     narrower, which the VAX backend did not lower - an integer sign-
     extended (a SHORTINT, an INTEGER, a LONGINT, an ADDRESS), anything
     else zero-extended (a CHAR, a SET, a pointer) - and, beside them,
     the narrowing and same-size cases it already did. ValOut prints what
     each gives, on both backends. *)
  IMPORT SYSTEM;
  TYPE Node* = POINTER TO RECORD END;

  PROCEDURE FromShort*(x: SHORTINT): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromShort;

  PROCEDURE FromInteger*(x: INTEGER): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromInteger;

  PROCEDURE FromLong*(x: LONGINT): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromLong;

  PROCEDURE FromAddress*(x: SYSTEM.ADDRESS): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromAddress;

  PROCEDURE FromChar*(x: CHAR): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromChar;

  PROCEDURE FromSet*(x: SET): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromSet;

  PROCEDURE FromPointer*(x: Node): HUGEINT;
  BEGIN RETURN SYSTEM.VAL(HUGEINT, x)
  END FromPointer;

  PROCEDURE ToAddress*(h: HUGEINT): SYSTEM.ADDRESS;
  BEGIN RETURN SYSTEM.VAL(SYSTEM.ADDRESS, h)
  END ToAddress;

  PROCEDURE ToChar*(i: INTEGER): CHAR;
  BEGIN RETURN SYSTEM.VAL(CHAR, i)
  END ToChar;

  PROCEDURE ToSet*(l: LONGINT): SET;
  BEGIN RETURN SYSTEM.VAL(SET, l)
  END ToSet;

END VaxVal.
