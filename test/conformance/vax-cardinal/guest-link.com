$ ! PLAN.md Phase 18 step 4d (doc/developer/vax-object-language.md,
$ ! section 15.4): llvm-cardinal's cardinal.mod linked from the objects
$ ! poc wrote, which tools/vax-do sent and converted, with poc's runtime
$ ! assembled by MACRO; then the image, with SYS$ERROR a file, typed
$ ! after it, which must print what guest-run.com's does. Everything
$ ! made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN LINK/EXECUTABLE=CARDINAL.EXE CARDINAL.OBJ, CARDINALTYPES.OBJ, -
	DECIMALTOREAL.OBJ, ERR.OBJ, FORMATTEDINPUT.OBJ, FORMATTEDOUTPUT.OBJ, -
	FORMATTEDTEXT.OBJ, INSTR.OBJ, LINEOUTPUT.OBJ, OUT.OBJ, OUTSTR.OBJ, -
	REALDIGITS.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE/USER SYS$ERROR CARDINAL-ERR.TXT
$ RUN CARDINAL.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "-- SYS$ERROR"
$ TYPE CARDINAL-ERR.TXT
$ CLEAN:
$ IF F$SEARCH("CARDINAL-ERR.TXT") .NES. "" THEN DELETE/NOLOG CARDINAL-ERR.TXT;*
$ DELETE/NOLOG POCRTL.OBJ;*,CARDINAL.EXE;*
$ EXIT 1
