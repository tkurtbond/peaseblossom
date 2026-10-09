$ ! PLAN.md Phase 16 step 3: EXTENSIONOUT.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, which prints what
$ ! the LLVM backend's prints
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @EXTENSIONOUT
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN EXTENSIONOUT.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,VAXEXTLIB.OBJ;*,EXTENSIONOUT.OBJ;*,EXTENSIONOUT.OPT;*,EXTENSIONOUT.EXE;*
$ EXIT 1
