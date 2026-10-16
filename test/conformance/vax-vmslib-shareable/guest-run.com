$ ! PLAN.md Phase 17 step 8 (the plan's second gap): POCRTL, VMSDEF (the
$ ! generated modules VMSLIB imports, only) and VMSLIB built by their
$ ! procedures, then SHAREUSE by the two procedures poc -build wrote, one
$ ! against the libraries' object libraries and one against their
$ ! shareable images, and both run. Everything made is deleted.
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
$ @SHAREOLB
$ WRITE SYS$OUTPUT "SHAREOLB, against the object libraries: ", $STATUS
$ @SHARESHR
$ WRITE SYS$OUTPUT "SHARESHR, against the shareable images: ", $STATUS
$ WRITE SYS$OUTPUT "== SHAREOLB"
$ RUN SHAREOLB
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ WRITE SYS$OUTPUT "== SHARESHR"
$ RUN SHARESHR
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
