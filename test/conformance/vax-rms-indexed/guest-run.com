$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 6): POCRTL
$ ! and VMSDEF built, then RMSINDEXED by the procedure poc -build wrote,
$ ! and run; it deletes the files it makes when it closes them, and
$ ! F$SEARCH shows that none is left. Everything made is deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @RMSINDEXED
$ WRITE SYS$OUTPUT "RMSINDEXED built: ", $STATUS
$ RUN RMSINDEXED
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ IF F$SEARCH("PARTS.DAT") .NES. "" THEN WRITE SYS$OUTPUT "PARTS.DAT is left"
$ IF F$SEARCH("SLOTS.DAT") .NES. "" THEN WRITE SYS$OUTPUT "SLOTS.DAT is left"
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*
$ IF F$SEARCH("PARTS.DAT") .NES. "" THEN DELETE/NOLOG PARTS.DAT;*
$ IF F$SEARCH("SLOTS.DAT") .NES. "" THEN DELETE/NOLOG SLOTS.DAT;*
$ EXIT 1
