$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 7): POCRTL
$ ! and VMSDEF built, then SMGFILE by the procedure poc -build wrote, and
$ ! run; it prints the screens it wrote to SCREEN.LIS. Everything made is
$ ! deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @SMGFILE
$ WRITE SYS$OUTPUT "SMGFILE built: ", $STATUS
$ RUN SMGFILE
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ IF F$SEARCH("SCREEN.LIS") .NES. "" THEN DELETE/NOLOG SCREEN.LIS;*
$ IF F$SEARCH("KEYS.DAT") .NES. "" THEN DELETE/NOLOG KEYS.DAT;*
$ EXIT 1
