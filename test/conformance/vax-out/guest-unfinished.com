$ ! PLAN.md Phase 16 step 3: OUTUNFINISHED.COM, which poc -build wrote,
$ ! run after poc's runtime is assembled; then the image, whose line
$ ! without Ln the exit handler writes
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @OUTUNFINISHED
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN OUTUNFINISHED.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,OUTUNFINISHED.OBJ;*,OUTUNFINISHED.OPT;*,OUTUNFINISHED.EXE;*
$ EXIT 1
