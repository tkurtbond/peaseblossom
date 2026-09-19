MODULE constDecls;
  (* PLAN.md Phase 8 step 13: fixture promotion - the compile+link+run+
     diff-stdout half of semantic-const-decls's own CONST coverage.
     Originally trimmed to the subset the backend supported at the time
     (INTEGER arithmetic incl. DIV/MOD, BOOLEAN & / OR / ~, a hex CHAR
     literal); Phase 9 steps 2 and 3 added REAL arithmetic (pi, widened,
     half), SET constructors and operators (aSet, combinedSet,
     isMember) and a named STRING CONST (greeting), so the CONST section
     below is now semantic-const-decls's own, complete - the same
     constants, the same expressions. Runtime-observable via the same
     SysWrite/"OK"-vs-"FAIL" pattern every other runtime fixture uses
     (see llvm-multi-module/client.mod). See ../crosscheck for this same
     CONST section re-verified under voc/Console.Mod directly - genuinely
     practical here (PLAN.md step 13's own "cross-check ... where
     practical"), unlike every earlier Phase 8 runtime fixture, because
     this one's own core logic needs no FFI at all - only the final
     OK/FAIL print does, and that's trivially swapped for Console.String
     there. The REAL checks are range checks, not equalities, since pi
     and widened are single-precision. *)
  CONST
    n = 10;
    limit = 100;
    pi = 3.14;
    widened = n + pi; (* INTEGER + REAL -> REAL, Appendix A *)
    half = 7 / 2; (* real division: always real, even for integer operands *)
    quotient = 7 DIV 2;
    remainder = 7 MOD 2;
    flag = TRUE & ~FALSE;
    disjunction = FALSE OR (n < limit);
    letter = 41X; (* 'A' *)
    greeting = "hello, world";
    aSet = {1, 2, 5 .. 8};
    combinedSet = aSet + {10} - {1};
    isMember = 5 IN aSet;
    doubled = n * 2;
  VAR ok: BOOLEAN; buf: ARRAY 16 OF CHAR;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  COPY(greeting, buf);
  ok := (quotient = 3) & (remainder = 1) & flag & disjunction & (ORD(letter) = 65) & (doubled = 20)
      & (half = 3.5) & (pi > 3.13) & (pi < 3.15) & (widened > 13.13) & (widened < 13.15)
      & isMember & (aSet = {1, 2, 5, 6, 7, 8}) & (combinedSet = {2, 5, 6, 7, 8, 10})
      & (buf = greeting) & (buf[7] = 77X) & (greeting = "hello, world");
  IF ok THEN SysWrite(1, "OK", 2) ELSE SysWrite(1, "FAIL", 4) END
END constDecls.
