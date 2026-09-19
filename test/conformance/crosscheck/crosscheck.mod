MODULE crosscheck;
  (* PLAN.md Phase 8 step 13: the voc half of the
     ../llvm-const-decls / ../semantic-const-decls CONST-folding
     cross-check. This directory is named after the module itself
     ("crosscheck"), not the fixture's purpose, purely so
     testenv.sh's own generic "rm -f ... $(basename \"$PWD\")" cleanup
     line - which only knows how to remove an executable matching the
     directory's own name - actually removes it (voc names the
     executable after the MODULE identifier, which can't contain the
     hyphens a more descriptive directory name would need; see
     test/conformance/hello for the same single-word-directory
     convention). Same CONST section (semantic-const-decls's own, complete since
     Phase 9 steps 2-3 lifted the original trimming), same OK/FAIL
     self-check logic as ../llvm-const-decls/const-decls.mod - deliberately kept
     byte-for-byte identical to it except for this file's own module
     name/header comment and using Console.String/Console.Ln (voc's
     own standard I/O) instead of poc's own ["C","write"] FFI hack,
     which voc cannot parse at all (confirmed directly: voc rejects a
     module using poc's own external-procedure bracket-attribute
     syntax with "err 38 identifier expected" at the "[" token - it is
     genuinely Peaseblossom's own invented extension, not something
     voc shares, per AGENTS.md's "External procedures" section). Both
     this file and poc's own file must independently fold the exact
     same CONST expressions to the exact same values and both print
     "OK" for this to be a real, meaningful cross-check of
     Oberon-2 CONST-folding semantics (Oberon2.pdf Appendix A/§5),
     rather than of either compiler's own idiosyncrasies. Not wired
     into make test's own poc/voc PATH selection the way every other
     conformance fixture is (see testenv.sh) - this one is voc-only by
     design, run with plain "voc crosscheck.mod -m", same as
     test/conformance/hello. *)
  IMPORT Console;
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
BEGIN
  COPY(greeting, buf);
  ok := (quotient = 3) & (remainder = 1) & flag & disjunction & (ORD(letter) = 65) & (doubled = 20)
      & (half = 3.5) & (pi > 3.13) & (pi < 3.15) & (widened > 13.13) & (widened < 13.15)
      & isMember & (aSet = {1, 2, 5, 6, 7, 8}) & (combinedSet = {2, 5, 6, 7, 8, 10})
      & (buf = greeting) & (buf[7] = 77X) & (greeting = "hello, world");
  IF ok THEN Console.String("OK") ELSE Console.String("FAIL") END;
  Console.Ln
END crosscheck.
