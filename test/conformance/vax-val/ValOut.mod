MODULE ValOut;
  (* prints what VaxVal gives (its comment says why), on both backends *)
  IMPORT SYSTEM, Out, VaxVal;
  VAR n: VaxVal.Node; a: SYSTEM.ADDRESS; h: HUGEINT;

  PROCEDURE Show(x: HUGEINT);
  BEGIN Out.Int(x, 0); Out.Char(" ")
  END Show;

BEGIN
  Show(VaxVal.FromShort(-5)); Show(VaxVal.FromShort(127));
  Show(VaxVal.FromInteger(-30000)); Show(VaxVal.FromInteger(30000));
  Show(VaxVal.FromLong(-1)); Show(VaxVal.FromLong(MAX(LONGINT))); Out.Ln;
  Show(VaxVal.FromAddress(-2)); Show(VaxVal.FromAddress(12345)); Out.Ln;
  Show(VaxVal.FromChar(0FFX)); Show(VaxVal.FromChar("A"));
  Show(VaxVal.FromSet({31})); Show(VaxVal.FromSet({0, 2})); Out.Ln;
  Show(VaxVal.FromPointer(NIL));
  NEW(n); a := SYSTEM.VAL(SYSTEM.ADDRESS, n); h := VaxVal.FromPointer(n);
  IF (h # 0) & (VaxVal.ToAddress(h) = a) THEN Out.String("pointer round trip") END; Out.Ln;
  Out.Char(VaxVal.ToChar(256 + 66)); Show(ORD(VaxVal.ToChar(-1)));
  IF VaxVal.ToSet(5) = {0, 2} THEN Out.String("set") END; Out.Ln
END ValOut.
