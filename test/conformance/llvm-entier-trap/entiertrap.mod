MODULE entiertrap;
  (* Phase 11 step 3, inventory A4: ENTIER of a value whose floor does not fit
     a LONGINT is a trap (exit 8, "ENTIER argument out of range for LONGINT"),
     where voc wraps (-O2) or answers the hardware's word (-OC) and poc used to
     answer -2147483648. The bounds are 2^31 under -O2 and 2^63 under -OC; test.sh
     runs each case, chosen by the program's argument, under both models. Only
     case 0 stays in range under both. *)
  IMPORT Modules, Out;
  VAR which: LONGINT; zero, big, x: LONGREAL; r: REAL;

  PROCEDURE Two(n: INTEGER): LONGREAL;
    VAR p: LONGREAL;
  BEGIN
    p := 1.0D0;
    WHILE n > 0 DO p := p * 2.0D0; DEC(n) END;
    RETURN p
  END Two;

  PROCEDURE Show(v: LONGREAL);
  BEGIN
    Out.Int(ENTIER(v), 0); Out.Ln
  END Show;

BEGIN
  Modules.GetIntArg(1, which);
  zero := 0.0D0; big := Two(1000);
  CASE which OF
    0: Show(3.7D0); Show(-3.7D0); Show(0.0D0); Show(-0.5D0); Show(-1.0D0);
       Show(Two(31) - 1.0D0); Show(Two(31) - 0.5D0); Show(-Two(31)); Show(-Two(31) + 0.5D0);
       r := 1.5E9; Out.Int(ENTIER(r), 0); Out.Ln
  | 1: Show(Two(31))
  | 2: Show(-Two(31) - 1.0D0)
  | 3: Show(Two(63))
  | 4: Show(-Two(63) - 2048.0D0)
  | 5: x := big * big; Show(x)
  | 6: x := big * big; Show(-x)
  | 7: x := zero / zero; Show(x)
  | 8: r := 3.0E9; Out.Int(ENTIER(r), 0); Out.Ln
  | 9: Show(Two(63) - 1024.0D0); Show(-Two(63)); Show(Two(40) + 0.5D0)
  END;
  Out.String("reached the end"); Out.Ln
END entiertrap.
