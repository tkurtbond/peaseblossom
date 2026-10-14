$ ! PLAN.md Phase 17 step 3 (design section 19.15, proposal 5):
$ ! MATHTEST.COM and MATHLTEST.COM (llvm-math's and llvm-mathl's
$ ! programs), which poc -build wrote, run after poc's runtime is
$ ! assembled; then each image. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @MATHTEST
$ IF S THEN S = $STATUS
$ IF S THEN @MATHLTEST
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ WRITE SYS$OUTPUT "== mathtest"
$ RUN MATHTEST.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "== mathltest"
$ RUN MATHLTEST.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG MATH.OBJ;*,MATHL.OBJ;*
$ DELETE/NOLOG MATHTEST.OBJ;*,MATHTEST.OPT;*,MATHTEST.EXE;*
$ DELETE/NOLOG MATHLTEST.OBJ;*,MATHLTEST.OPT;*,MATHLTEST.EXE;*
$ EXIT 1
