$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10): POCRTL,
$ ! and VMSDEF built, then INFOUSE by the procedure poc -build
$ ! wrote, and run. Everything made is deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @INFOUSE
$ WRITE SYS$OUTPUT "INFOUSE built: ", $STATUS
$ RUN INFOUSE
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ EXIT 1
