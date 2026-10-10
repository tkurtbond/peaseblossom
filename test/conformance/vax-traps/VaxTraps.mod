MODULE VaxTraps;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 10): traps under -trap-location and -range-checks. Each trap
     also passes the module's file and the procedure it is in, a counted
     string for each that traps, named as LLVM names it: a procedure, a
     nested one, a type-bound one, and the module body. CHR's code has a
     high word of 1, for its own message; SHORT's is 14 alone. *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD n: INTEGER; next: Node END;
  VAR
    node: Node; i: INTEGER; c: CHAR; s: SHORTINT; a: ARRAY 4 OF INTEGER;

  PROCEDURE (n: Node) Sum(): INTEGER;
  BEGIN
    RETURN n.n + n.next.n
  END Sum;

  PROCEDURE Outer(k: INTEGER): INTEGER;
    PROCEDURE Inner(): INTEGER;
    BEGIN
      RETURN a[k]
    END Inner;
  BEGIN
    RETURN Inner() + a[k + 1]
  END Outer;

BEGIN
  i := 300; c := CHR(i); s := SHORT(i); i := Outer(1);
  NEW(node); i := node.Sum()
END VaxTraps.
