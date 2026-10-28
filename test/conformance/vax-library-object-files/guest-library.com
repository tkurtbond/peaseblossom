$ ! vax-library-object-files (doc/developer/vax-macro32-backend.md, section
$ ! 13.1, proposal 6): POCRTL built from poc's objects, then EXT, whose
$ ! procedure inserts its module's object, its part's and the object
$ ! file made from HAND-TWICE.MAR in EXT.OLB and links them into EXT.EXE,
$ ! TWICE and THRICE among its UNIVERSAL= symbols; then EXTUSE built against
$ ! the shareable images (USESHR.COM) and run, then against the object
$ ! libraries (USEOLB.COM) and run.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @EXT_SETUP
$ @EXT_BUILD
$ WRITE SYS$OUTPUT "EXT_BUILD: ", $STATUS
$ @USESHR.COM
$ WRITE SYS$OUTPUT "USESHR.COM, against the shareable images: ", $STATUS
$ RUN USESHR
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ @USEOLB.COM
$ WRITE SYS$OUTPUT "USEOLB.COM, against the object libraries: ", $STATUS
$ RUN USEOLB
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
