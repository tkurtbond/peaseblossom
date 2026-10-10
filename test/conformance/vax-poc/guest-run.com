$ ! PLAN.md Phase 16 step 4's end: POC.COM, which poc -build wrote for
$ ! poc's own source, run after poc's runtime is assembled; then POC.EXE,
$ ! as a foreign command, with options DCL uppercases, its SYS$ERROR a
$ ! file, printed after its status
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @POC
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ POC :== $'F$ENVIRONMENT("DEFAULT")'POC.EXE
$ OPTIONS = "-help/-h/-version/-target vax-dec-vms -version/" + -
    "-target x86_64-linux-gnu -version/-nosuch"
$ I = 0
$ RUN_ONE:
$ OPTION = F$ELEMENT(I, "/", OPTIONS)
$ IF OPTION .EQS. "/" THEN GOTO DONE
$ UOPTION = F$EDIT(OPTION, "UPCASE")
$ WRITE SYS$OUTPUT "== POC ", UOPTION
$ DEFINE/USER_MODE SYS$ERROR POC.ERR
$ POC 'UOPTION'
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ IF F$SEARCH("POC.ERR") .NES. "" THEN TYPE POC.ERR
$ IF F$SEARCH("POC.ERR") .NES. "" THEN DELETE/NOLOG POC.ERR;*
$ I = I + 1
$ GOTO RUN_ONE
$ DONE:
$ DELETE/SYMBOL/GLOBAL POC
$ CLEAN:
$ ! the objects POC.COM made, as POC.OPT lists them, then the rest
$ IF F$SEARCH("POC.OPT") .EQS. "" THEN GOTO LAST
$ OPEN/READ OPT POC.OPT
$ NEXT_OBJECT:
$ READ/END_OF_FILE=OBJECTS_DONE OPT OBJECT
$ IF F$SEARCH(OBJECT) .NES. "" THEN DELETE/NOLOG 'OBJECT';*
$ GOTO NEXT_OBJECT
$ OBJECTS_DONE:
$ CLOSE OPT
$ LAST:
$ IF F$SEARCH("POCRTL.OBJ") .NES. "" THEN DELETE/NOLOG POCRTL.OBJ;*
$ IF F$SEARCH("POC.OPT") .NES. "" THEN DELETE/NOLOG POC.OPT;*
$ IF F$SEARCH("POC.EXE") .NES. "" THEN DELETE/NOLOG POC.EXE;*
$ EXIT 1
