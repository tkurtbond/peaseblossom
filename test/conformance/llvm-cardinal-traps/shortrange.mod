MODULE shortrange;
  (* -range-checks: SHORT of a CARD16 that does not fit a CARD8 *)
  IMPORT SYSTEM, Out;
  VAR w: SYSTEM.CARD16; a: SYSTEM.CARD8;
BEGIN
  w := 255; a := SHORT(w); Out.String("A");
  w := 256; a := SHORT(w);
  Out.String("B")
END shortrange.
