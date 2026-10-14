$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 2,
$ ! proposal 8): the libraries POCRTL and VMSDEF built by their
$ ! procedures, then VMSDEFLAYOUT and VMSDEFCALLS by the procedures poc
$ ! -build wrote, against their object libraries, and run, VMSDEFCALLS
$ ! with VMSDEFCALLS.TXT made and POC_VMSDEF_LNM defined as a process
$ ! logical name. Everything made is deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @VMSDEFLAYOUT
$ WRITE SYS$OUTPUT "VMSDEFLAYOUT.COM: ", $STATUS
$ RUN VMSDEFLAYOUT
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ @VMSDEFCALLS
$ WRITE SYS$OUTPUT "VMSDEFCALLS.COM: ", $STATUS
$ CREATE VMSDEFCALLS.TXT
one line
$ DEFINE/PROCESS POC_VMSDEF_LNM "translated value"
$ RUN VMSDEFCALLS
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DEASSIGN/PROCESS POC_VMSDEF_LNM
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*, VMSDEFCALLS.TXT;*
$ EXIT 1
