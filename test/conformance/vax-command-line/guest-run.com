$ ! PLAN.md Phase 16 step 4: ARGSOUT.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, as a foreign
$ ! command with arguments of each kind DCL has (DCL Dictionary, DCL1-5),
$ ! a tab before the last one, and as RUN runs it, with none
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @ARGSOUT
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ ARGSOUT :== $SYS$LOGIN:ARGSOUT.EXE
$ IF S THEN ARGSOUT -o "Hello"  mixedCase a"b"c "x""y" "" "two  spaces"	tab
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ IF S THEN RUN ARGSOUT.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/SYMBOL/GLOBAL ARGSOUT
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,MODULES.OBJ;*,ARGSOUT.OBJ;*,ARGSOUT.OPT;*,ARGSOUT.EXE;*
$ EXIT 1
