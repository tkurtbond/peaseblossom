MODULE strict;
  IMPORT SYSTEM;
  VAR a: SYSTEM.CARD8; w: SYSTEM.CARD16; d: SYSTEM.CARD32; q: SYSTEM.CARD64; c: SYSTEM.CARD;
BEGIN
  a := 1; w := a; d := w; q := d; c := d
END strict.
