$ ! Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
$ ! proposals 2 and 8): ASTHEAP.COM and ASTNOIMPORT.COM, which poc -build
$ ! wrote, run after poc's runtime is assembled; then ASTHEAP's image,
$ ! three times, and ASTNOIMPORT's, three times, its SYS$ERROR, where the
$ ! trap's message goes, a file shown after each run. Everything made is
$ ! deleted
$ SET NOON
$ IF P1 .EQS. "RUNS" THEN GOTO RUNS
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @ASTHEAP
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ @ASTNOIMPORT
$ WRITE SYS$OUTPUT "AstNoImport build status: ", $STATUS
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
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*
$ DELETE/NOLOG ASTHEAP.OBJ;*,ASYNCHRONOUSTRAPS.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,ASTHEAP.OPT;*,ASTHEAP.EXE;*
$ IF F$SEARCH("ASTNOIMPORT.OBJ") .NES. "" THEN DELETE/NOLOG ASTNOIMPORT.OBJ;*
$ IF F$SEARCH("ASTNOIMPORT.OPT") .NES. "" THEN DELETE/NOLOG ASTNOIMPORT.OPT;*
$ IF F$SEARCH("ASTNOIMPORT.EXE") .NES. "" THEN DELETE/NOLOG ASTNOIMPORT.EXE;*
$ EXIT 1
$ !
$RUNS:
$ RUN ASTHEAP
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ RUN ASTHEAP
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ RUN ASTHEAP
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ N = 0
$ NOIMPORT:
$ N = N + 1
$ DEFINE/USER_MODE SYS$ERROR ASTNOIMPORT.ERR
$ RUN ASTNOIMPORT
$ WRITE SYS$OUTPUT "AstNoImport run status: ", $STATUS
$ IF F$SEARCH("ASTNOIMPORT.ERR") .NES. "" THEN TYPE ASTNOIMPORT.ERR
$ IF F$SEARCH("ASTNOIMPORT.ERR") .NES. "" THEN DELETE/NOLOG ASTNOIMPORT.ERR;*
$ IF N .LT. 3 THEN GOTO NOIMPORT
$ EXIT 1
