$ ! PLAN.md Phase 18 step 5c (doc/developer/vax-object-language.md,
$ ! section 16.7): VaxDebug linked /DEBUG from the object poc -g wrote,
$ ! which tools/vax-do sent and converted, with poc's runtime assembled
$ ! by MACRO, and run under the debugger with DEBUG.DBG's commands,
$ ! which show and change its variables and show its constants. Step
$ ! 5d: VaxDebugTypes likewise, with TYPES.DBG's, which show and change
$ ! its records, arrays, pointers, sets and open arrays. Everything made
$ ! is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN LINK/DEBUG/EXECUTABLE=VAXDEBUG.EXE VAXDEBUG.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "debug build status: ", S
$ IF S THEN DEFINE/USER DBG$INPUT DEBUG.DBG
$ IF S THEN RUN VAXDEBUG.EXE
$ IF S THEN WRITE SYS$OUTPUT "debug run status: ", $STATUS
$ IF S THEN LINK/DEBUG/EXECUTABLE=VAXDEBUGTYPES.EXE VAXDEBUGTYPES.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "types build status: ", S
$ IF S THEN DEFINE/USER DBG$INPUT TYPES.DBG
$ IF S THEN RUN VAXDEBUGTYPES.EXE
$ IF S THEN WRITE SYS$OUTPUT "types run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXDEBUG.EXE;*,VAXDEBUGTYPES.EXE;*
$ EXIT 1
