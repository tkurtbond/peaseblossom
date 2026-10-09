MODULE VaxBuildSums;
  (* imported by VaxBuild (PLAN.md Phase 16 step 2): an exported variable
     and two exported procedures, one of them calling poc's runtime
     (POC_HMUL) *)
  VAR calls*: INTEGER;

  PROCEDURE Sum*(n: INTEGER): LONGINT;
    VAR i: INTEGER; s: LONGINT;
  BEGIN
    INC(calls); s := 0;
    FOR i := 1 TO n DO s := s + i END;
    RETURN s
  END Sum;

  PROCEDURE Product*(a, b: HUGEINT): HUGEINT;
  BEGIN
    INC(calls);
    RETURN a * b
  END Product;
END VaxBuildSums.
