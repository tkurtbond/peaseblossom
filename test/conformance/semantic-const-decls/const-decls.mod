MODULE constDecls;
  (* CONST declarations exercising Oberon2.pdf §5's ConstExpr grammar
     over each basic type (§6.1): numeric arithmetic and the widening
     inclusion hierarchy, DIV/MOD/real division, BOOLEAN &, OR, and ~
     (including the predeclared TRUE/FALSE), CHAR and string literals,
     SET literals and set operators, and a later constant referencing
     an earlier one. *)

  CONST
    n = 10;
    limit* = 100;
    pi = 3.14;
    widened = n + pi; (* INTEGER + REAL -> REAL, Appendix A *)
    half = 7 / 2; (* real division: always real, even for integer operands *)
    quotient = 7 DIV 2;
    remainder = 7 MOD 2;
    flag = TRUE & ~FALSE;
    disjunction = FALSE OR (n < limit);
    letter = 41X; (* hex character constant: 'A' *)
    greeting = "hello, world";
    aSet = {1, 2, 5 .. 8};
    combinedSet = aSet + {10} - {1};
    isMember = 5 IN aSet;
    doubled = n * 2;
BEGIN
END constDecls.
