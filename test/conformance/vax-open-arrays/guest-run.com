$ ! PLAN.md Phase 16 step 3: VAXOPENARRAYS.COM, which poc -build wrote (-O2,
$ ! then -OC), run after poc's runtime is assembled; then the image, whose
$ ! exit status says which of its checks held
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VAXOPENARRAYS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXOPENARRAYS.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXOPENARRAYS.OBJ;*,VAXOPENARRAYS.OPT;*,VAXOPENARRAYS.EXE;*
$ EXIT 1
