$ ! Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
$ ! proposal 8): the libraries POCRTL, VMSDEF (only the generated
$ ! modules VMSLIB and the programs import) and VMSLIB built by their
$ ! procedures, then each program by the procedure poc -build wrote,
$ ! against their object libraries, and run. ASTTRAP's SYS$ERROR, where
$ ! the trap's message goes, is a file, shown after its output. Everything
$ ! made is deleted.
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
$ @ASTORDER
$ @ASTTRAP
$ WRITE SYS$OUTPUT "programs built: ", $STATUS
$ !
$ WRITE SYS$OUTPUT "== AstOrder"
$ RUN ASTORDER
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ WRITE SYS$OUTPUT "== AstTrap"
$ DEFINE/USER_MODE SYS$ERROR ASTTRAP.ERR
$ RUN ASTTRAP
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ TYPE ASTTRAP.ERR
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*, ASTTRAP.ERR;*
$ EXIT 1
