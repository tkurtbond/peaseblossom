$ ! PLAN.md Phase 17 step 3 (design section 19.7, proposals 4 to 6):
$ ! REALSUSE.COM (llvm-reals-module's reals.mod) and BEYOND.COM, which
$ ! poc -build wrote, run after poc's runtime is assembled; then each
$ ! image. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @REALSUSE
$ IF S THEN S = $STATUS
$ IF S THEN @BEYOND
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ WRITE SYS$OUTPUT "== reals"
$ RUN REALSUSE.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "== beyond"
$ RUN BEYOND.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*,REALS.OBJ;*,DECIMALTOREAL.OBJ;*
$ DELETE/NOLOG REALSUSE.OBJ;*,REALSUSE.OPT;*,REALSUSE.EXE;*,BEYOND.OBJ;*,BEYOND.OPT;*,BEYOND.EXE;*
$ EXIT 1
