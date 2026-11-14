$ ! vax-coroutines-traps (doc/developer/coroutines.md, Phase 4): poc's
$ ! runtime and Coroutines' switch, COROUTINESWITCH.MAR, are assembled;
$ ! COROUTINETRAPS.COM, which poc -build wrote, links the program with the
$ ! switch by its -link line; then the image runs once for each case, 1 to
$ ! 14, as a foreign command given the case, its SYS$ERROR, where a trap's
$ ! message goes, a file shown after the run. Case 14 overflows a stack,
$ ! and VMS's two register dumps, whose addresses any change to the code
$ ! moves, go to SYS$OUTPUT and SYS$ERROR both: its output is a file too,
$ ! of which only the program's own lines are shown, and its SYS$ERROR is
$ ! searched for the access violation. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN MACRO/OBJECT COROUTINESWITCH.MAR
$ IF S THEN S = $STATUS
$ IF S THEN @COROUTINETRAPS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ TRAPS = "$" + F$ENVIRONMENT("DEFAULT") + "COROUTINETRAPS.EXE"
$ N = 0
$NEXT_CASE:
$ N = N + 1
$ WRITE SYS$OUTPUT "== ", N
$ IF N .EQ. 14 THEN GOTO OVERFLOW
$ DEFINE/USER_MODE SYS$ERROR TRAPS.ERR
$ TRAPS 'N'
$ WRITE SYS$OUTPUT "status: ", $STATUS
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN TYPE TRAPS.ERR
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN DELETE/NOLOG TRAPS.ERR;*
$ GOTO NEXT_CASE
$OVERFLOW:
$ DEFINE/USER_MODE SYS$OUTPUT TRAPS.OUT
$ DEFINE/USER_MODE SYS$ERROR TRAPS.ERR
$ TRAPS 'N'
$ WRITE SYS$OUTPUT "status: ", $STATUS
$ SEARCH TRAPS.OUT "a coroutine recurses","finalized"
$ SEARCH/OUTPUT=NL: TRAPS.ERR "%SYSTEM-F-ACCVIO"
$ IF $SEVERITY .EQ. 1 THEN WRITE SYS$OUTPUT "an access violation reported"
$ DELETE/NOLOG TRAPS.OUT;*,TRAPS.ERR;*
$CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,COROUTINESWITCH.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*
$ DELETE/NOLOG REALDIGITS.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,COROUTINES.OBJ;*,ASYNCHRONOUSTRAPS.OBJ;*
$ DELETE/NOLOG PLATFORM.OBJ;*,MODULES.OBJ;*,COROUTINETRAPS.OBJ;*
$ IF F$SEARCH("COROUTINETRAPS.OPT") .NES. "" THEN DELETE/NOLOG COROUTINETRAPS.OPT;*
$ IF F$SEARCH("COROUTINETRAPS.EXE") .NES. "" THEN DELETE/NOLOG COROUTINETRAPS.EXE;*
$ EXIT 1
