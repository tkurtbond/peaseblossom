$ ! PLAN.md Phase 16 step 3: OUTBASICS.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, which prints what
$ ! the LLVM backend's prints
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @OUTBASICS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN OUTBASICS.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,OUTBASICS.OBJ;*,OUTBASICS.OPT;*,OUTBASICS.EXE;*
$ EXIT 1
