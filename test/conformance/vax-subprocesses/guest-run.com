$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 11): POCRTL,
$ ! VMSDEF and VMSLIB built, then SPAWNUSE and CHAINEDUSE by the procedures
$ ! poc -build wrote, and SPAWNUSE run; it runs CHAINEDUSE, which ends by
$ ! LIB$DO_COMMAND. The lines after the RUN show what follows the chain.
$ ! Everything made is deleted.
$ SET NOON
$ IF P1 .EQS. "RUNS" THEN GOTO RUNS
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @VMSLIB_SETUP
$ @VMSLIB_BUILD
$ WRITE SYS$OUTPUT "VMSLIB_BUILD: ", $STATUS
$ @SPAWNUSE
$ WRITE SYS$OUTPUT "SPAWNUSE built: ", $STATUS
$ @CHAINEDUSE
$ WRITE SYS$OUTPUT "CHAINEDUSE built: ", $STATUS
$ ! the runs, once; or, with P1 = n (vax_do's VAX_REPEAT), n times, the
$ ! first one's output shown and each later one's compared with it and
$ ! shown only where it differs. The procedure runs itself to make them,
$ ! with P1 = RUNS, so that a run's output can go to a file.
$ SELF = F$ENVIRONMENT("PROCEDURE")
$ PASSES = F$INTEGER(P1)
$ IF PASSES .LE. 1 THEN @'SELF' RUNS
$ IF PASSES .LE. 1 THEN GOTO CLEAN
$ @'SELF'/OUTPUT=PASS1.TXT RUNS
$ TYPE PASS1.TXT
$ PASS = 2
$NEXT_RUN:
$ @'SELF'/OUTPUT=PASS.TXT RUNS
$ DIFFERENCES/OUTPUT=NL: PASS1.TXT PASS.TXT
$ SAME = $SEVERITY .EQ. 1
$ IF .NOT. SAME THEN WRITE SYS$OUTPUT "run ", PASS, " of ", PASSES, " differs from the first:"
$ IF .NOT. SAME THEN DIFFERENCES PASS1.TXT PASS.TXT
$ DELETE/NOLOG PASS.TXT;*
$ PASS = PASS + 1
$ IF PASS .LE. PASSES THEN GOTO NEXT_RUN
$ DELETE/NOLOG PASS1.TXT;*
$CLEAN:
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*, SPAWN%.OUT;*, SPAWN3.COM;*
$ EXIT 1
$ !
$RUNS:
$ RUN SPAWNUSE
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ WRITE SYS$OUTPUT "after the run"
$ EXIT 1
