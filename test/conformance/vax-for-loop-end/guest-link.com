$ ! PLAN.md Phase 18 step 4d (doc/developer/vax-object-language.md,
$ ! section 15.4): llvm-for-loop-end's forend.mod linked from the objects
$ ! poc wrote, which tools/vax-do sent and converted, with poc's runtime
$ ! assembled by MACRO; then the image, which must print what
$ ! guest-run.com's does. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN LINK/EXECUTABLE=FOREND.EXE FOREND.OBJ, OUT.OBJ, LINEOUTPUT.OBJ, -
	FORMATTEDOUTPUT.OBJ, FORMATTEDTEXT.OBJ, REALDIGITS.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN FOREND.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,FOREND.EXE;*
$ EXIT 1
