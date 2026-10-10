MODULE Traps;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 10): built by both backends and run once for each case,
     TrapMode.mode, which test.sh writes; each prints a line, then traps or
     halts. The messages, on the standard error and SYS$ERROR, must be the
     same, and the VAX's status %X10000000 + 8 * c + 2 where LLVM exits
     with c, or %X00000001 for 0. *)
  IMPORT Out, TrapMode, TrapLib;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD n: INTEGER; next: Node END;
    Base = POINTER TO BaseDesc;
    BaseDesc = RECORD END;
    Ext = POINTER TO ExtDesc;
    ExtDesc = RECORD (BaseDesc) k: INTEGER END;
  VAR
    node: Node; b: Base; i: INTEGER; l: LONGINT; x: LONGREAL; c: CHAR; s: SHORTINT;

  PROCEDURE Choose(k: INTEGER): INTEGER;
    VAR r: INTEGER;
  BEGIN
    CASE k OF 1: r := 10 | 2: r := 20 END;
    RETURN r
  END Choose;

  PROCEDURE (n: Node) Sum(): INTEGER;
  BEGIN
    RETURN n.n + n.next.n
  END Sum;

  PROCEDURE Outer(p: Base): INTEGER;
    PROCEDURE Inner(): INTEGER;
    BEGIN
      RETURN p(Ext).k
    END Inner;
  BEGIN
    RETURN Inner()
  END Outer;

BEGIN
  Out.String("case "); Out.Int(TrapMode.mode, 0); Out.Ln;
  NEW(node); node.n := 1; NEW(b); i := 0;
  CASE TrapMode.mode OF
    1: i := Choose(3)
  | 2: i := node.Sum()
  | 3: i := Outer(b)
  | 4: i := TrapLib.Get(5)
  | 5: x := 1.0D20; l := ENTIER(x)
  | 6: i := 300; c := CHR(i)
  | 7: i := 300; s := SHORT(i)
  | 8: HALT(0)
  | 9: HALT(7)
  END;
  Out.String("not reached"); Out.Ln
END Traps.
