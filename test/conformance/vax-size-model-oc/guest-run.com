$ ! PLAN.md Phase 16 step 3: VAXSIZEMODEL.COM, which poc -OC -build wrote,
$ ! run after poc's runtime is assembled; then the image, whose exit
$ ! status says which of its checks held
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VAXSIZEMODEL
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXSIZEMODEL.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXSIZEMODEL.OBJ;*,VAXSIZEMODEL.OPT;*,VAXSIZEMODEL.EXE;*
$ EXIT 1
