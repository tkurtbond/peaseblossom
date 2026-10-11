MODULE VaxShifts;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): SYSTEM.LSH, ROT and BIT, which the VAX
     backend did not lower, at each width - a CHAR, an INTEGER (a word
     under -O2), a LONGINT, a HUGEINT - with a variable count of each kind
     (a SHORTINT, a LONGINT, a HUGEINT) and a constant one. ShiftsOut
     prints what each gives, on both backends. *)
  IMPORT SYSTEM;

  PROCEDURE LshChar*(c: CHAR; n: SHORTINT): CHAR;
  BEGIN RETURN SYSTEM.LSH(c, n)
  END LshChar;

  PROCEDURE LshWord*(i: INTEGER; n: LONGINT): INTEGER;
  BEGIN RETURN SYSTEM.LSH(i, n)
  END LshWord;

  PROCEDURE LshLong*(l: LONGINT; n: LONGINT): LONGINT;
  BEGIN RETURN SYSTEM.LSH(l, n)
  END LshLong;

  PROCEDURE LshLongByHuge*(l: LONGINT; n: HUGEINT): LONGINT;
  BEGIN RETURN SYSTEM.LSH(l, n)
  END LshLongByHuge;

  PROCEDURE LshQuad*(h: HUGEINT; n: LONGINT): HUGEINT;
  BEGIN RETURN SYSTEM.LSH(h, n)
  END LshQuad;

  PROCEDURE LshConstants*(l: LONGINT; h: HUGEINT): HUGEINT;
  BEGIN RETURN SYSTEM.LSH(l, -4) + SYSTEM.LSH(l, 3) + SYSTEM.LSH(h, -40)
  END LshConstants;

  PROCEDURE RotChar*(c: CHAR; n: LONGINT): CHAR;
  BEGIN RETURN SYSTEM.ROT(c, n)
  END RotChar;

  PROCEDURE RotWord*(i: INTEGER; n: SHORTINT): INTEGER;
  BEGIN RETURN SYSTEM.ROT(i, n)
  END RotWord;

  PROCEDURE RotLong*(l: LONGINT; n: HUGEINT): LONGINT;
  BEGIN RETURN SYSTEM.ROT(l, n)
  END RotLong;

  PROCEDURE RotQuad*(h: HUGEINT; n: LONGINT): HUGEINT;
  BEGIN RETURN SYSTEM.ROT(h, n)
  END RotQuad;

  PROCEDURE RotConstants*(i: INTEGER; l: LONGINT): LONGINT;
  BEGIN RETURN SYSTEM.ROT(i, -3) + SYSTEM.ROT(l, 33)
  END RotConstants;

  PROCEDURE Bit*(a: SYSTEM.ADDRESS; n: LONGINT): BOOLEAN;
  BEGIN RETURN SYSTEM.BIT(a, n)
  END Bit;

  PROCEDURE BitByHuge*(a: SYSTEM.ADDRESS; n: HUGEINT): BOOLEAN;
  BEGIN RETURN SYSTEM.BIT(a, n)
  END BitByHuge;

  PROCEDURE BitConstant*(a: SYSTEM.ADDRESS): BOOLEAN;
  BEGIN RETURN SYSTEM.BIT(a, 11)
  END BitConstant;

END VaxShifts.
