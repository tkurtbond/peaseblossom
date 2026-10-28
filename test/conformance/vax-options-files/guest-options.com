$ ! vax-options-files (doc/developer/vax-macro32-backend.md, section
$ ! 13.3): POCRTL and SEVEN built from poc's objects, SEVEN's link taking
$ ! the line SEVEN.OPT gave; then VALUE, whose procedure has that line (VALUE.COM),
$ ! and SEVENUSE, built with no options file against the shareable images
$ ! (USESHR.COM) and the object libraries (USEOLB.COM), each run: the
$ ! symbol SEVEN_VALUE has the value 7 only where the line reached the link.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @SEVEN_SETUP
$ @SEVEN_BUILD
$ WRITE SYS$OUTPUT "SEVEN_BUILD: ", $STATUS
$ @VALUE.COM
$ WRITE SYS$OUTPUT "VALUE.COM, with SEVEN.OPT: ", $STATUS
$ RUN VALUE
$ WRITE SYS$OUTPUT "run: ", $STATUS
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
