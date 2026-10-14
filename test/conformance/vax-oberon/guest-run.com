$ ! PLAN.md Phase 17 step 3 (design section 19.19, proposal 4):
$ ! OBERONUSE.COM and BEYOND.COM (llvm-oberon's programs, oberon renamed),
$ ! which poc -build wrote, run after poc's runtime is assembled; then each
$ ! image as a foreign command, OBERONUSE with llvm-oberon's arguments,
$ ! quoted to keep their case, BEYOND with one of 200 characters, since
$ ! DCL takes a line of at most 255. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @OBERONUSE
$ IF S THEN S = $STATUS
$ IF S THEN @BEYOND
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ WRITE SYS$OUTPUT "== oberon"
$ OBERONUSE :== $SYS$LOGIN:OBERONUSE.EXE
$ OBERONUSE "Name.sub" 12 """a string""" -7 / "x"
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "== beyond"
$ BEYOND :== $SYS$LOGIN:BEYOND.EXE
$ LONG = F$FAO("!199*0") + "7"
$ BEYOND 'LONG'
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/SYMBOL/GLOBAL OBERONUSE
$ DELETE/SYMBOL/GLOBAL BEYOND
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,LINEOUTPUT.OBJ;*,PLATFORM.OBJ;*,FILES.OBJ;*
$ DELETE/NOLOG MODULES.OBJ;*,DECIMALTOREAL.OBJ;*,REALS.OBJ;*,REALDIGITS.OBJ;*,TEXTS.OBJ;*
$ DELETE/NOLOG OBERON.OBJ;*,FORMATTEDTEXT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG OBERONUSE.OBJ;*,OBERONUSE.OPT;*,OBERONUSE.EXE;*
$ DELETE/NOLOG BEYOND.OBJ;*,BEYOND.OPT;*,BEYOND.EXE;*
$ EXIT 1
