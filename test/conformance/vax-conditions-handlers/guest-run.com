$ ! Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
$ ! proposal 8): the libraries POCRTL, VMSDEF (only the generated
$ ! modules VMSLIB and the programs import) and VMSLIB built by their
$ ! procedures, then each program by the procedure poc -build wrote,
$ ! against their object libraries, and run. HANDLERS' SYS$ERROR is a
$ ! file, shown after its output, which there is not if every condition
$ ! was handled.
$ ! Everything made is deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @VMSLIB_SETUP
$ @VMSLIB_BUILD
$ WRITE SYS$OUTPUT "VMSLIB_BUILD: ", $STATUS
$ @HANDLERS
$ @EXITSTATUS
$ WRITE SYS$OUTPUT "programs built: ", $STATUS
$ !
$ WRITE SYS$OUTPUT "== Handlers"
$ DEFINE/USER_MODE SYS$ERROR HANDLERS.ERR
$ RUN HANDLERS
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ IF F$SEARCH("HANDLERS.ERR") .EQS. "" THEN WRITE SYS$OUTPUT "nothing on SYS$ERROR"
$ IF F$SEARCH("HANDLERS.ERR") .NES. "" THEN TYPE HANDLERS.ERR
$ WRITE SYS$OUTPUT "== ExitStatus"
$ RUN EXITSTATUS
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ IF F$SEARCH("HANDLERS.ERR") .NES. "" THEN DELETE/NOLOG HANDLERS.ERR;*
$ EXIT 1
