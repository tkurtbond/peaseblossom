$ ! PLAN.md Phase 17 step 3 (design section 19.9, proposals 3 and 4):
$ ! OUTSTRUSE.COM (llvm-outstr's outstr.mod), which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image. Everything made is
$ ! deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @OUTSTRUSE
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN OUTSTRUSE.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*,OUTSTR.OBJ;*
$ DELETE/NOLOG OUTSTRUSE.OBJ;*,OUTSTRUSE.OPT;*,OUTSTRUSE.EXE;*
$ EXIT 1
