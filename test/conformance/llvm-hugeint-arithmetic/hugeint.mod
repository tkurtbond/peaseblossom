MODULE hugeint;
  (* HUGEINT arithmetic done at run time (every operand comes from a
     variable, so nothing folds): on a 32-bit target each 64-bit value is a
     register pair and DIV/MOD call runtime helpers. llvm-i686-runtime
     reruns this as a 32-bit executable (inventory C3); the expected output
     is voc's. *)
  IMPORT Out;
  TYPE Pair = RECORD lo, hi: HUGEINT END;
  VAR
    a, b, c, big, neg: HUGEINT; small: LONGINT; i: INTEGER;
    arr: ARRAY 3 OF HUGEINT; p: Pair; r: LONGREAL;

  PROCEDURE Show(label: ARRAY OF CHAR; x: HUGEINT);
  BEGIN Out.String(label); Out.String(" "); Out.Int(x, 0); Out.Ln
  END Show;

  PROCEDURE Twice(x: HUGEINT): HUGEINT; BEGIN RETURN x + x END Twice;

  PROCEDURE AddTo(VAR x: HUGEINT; y: HUGEINT); BEGIN x := x + y END AddTo;

  PROCEDURE Cmp(x, y: HUGEINT);
  BEGIN
    IF x < y THEN Out.String("<") ELSIF x = y THEN Out.String("=") ELSE Out.String(">") END;
    IF x # y THEN Out.String(" #") END;
    IF x >= y THEN Out.String(" >=") END;
    Out.Ln
  END Cmp;

BEGIN
  a := 4294967295; b := 1; big := 1000000000000; small := 123456789;
  neg := -big;
  Show("carry", a + b);                      (* crosses 2^32 *)
  Show("borrow", a + b - 2);
  Show("mul", big * 3);
  Show("mul2", a * a);                       (* high word only *)
  Show("mulneg", neg * 7);
  Show("div", big DIV 7);
  Show("mod", big MOD 7);
  Show("divneg", neg DIV 7);                 (* floors *)
  Show("modneg", neg MOD 7);
  c := 4294967296 * 5 + 3;
  Show("divbig", c DIV 4294967296);         (* a divisor wider than 32 bits *)
  Show("modbig", c MOD 4294967296);
  Show("divbigneg", -c DIV 4294967296);
  Show("modbigneg", -c MOD 4294967296);
  Show("abs", ABS(neg));
  Show("negate", -neg);
  Show("mixed", big + small);                (* LONGINT widened *)
  c := small; Show("long", c * 100000);     (* LONGINT assigned, then widened *)
  Show("short", SHORT(big DIV 1000));
  Show("ash", ASH(b, 40));
  Show("ashneg", ASH(neg, -3));
  Show("max+1", MAX(HUGEINT) - b + 2);       (* wraps to MIN *)
  Show("min", MIN(HUGEINT) + b - 1);
  Show("twice", Twice(big));                 (* 64-bit argument and result *)
  c := big; AddTo(c, a); Show("varparam", c);
  FOR i := 0 TO 2 DO arr[i] := big * i + i END;
  Show("array", arr[2]);
  p.lo := a; p.hi := big; Show("record", p.hi - p.lo);
  Cmp(a, a + b); Cmp(big, big); Cmp(neg, b); Cmp(4294967296, 1);
  IF ODD(a) THEN Out.String("odd") ELSE Out.String("even") END; Out.Ln;
  r := big; r := r * 2.0; Out.Int(ENTIER(r / 1.0D6), 0); Out.Ln
END hugeint.
