$ ! PLAN.md Phase 17 (design section 20, proposals 8 and 10): FOREND.COM
$ ! (llvm-for-loop-end's forend.mod), which poc -build wrote, run after
$ ! poc's runtime is assembled; then the image. Everything made is
$ ! deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @FOREND
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN FOREND.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG FOREND.OBJ;*,FOREND.OPT;*,FOREND.EXE;*
$ EXIT 1
