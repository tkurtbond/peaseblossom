MODULE strindex;
  IMPORT Out;
  (* Ongoing bug 18 (PLAN.md): a string literal passed to a procedure that is
     called inside an array index, a[F("ab")], was referenced but never
     emitted, so the build failed. What is run: the index on either side of
     an assignment, a nested index, an index of a record field's array, an
     index of a local array, the literal in a procedure, a set's element,
     and a call through an indexed procedure variable. Every line
     printed is "NN ok" or "NN BAD". *)
  TYPE
    R = RECORD v: ARRAY 4 OF INTEGER END;
  VAR
    a: ARRAY 4 OF INTEGER;
    m: ARRAY 4, 4 OF INTEGER;
    r: R;
    x: INTEGER;
    ps: ARRAY 4 OF PROCEDURE (n: INTEGER);
    called: INTEGER;

  PROCEDURE F(s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0; WHILE s[n] # 0X DO INC(n) END;
    RETURN n MOD 4
  END F;

  PROCEDURE Report(number: INTEGER; ok: BOOLEAN);
  BEGIN
    IF number < 10 THEN Out.Char("0") END;
    Out.Int(number, 0);
    IF ok THEN Out.String(" ok") ELSE Out.String(" BAD") END;
    Out.Ln
  END Report;

  PROCEDURE Set(n: INTEGER);
  BEGIN
    called := n
  END Set;

  PROCEDURE Local(): INTEGER;
    VAR b: ARRAY 4 OF INTEGER;
  BEGIN
    b[F("abc")] := 7;
    RETURN b[F("xyz")]
  END Local;

BEGIN
  a[F("ab")] := 1;
  Report(1, a[2] = 1);
  a[3] := 5;
  x := a[F("abc")];
  Report(2, x = 5);
  m[F("a"), F("abc")] := 9;
  Report(3, m[1, 3] = 9);
  Report(4, m[F("b")][F("xyz")] = 9);
  r.v[F("ab")] := 4;
  Report(5, r.v[2] = 4);
  a[1] := 6;
  Report(6, a[a[F("ab")]] = 6);
  Report(7, Local() = 7);
  Report(8, a[F("abcd")] = 0);
  Report(9, {F("ab"), F("a") .. F("abc")} = {1 .. 3});
  ps[F("abc")] := Set;
  ps[F("xyz")](F("ab"));
  Report(10, called = 2)
END strindex.
