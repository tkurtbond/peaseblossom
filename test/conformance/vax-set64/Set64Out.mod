MODULE Set64Out;
  IMPORT SYSTEM, Out;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): SYSTEM.SET64, printed with Out as ORD's HUGEINT, so that
     the program built by the LLVM backend and the one built for the VAX
     can be compared: constructors, constant and not, a range crossing
     bit 32; +, -, *, / and unary -; a SET widened; IN in memory and in a
     register, with an element out of 0..63; INCL and EXCL; comparisons;
     and SET64 parameters, results, fields and array elements. *)
  TYPE
    Pair = RECORD tag: CHAR; s: SYSTEM.SET64 END;
  VAR
    a, b, c: SYSTEM.SET64; s: SET; i, j, n: INTEGER; h: HUGEINT;
    p: Pair; arr: ARRAY 3 OF SYSTEM.SET64;

  PROCEDURE Show(name: ARRAY OF CHAR; x: SYSTEM.SET64);
  BEGIN
    Out.String(name); Out.String(" "); Out.Hex(ORD(x), 16); Out.Ln
  END Show;

  PROCEDURE Flag(name: ARRAY OF CHAR; f: BOOLEAN);
  BEGIN
    Out.String(name); IF f THEN Out.String(" TRUE") ELSE Out.String(" FALSE") END; Out.Ln
  END Flag;

  PROCEDURE Upper(x: SYSTEM.SET64): SYSTEM.SET64;
  BEGIN
    RETURN x * {32 .. 63}
  END Upper;

  PROCEDURE Add(VAR x: SYSTEM.SET64; k: INTEGER);
  BEGIN
    INCL(x, k)
  END Add;

  (* the members of x, by IN with a variable element, -1 and 64 too *)
  PROCEDURE Members(x: SYSTEM.SET64);
    VAR k: INTEGER;
  BEGIN
    Out.String("members");
    FOR k := -1 TO 64 DO
      IF k IN x THEN Out.String(" "); Out.Int(k, 0) END
    END;
    Out.Ln
  END Members;

BEGIN
  a := {0, 31, 32, 63};
  Show("constant", a);
  i := 3; j := 40;
  b := {i, 33, j - 30 .. j + 1};
  Show("constructor", b);
  b := {35, i .. j};
  Show("range across 32", b);
  b := {33, j .. i};
  Show("empty range", b);
  b := {33, j};
  Show("j, 33", b);
  c := a + b; Show("a + b", c);
  c := b - a; Show("b - a", c);
  c := a * {0 .. 40}; Show("a * {0..40}", c);
  c := a / {0 .. 40}; Show("a / {0..40}", c);
  c := -a; Show("-a", c);
  s := {1, 30};
  c := s + a; Show("SET + SET64", c);
  c := s; Show("SET to SET64", c);
  c := a - s; Show("SET64 - SET", c);
  Flag("31 IN a", 31 IN a);
  Flag("32 IN a", 32 IN a);
  Flag("33 IN a", 33 IN a);
  Flag("70 IN a", 70 IN a);
  n := 63; Flag("n IN a", n IN a);
  n := 64; Flag("64 IN a", n IN a);
  n := -1; Flag("-1 IN a", n IN a);
  n := 40; Flag("40 IN a + b", n IN a + b);
  Flag("62 IN -a", 62 IN -a);
  h := 32; Flag("HUGEINT 32 IN a", h IN a);
  Members(a + b);
  c := {}; INCL(c, 0); INCL(c, 45); n := 63; INCL(c, n); n := 33; INCL(c, n);
  Show("INCL", c);
  EXCL(c, 45); n := 0; EXCL(c, n); n := 63; EXCL(c, n);
  Show("EXCL", c);
  Flag("a = a", a = a);
  Flag("a # b", a # b);
  Flag("a = b", a = b);
  Show("Upper", Upper(a));
  c := {}; Add(c, 50); Add(c, 2); Show("Add", c);
  p.tag := "x"; p.s := a; INCL(p.s, 50);
  Show("field", p.s);
  FOR n := 0 TO 2 DO arr[n] := {}; INCL(arr[n], n * 30) END;
  Show("arr[0]", arr[0]); Show("arr[1]", arr[1]); Show("arr[2]", arr[2]);
  n := 2; Flag("60 IN arr[n]", 60 IN arr[n]);
  Members(arr[1] + arr[n]);
  h := ORD(a); Out.Int(h, 0); Out.Ln
END Set64Out.
