MODULE set64;
  (* SYSTEM.SET64, the 64-bit set: what a SET (32 bits under -O2 and -OC alike)
     is widened into, with elements 0..63. Constant sets are typed by their
     value - {0, 31} is a SET, {0, 32} a SET64 - and a constructor with a
     variable element is a SET64 only when a constant element is above 31. *)
  IMPORT SYSTEM, Out;

  CONST
    high = {32, 40, 63};
    low = {1, 31};
    everything = {0..63};
    mixed = high + {5};
    lower32 = {0..31};

  TYPE
    Holder = RECORD flags: SYSTEM.SET64; count: INTEGER END;

  VAR
    a, b: SYSTEM.SET64; s: SET; n: INTEGER; h: HUGEINT;
    holder: Holder; table: ARRAY 3 OF SYSTEM.SET64;
    pointer: POINTER TO Holder;

  PROCEDURE Flag(x: BOOLEAN);
  BEGIN
    IF x THEN Out.String("T") ELSE Out.String("F") END
  END Flag;

  PROCEDURE Widen(x: SET): SYSTEM.SET64;
  BEGIN
    RETURN x
  END Widen;

  PROCEDURE Members(x: SYSTEM.SET64);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO 63 DO
      IF i IN x THEN Out.Int(i, 0); Out.Char(" ") END
    END;
    Out.Ln
  END Members;

BEGIN
  (* IN at the edges, and outside 0..63 *)
  a := high;
  Flag(32 IN a); Flag(31 IN a); Flag(63 IN a); Flag(64 IN a); Flag(-1 IN a); Out.Ln;
  Members(a);

  (* a SET goes into a SYSTEM.SET64 unchanged *)
  s := low; a := s; Members(a);
  a := lower32; Members(a);
  a := Widen({3, 30}); Members(a);

  (* INCL, EXCL *)
  a := {}; INCL(a, 63); INCL(a, 0); INCL(a, 40); EXCL(a, 0); Members(a);
  n := 33; INCL(a, n); Members(a);

  (* operators, with a SET operand widened *)
  a := high; b := {0, 32, 50};
  Members(a + b); Members(a - b); Members(a * b); Members(a / b);
  a := low; Members(a + {40}); Members(a * s);
  b := everything; Members(-{0..61});
  a := -{}; Flag(a = everything); Flag(a # everything); Out.Ln;

  (* constant folding: the value decides the type *)
  a := mixed; Members(a);
  a := high * {32, 33}; Members(a);
  a := {0..3} + {60..63}; Members(a);
  a := {40..30}; Flag(a = {}); Out.Ln;

  (* relations, mixed widths compare as SET64s *)
  a := low; s := low; Flag(a = s); Flag(s = a); Flag(a # s); Out.Ln;
  a := low + {33}; Flag(a = s); Flag(a # s); Out.Ln;

  (* a constructor with a variable element *)
  n := 45; a := {n, 33}; Members(a);
  n := 5; a := {n, 40}; Members(a);
  n := 7; a := {n..9, 62}; Members(a);

  (* in a record, an array, through a pointer *)
  holder.flags := high; holder.count := 1; Members(holder.flags);
  table[0] := {1}; table[1] := everything; table[2] := {}; Members(table[0] + table[2]);
  Flag(table[1] = everything);
  NEW(pointer); pointer.flags := {63}; INCL(pointer.flags, 1); Members(pointer.flags); Out.Ln;

  (* ORD, VAL, SIZE, MAX, MIN *)
  a := {32}; h := ORD(a); Flag(h = 4294967296); Out.Ln;
  h := 4294967297; a := SYSTEM.VAL(SYSTEM.SET64, h); Members(a);
  Out.Int(SIZE(SYSTEM.SET64), 0); Out.Char(" "); Out.Int(SIZE(SET), 0); Out.Char(" ");
  Out.Int(MAX(SYSTEM.SET64), 0); Out.Char(" "); Out.Int(MAX(SET), 0); Out.Char(" ");
  Out.Int(MIN(SYSTEM.SET64), 0); Out.Ln;

  (* SYSTEM.SET32 is SET *)
  s := {7}; a := s;
  Flag(SIZE(SYSTEM.SET32) = SIZE(SET)); Out.Ln
END set64.
