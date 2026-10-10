$ ! PLAN.md Phase 16 step 3, section 14 item 11: ASSERTS.COM, which poc
$ ! -build wrote, run after poc's runtime is assembled, once for each
$ ! ASSERTMODEn.MAR sent, copied to ASSERTMODE.MAR; then the image, run
$ ! with SYS$ERROR a file, so that the message comes after the output,
$ ! as test.sh prints the LLVM backend's, and the image's status
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ IF .NOT. $STATUS THEN EXIT 1
$ LOOP:
$ F = F$SEARCH("ASSERTMODE%.MAR", 1)
$ IF F .EQS. "" THEN GOTO DONE
$ N = F$EXTRACT(10, 1, F$PARSE(F,,,"NAME"))
$ COPY 'F' ASSERTMODE.MAR
$ @ASSERTS
$ WRITE SYS$OUTPUT "== case ", N, ", build status: ", $STATUS
$ DEFINE/USER_MODE SYS$ERROR ASSERTS.ERR
$ RUN ASSERTS.EXE
$ WRITE SYS$OUTPUT "status: ", $STATUS
$ IF F$SEARCH("ASSERTS.ERR") .NES. "" THEN TYPE ASSERTS.ERR
$ IF F$SEARCH("ASSERTS.ERR") .NES. "" THEN DELETE/NOLOG ASSERTS.ERR;*
$ DELETE/NOLOG ASSERTMODE.MAR;*,ASSERTMODE.OBJ;*,ASSERTS.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,ASSERTS.OPT;*,ASSERTS.EXE;*
$ GOTO LOOP
$ DONE:
$ DELETE/NOLOG POCRTL.OBJ;*
$ EXIT 1
