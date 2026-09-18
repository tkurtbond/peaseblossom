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
     convention). Same CONST section, same OK/FAIL self-check logic as
     ../llvm-const-decls/const-decls.mod (see that file's own header
     comment for exactly which of semantic-const-decls's original
     constants this subset keeps and why) - deliberately kept
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
    quotient = 7 DIV 2;
    remainder = 7 MOD 2;
    flag = TRUE & ~FALSE;
    disjunction = FALSE OR (n < limit);
    letter = 41X; (* 'A' *)
    doubled = n * 2;
  VAR ok: BOOLEAN;
BEGIN
  ok := (quotient = 3) & (remainder = 1) & flag & disjunction & (ORD(letter) = 65) & (doubled = 20);
  IF ok THEN Console.String("OK") ELSE Console.String("FAIL") END;
  Console.Ln
END crosscheck.
