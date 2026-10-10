MODULE WidenNewOut;
  (* prints what VaxWidenNew gives (its comment says why), on both
     backends; the last call traps (7) *)
  IMPORT SYSTEM, Out, VaxWidenNew;
  VAR deep: VaxWidenNew.Deep; any: SYSTEM.PTR;
BEGIN
  Out.Int(VaxWidenNew.Shorter(-100), 0); Out.Ln;
  Out.Int(VaxWidenNew.Offset(), 0); Out.Ln;
  VaxWidenNew.MakeDeep(deep);
  Out.Int(LEN(deep^, 0), 0); Out.Char(" "); Out.Int(LEN(deep^, 11), 0); Out.Ln;
  VaxWidenNew.RawBlock(any, 16);
  IF any # NIL THEN Out.String("a block of 16 bytes") END; Out.Ln;
  VaxWidenNew.RawBlock(any, 0);
  Out.String("not reached"); Out.Ln
END WidenNewOut.
