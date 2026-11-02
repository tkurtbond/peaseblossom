MODULE valchecks;
  (* Every shape of VAL's check under -range-checks, for review: signed to
     narrower signed, from a longword and from a quadword, a pair of
     registers among them; to a CARD from a signed type, and back; none
     where every value fits; and SYSTEM.VAL, never checked. *)
  IMPORT SYSTEM;
  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT;
    sc: SHORTCARD; c: CARDINAL; lc: LONGCARD; hc: HUGECARD;
    a: ARRAY 4 OF LONGINT;

  PROCEDURE Huge(): HUGEINT;
  BEGIN
    RETURN h
  END Huge;

BEGIN
  i := VAL(INTEGER, l);
  s := VAL(SHORTINT, l);
  l := VAL(LONGINT, h);
  s := VAL(SHORTINT, h);
  i := VAL(INTEGER, Huge());
  sc := VAL(SHORTCARD, l);
  c := VAL(CARDINAL, i);
  lc := VAL(LONGCARD, l);
  c := VAL(CARDINAL, h);
  lc := VAL(LONGCARD, h);
  hc := VAL(HUGECARD, h);
  hc := VAL(HUGECARD, l);
  h := VAL(HUGEINT, hc);
  i := VAL(INTEGER, c);
  l := VAL(LONGINT, hc);
  sc := VAL(SHORTCARD, c);
  lc := VAL(LONGCARD, hc);
  l := VAL(LONGINT, a[i]);
  (* no check: every value fits *)
  l := VAL(LONGINT, i);
  h := VAL(HUGEINT, lc);
  lc := VAL(LONGCARD, sc);
  (* never checked *)
  s := SYSTEM.VAL(SHORTINT, h);
  c := SYSTEM.VAL(CARDINAL, i)
END valchecks.
