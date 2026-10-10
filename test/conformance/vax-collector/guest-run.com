$ ! PLAN.md Phase 16 step 4: COLLECTOUT.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, which prints what
$ ! the LLVM backend's prints
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @COLLECTOUT
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN COLLECTOUT.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,COLLECTOUT.OBJ;*,COLLECTOUT.OPT;*,COLLECTOUT.EXE;*
$ EXIT 1
