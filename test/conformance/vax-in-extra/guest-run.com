$ ! PLAN.md Phase 17 step 3 (design section 19.11, proposals 1, 3 and 5):
$ ! INEXTRA.COM (llvm-in-extra's inextra.mod), which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, with SYS$INPUT its
$ ! input file. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @INEXTRA
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE/USER SYS$INPUT INPUT.TXT
$ RUN INEXTRA.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG IN.OBJ;*,FORMATTEDINPUT.OBJ;*,DECIMALTOREAL.OBJ;*,PLATFORM.OBJ;*
$ DELETE/NOLOG INEXTRA.OBJ;*,INEXTRA.OPT;*,INEXTRA.EXE;*,INPUT.TXT;*
$ EXIT 1
