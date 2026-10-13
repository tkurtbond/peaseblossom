$ ! PLAN.md Phase 17 step 1: VAXLIB's build procedure stops at once, with a
$ ! message, before POCRTL's setup has run; then POCRTL and VAXLIB are
$ ! built, and VAXLIBUSE built by the procedures poc's -build wrote,
$ ! against their shareable images and run, then against their object
$ ! libraries and run. Then the failures a library's user can meet
$ ! (section 18.3, proposal 8), each stopped with VMS's message: USESHR
$ ! run with VAXLIB's image not found, then under VAXLIB relinked, and
$ ! STALE.COM's program, compiled against another VaxLibSums, linked
$ SET NOON
$ DEFINE SYS$ERROR SYS$OUTPUT
$ @VAXLIB_BUILD
$ WRITE SYS$OUTPUT "VAXLIB_BUILD before POCRTL_SETUP: ", $STATUS
$ DEASSIGN SYS$ERROR
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VAXLIB_SETUP
$ @VAXLIB_BUILD
$ WRITE SYS$OUTPUT "VAXLIB_BUILD: ", $STATUS
$ @USESHR.COM
$ WRITE SYS$OUTPUT "USESHR.COM, against the shareable images: ", $STATUS
$ RUN USESHR
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ @USEOLB.COM
$ WRITE SYS$OUTPUT "USEOLB.COM, against the object libraries: ", $STATUS
$ RUN USEOLB
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DEFINE SYS$ERROR SYS$OUTPUT
$ DEASSIGN VAXLIB
$ RUN USESHR
$ WRITE SYS$OUTPUT "run, VAXLIB's image not found: ", $STATUS
$ @VAXLIB_SETUP
$ @VAXLIB_BUILD
$ WRITE SYS$OUTPUT "VAXLIB_BUILD again: ", $STATUS
$ RUN USESHR
$ WRITE SYS$OUTPUT "run, VAXLIB relinked: ", $STATUS
$ @STALE.COM
$ WRITE SYS$OUTPUT "STALE.COM, against another VaxLibSums: ", $STATUS
$ DEASSIGN SYS$ERROR
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
