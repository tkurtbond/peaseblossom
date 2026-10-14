$ ! PLAN.md Phase 17 step 3 (design section 19.17, proposal 4):
$ ! ARGSTEST.COM (llvm-args' program), which poc -build wrote, run after
$ ! poc's runtime is assembled; then the image as a foreign command, with
$ ! ARGSTEST_SET defined as a logical name, ARGSTEST_EMPTY as a global
$ ! symbol defined empty and ARGSTEST_NUMBER as a local numeric symbol
$ ! (section 19.19, proposals 3 and 4), and ARGSTEST_UNSET not.
$ ! Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @ARGSTEST
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE/PROCESS ARGSTEST_SET "value"
$ ARGSTEST_EMPTY == ""
$ ARGSTEST_NUMBER = 12
$ ARGSTEST :== $SYS$LOGIN:ARGSTEST.EXE
$ ARGSTEST "alpha" "" 42 -7 "x9"
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/SYMBOL/GLOBAL ARGSTEST
$ DELETE/SYMBOL/GLOBAL ARGSTEST_EMPTY
$ DELETE/SYMBOL/LOCAL ARGSTEST_NUMBER
$ DEASSIGN/PROCESS ARGSTEST_SET
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*
$ DELETE/NOLOG MODULES.OBJ;*,PLATFORM.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,ARGS.OBJ;*
$ DELETE/NOLOG ARGSTEST.OBJ;*,ARGSTEST.OPT;*,ARGSTEST.EXE;*
$ EXIT 1
