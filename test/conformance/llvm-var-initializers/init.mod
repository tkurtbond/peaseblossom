(* Phase 11 A23: VAR x, y: T := e - e is evaluated once for each variable,
   in declaration order, before the body (locals on every entry, globals
   before the module body). Phase 11 D16: a local with no initializer
   starts at zero. A string literal in an initializer of several variables
   is one global, not one per copy. *)
MODULE init;
  IMPORT Out;
  VAR
    calls: INTEGER;
    g1, g2, g3: INTEGER := 7;
    name: ARRAY 16 OF CHAR := "global";

  PROCEDURE Next(): INTEGER;
  BEGIN INC(calls); RETURN calls * 10
  END Next;

  PROCEDURE Show(label: ARRAY OF CHAR; x: LONGINT);
  BEGIN Out.String(label); Out.String(" "); Out.Int(x, 0); Out.Ln
  END Show;

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN i := 0; WHILE s[i] # 0X DO INC(i) END; RETURN i
  END Length;

  VAR l1, l2: INTEGER := Length("four");

  PROCEDURE Locals(n: INTEGER);
    VAR
      a, b, c: INTEGER := Next();
      d: INTEGER := a + n;
      r: RECORD x, y: INTEGER END;
      s: ARRAY 8 OF CHAR := "abc";
      z: LONGINT;
    PROCEDURE Inner;
      VAR k: INTEGER := d * 2;
    BEGIN Show("inner k", k)
    END Inner;
  BEGIN
    Show("a", a); Show("b", b); Show("c", c); Show("d", d);
    Show("r.x", r.x); Show("z", z); Out.String(s); Out.Ln;
    Inner
  END Locals;

BEGIN
  Show("g1", g1); Show("g2", g2); Show("g3", g3); Out.String(name); Out.Ln;
  Show("l1", l1); Show("l2", l2);
  Locals(100);
  Locals(200);
  Show("calls", calls)
END init.
