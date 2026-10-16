$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 11): POCRTL,
$ ! VMSDEF and VMSLIB built, then SPAWNUSE and CHAINEDUSE by the procedures
$ ! poc -build wrote, and SPAWNUSE run; it runs CHAINEDUSE, which ends by
$ ! LIB$DO_COMMAND. The lines after the RUN show what follows the chain.
$ ! Everything made is deleted.
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
$ @SPAWNUSE
$ WRITE SYS$OUTPUT "SPAWNUSE built: ", $STATUS
$ @CHAINEDUSE
$ WRITE SYS$OUTPUT "CHAINEDUSE built: ", $STATUS
$ RUN SPAWNUSE
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ WRITE SYS$OUTPUT "after the run"
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*, SPAWN%.OUT;*, SPAWN3.COM;*
$ EXIT 1
