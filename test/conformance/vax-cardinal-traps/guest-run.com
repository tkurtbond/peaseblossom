$ ! PLAN.md Phase 17 (design section 20, proposals 1, 6 and 10):
$ ! BIGINDEX.COM, OPENINDEX.COM, SHORTRANGE.COM and CHRRANGE.COM
$ ! (llvm-cardinal-traps' programs), which poc -build wrote, run after
$ ! poc's runtime is assembled; then each image, with SYS$ERROR a file,
$ ! so that the message comes after the output, and its status.
$ ! Everything made from MACRO-32 is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ IF .NOT. $STATUS THEN EXIT 1
$ ! Built from poc's objects (vax_build), the modules' objects were sent
$ ! and are kept for every program
$ KIND = "MAR"
$ IF F$SEARCH("BIGINDEX.MAR") .EQS. "" THEN KIND = "OBJ"
$ N = 0
$ LOOP:
$ NAME = F$ELEMENT(N, ",", "BIGINDEX,OPENINDEX,SHORTRANGE,CHRRANGE")
$ IF NAME .EQS. "," THEN GOTO DONE
$ @'NAME'
$ WRITE SYS$OUTPUT "== ", F$EDIT(NAME, "LOWERCASE"), ", build status: ", $STATUS
$ DEFINE/USER_MODE SYS$ERROR TRAPS.ERR
$ RUN 'NAME'.EXE
$ WRITE SYS$OUTPUT "status: ", $STATUS
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN TYPE TRAPS.ERR
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN DELETE/NOLOG TRAPS.ERR;*
$ DELETE/NOLOG 'NAME'.OBJ;*,'NAME'.OPT;*,'NAME'.EXE;*
$ IF KIND .EQS. "MAR" THEN DELETE/NOLOG OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*
$ IF KIND .EQS. "MAR" .AND. F$SEARCH("GARBAGECOLLECTEDHEAP.OBJ") .NES. "" THEN DELETE/NOLOG GARBAGECOLLECTEDHEAP.OBJ;*
$ N = N + 1
$ GOTO LOOP
$ DONE:
$ DELETE/NOLOG POCRTL.OBJ;*
$ EXIT 1
