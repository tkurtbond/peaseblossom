$ ! vax-coroutines-examples (doc/developer/coroutines.md, Phase 5): poc's
$ ! runtime and Coroutines' switch, COROUTINESWITCH.MAR, are assembled;
$ ! then WORDSETS.COM and QUEENS.COM, which poc -build wrote, link the two
$ ! programs, and each runs as a foreign command, as the User's Guide
$ ! says. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN MACRO/OBJECT COROUTINESWITCH.MAR
$ IF S THEN S = $STATUS
$ IF S THEN @WORDSETS
$ IF S THEN S = $STATUS
$ IF S THEN @QUEENS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ WORDSETS :== $SYS$LOGIN:WORDSETS.EXE
$ QUEENS :== $SYS$LOGIN:QUEENS.EXE
$ WRITE SYS$OUTPUT "$ wordsets memo.txt words.txt"
$ WORDSETS memo.txt words.txt
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ wordsets memo.txt"
$ WORDSETS memo.txt
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 5 -k 3 2"
$ QUEENS -N 5 -K 3 2
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 4 all"
$ QUEENS -N 4 ALL
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens all"
$ QUEENS ALL
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 6 all"
$ QUEENS -N 6 ALL
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 10 -k 5 3"
$ QUEENS -N 10 -K 5 3
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 26 -k 26 1"
$ QUEENS -N 26 -K 26 1
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "$ queens -n 27"
$ QUEENS -N 27
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/SYMBOL/GLOBAL WORDSETS
$ DELETE/SYMBOL/GLOBAL QUEENS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,COROUTINESWITCH.OBJ;*,WORDSETS.OBJ;*,QUEENS.OBJ;*,COROUTINES.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*
$ DELETE/NOLOG LINEOUTPUT.OBJ;*,PLATFORM.OBJ;*,FILES.OBJ;*,MODULES.OBJ;*,ARGS.OBJ;*,DECIMALTOREAL.OBJ;*
$ DELETE/NOLOG FORMATTEDINPUT.OBJ;*,IN.OBJ;*,REALDIGITS.OBJ;*,FORMATTEDTEXT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG WORDSETS.OPT;*,WORDSETS.EXE;*,QUEENS.OPT;*,QUEENS.EXE;*
$ EXIT 1
