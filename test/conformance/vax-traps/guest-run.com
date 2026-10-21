$ ! PLAN.md Phase 16 step 3, section 14 item 10: TRAPS.COM, which poc
$ ! -build wrote, run after poc's runtime is assembled, once for each
$ ! TRAPMODEn.MAR sent, copied to TRAPMODE.MAR; then the image, run with
$ ! SYS$ERROR a file, so that the message comes after the output, as
$ ! test.sh prints the LLVM backend's, and the image's status
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ IF .NOT. $STATUS THEN EXIT 1
$ ! Built from poc's objects (vax_build), TRAPMODEn.OBJ were sent instead
$ ! and the modules' objects are kept for every case
$ KIND = "MAR"
$ IF F$SEARCH("TRAPS.MAR") .EQS. "" THEN KIND = "OBJ"
$ LOOP:
$ F = F$SEARCH("TRAPMODE%.''KIND'", 1)
$ IF F .EQS. "" THEN GOTO DONE
$ N = F$EXTRACT(8, 1, F$PARSE(F,,,"NAME"))
$ COPY 'F' TRAPMODE.'KIND'
$ @TRAPS
$ WRITE SYS$OUTPUT "== case ", N, ", build status: ", $STATUS
$ DEFINE/USER_MODE SYS$ERROR TRAPS.ERR
$ RUN TRAPS.EXE
$ WRITE SYS$OUTPUT "status: ", $STATUS
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN TYPE TRAPS.ERR
$ IF F$SEARCH("TRAPS.ERR") .NES. "" THEN DELETE/NOLOG TRAPS.ERR;*
$ IF KIND .EQS. "MAR" THEN DELETE/NOLOG TRAPMODE.OBJ;*,TRAPS.OBJ;*,TRAPLIB.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*
$ DELETE/NOLOG TRAPMODE.'KIND';*,TRAPS.OPT;*,TRAPS.EXE;*
$ GOTO LOOP
$ DONE:
$ DELETE/NOLOG POCRTL.OBJ;*
$ EXIT 1
