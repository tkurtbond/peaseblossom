$ ! Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
$ ! proposal 8): the libraries POCRTL, VMSDEF (only the generated
$ ! modules VMSLIB and the programs import) and VMSLIB built by their
$ ! procedures, then each program by the procedure poc -build wrote,
$ ! against their object libraries, and run. HANDLERS' SYS$ERROR is a
$ ! file, shown after its output, which there is not if every condition
$ ! was handled.
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
$ @HANDLERS
$ @EXITSTATUS
$ WRITE SYS$OUTPUT "programs built: ", $STATUS
$ !
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
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ IF F$SEARCH("HANDLERS.ERR") .NES. "" THEN DELETE/NOLOG HANDLERS.ERR;*
$ EXIT 1
$ !
$RUNS:
$ WRITE SYS$OUTPUT "== Handlers"
$ DEFINE/USER_MODE SYS$ERROR HANDLERS.ERR
$ RUN HANDLERS
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ IF F$SEARCH("HANDLERS.ERR") .EQS. "" THEN WRITE SYS$OUTPUT "nothing on SYS$ERROR"
$ IF F$SEARCH("HANDLERS.ERR") .NES. "" THEN TYPE HANDLERS.ERR
$ WRITE SYS$OUTPUT "== ExitStatus"
$ RUN EXITSTATUS
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ EXIT 1
