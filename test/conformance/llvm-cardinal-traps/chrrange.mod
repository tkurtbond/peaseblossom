MODULE chrrange;
  (* -range-checks: CHR of any CARD8 fits, of a CARD16 above 255 does not *)
  IMPORT SYSTEM, Out;
  VAR w: SYSTEM.CARD16; a: SYSTEM.CARD8; ch: CHAR;
BEGIN
  a := 255; ch := CHR(a); w := 255; ch := CHR(w); Out.String("A");
  w := 256; ch := CHR(w);
  Out.String("B")
END chrrange.
