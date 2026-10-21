$ ! PLAN.md Phase 18 step 6b: POCRTL and VAXLIB built from poc's own
$ ! objects, which tools/vax-do sent and converted, by the procedures
$ ! poc -vax-objects -library wrote (POCRTL's assembles only PocRtl.mar);
$ ! then VAXLIBUSE built against their shareable images from its object
$ ! (USESHR.COM, by poc -vax-objects -build) and run, then against their
$ ! object libraries from its MACRO-32 (USEOLB.COM, by poc -build) and run
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VAXLIB_SETUP
$ @VAXLIB_BUILD
$ WRITE SYS$OUTPUT "VAXLIB_BUILD: ", $STATUS
$ @USESHR.COM
$ WRITE SYS$OUTPUT "USESHR.COM, from objects, against the shareable images: ", $STATUS
$ RUN USESHR
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ @USEOLB.COM
$ WRITE SYS$OUTPUT "USEOLB.COM, from MACRO-32, against the object libraries: ", $STATUS
$ RUN USEOLB
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
