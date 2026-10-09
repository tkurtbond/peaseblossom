MODULE VaxBuild;
  (* PLAN.md Phase 16 step 2: a program poc builds for vax-dec-vms, run on
     VMS. Until the runtime has Out (step 4) it shows what it computed in
     its exit status, which DCL's $STATUS shows: 55 * 256 for the sum,
     16 if the HUGEINT product and quotient are right (POC_HMUL,
     POC_HDIV), 32 if the string comparison is (POC_STRCMP), twice the
     two calls counted in the imported variable, and 1: 14133, %X3735. *)
  IMPORT VaxBuildSums;
  VAR status: LONGINT; name: ARRAY 8 OF CHAR;

  PROCEDURE ["VMS"] SYS$EXIT(code: LONGINT);

BEGIN
  name := "VAX";
  status := VaxBuildSums.Sum(10) * 256;
  IF VaxBuildSums.Product(100000, 100000) DIV 1000000 = 10000 THEN INC(status, 16) END;
  IF name = "VAX" THEN INC(status, 32) END;
  status := status + VaxBuildSums.calls * 2 + 1;
  SYS$EXIT(status)
END VaxBuild.
