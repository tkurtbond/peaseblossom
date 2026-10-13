$ ! PLAN.md Phase 17 step 3 (design section 19.7, proposal 6): DIGITS.COM,
$ ! which poc -build wrote, run after poc's runtime is assembled; then the
$ ! image. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @DIGITS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ RUN DIGITS.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG DIGITS.OBJ;*,DIGITS.OPT;*,DIGITS.EXE;*
$ EXIT 1
