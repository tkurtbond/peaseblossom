$ ! BUGS.md, 2026-10-28: POCRTL and HOLDLIB built from poc's objects, by
$ ! the procedures poc -vax-objects -library wrote, then HOLDUSE linked
$ ! against their object libraries (HOLDUSE.COM) and run: the things it
$ ! holds only in a local must survive HoldLib.Churn's collections
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @HOLDLIB_SETUP
$ @HOLDLIB_BUILD
$ WRITE SYS$OUTPUT "HOLDLIB_BUILD: ", $STATUS
$ @HOLDUSE.COM
$ WRITE SYS$OUTPUT "HOLDUSE.COM: ", $STATUS
$ RUN HOLDUSE
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
