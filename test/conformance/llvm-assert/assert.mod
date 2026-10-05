MODULE assert;
  (* ASSERT(x) and ASSERT(x, n), poc's extension (doc/research/assert-survey.md): a
     FALSE condition writes "assertion failed", with " (n)" for a code, and
     exits with status 10, the code or not; a TRUE one does nothing. The
     condition is evaluated whatever it is (its side effects happen), and
     output written before the failure is not lost. test.sh runs each case,
     chosen by the program's argument, under both size models; only case 0
     passes every assertion. *)
  IMPORT Modules, Out;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
  VAR which: LONGINT; count: INTEGER; list: Node;

  PROCEDURE Counted(result: BOOLEAN): BOOLEAN;
  BEGIN
    INC(count); RETURN result
  END Counted;

  PROCEDURE Sum(n: Node): INTEGER;
    VAR s: INTEGER;
  BEGIN
    s := 0;
    WHILE n # NIL DO ASSERT(n.value > 0, 20); INC(s, n.value); n := n.next END;
    RETURN s
  END Sum;

  PROCEDURE Push(v: INTEGER);
    VAR n: Node;
  BEGIN
    NEW(n); n.value := v; n.next := list; list := n
  END Push;

  PROCEDURE Outer(k: INTEGER): INTEGER;
    PROCEDURE Inner(j: INTEGER): INTEGER;
    BEGIN
      ASSERT(j < k, 61); RETURN k - j
    END Inner;
  BEGIN
    RETURN Inner(k DIV 2) + Inner(k - 1)
  END Outer;

BEGIN
  Modules.GetIntArg(1, which);
  count := 0;
  ASSERT(Counted(TRUE)); ASSERT(Counted(TRUE), 5);
  ASSERT((count = 2) & (count # 0) OR Counted(FALSE));
  Out.Int(count, 0); Out.Ln;
  Push(3); Push(4);
  CASE which OF
    0: Out.Int(Sum(list), 0); Out.Char(" "); Out.Int(Outer(10), 0); Out.Ln;
       ASSERT(SIZE(NodeDesc) > 0); ASSERT(list # NIL, 255); Out.String("all passed"); Out.Ln
  | 1: Out.String("before "); ASSERT(count = 3)
  | 2: Out.String("before "); ASSERT(count = 3, 42)
  | 3: ASSERT(list = NIL, 0)
  | 4: Push(-1); Out.Int(Sum(list), 0)
  | 5: Out.Int(Outer(0), 0)
  | 6: ASSERT(Counted(FALSE), 255)
  END;
  Out.String("after"); Out.Ln
END assert.
