MODULE constFoldInteger;
  (* PLAN.md Phase 9 step 10: an integer expression whose leaves are all
     constants is a constant of the *minimal* type its value fits, not the
     wider of its operands' types - so 2 * 100 + 2 * 10 is an INTEGER 220
     (it wrapped at SHORTINT width before), -128 a SHORTINT though 128 is an
     INTEGER, and MAX(SHORTINT) + 1 an INTEGER. Every assignment below is
     accepted by real voc under its default -O2 sizes (SHORTINT -128..127,
     INTEGER -32768..32767, LONGINT 32 bits, HUGEINT 64) - the accepting
     counterpart of semantic-reject-const-fold-narrow. *)

  CONST
    total = 2 * 100 + 2 * 10;         (* 220: INTEGER *)
    beyondShort = MAX(SHORTINT) + 1;  (* 128: INTEGER *)
    lowShort = -MAX(SHORTINT) - 1;    (* -128: SHORTINT *)
    million = 1000 * 1000;            (* LONGINT *)
    wide = 100000 * 100000;           (* 10^10: HUGEINT *)
    shifted = ASH(1, 20);             (* LONGINT *)
    hugeShift = ASH(1, 40);           (* 2^40: does not fit a 32-bit LONGINT, so HUGEINT *)
    ten = 1000 DIV 100;               (* SHORTINT *)
    six = 1000 MOD 7;                 (* SHORTINT *)
    negated = -(2 * 100);             (* -200: INTEGER *)

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT;

BEGIN
  (* a negative numeral takes the type of its negative value *)
  s := -128;
  i := -32768;
  l := -2147483648;
  h := -9223372036854775807 - 1;
  (* each operation re-derives the type *)
  s := 100 + 27;
  s := 2 * 100 - 100;
  s := 200 DIV 2;
  s := 1000 MOD 7;
  i := 2 * 100 + 2 * 10;
  i := 127 + 1;
  i := 100 * 200;
  i := -(2 * 100);
  l := 32767 + 1;
  l := 100 * 1000 * 100;
  h := 2147483647 + 1;
  h := 100000 * 100000;
  h := MAX(HUGEINT) - 1 + 1;
  (* named constants carry the folded type *)
  s := lowShort;
  s := ten;
  s := six;
  i := total;
  i := beyondShort;
  i := negated;
  l := million;
  l := shifted;
  h := wide;
  h := hugeShift;
  (* a constant inside an expression that is not constant *)
  i := i + 100 * 200;
  l := l + 100 * 100 * 100;
  (* ASH: the wider of LONGINT and x's type, so a SHORTINT result is out *)
  l := ASH(1, 20);
  l := ASH(-1000, -3);
  h := ASH(1, 62);
  h := ASH(1, 40);
  h := ASH(1, 2 + 3);
  h := ASH(MAX(LONGINT), 32);
  h := ASH(MIN(HUGEINT), -1)
END constFoldInteger.
