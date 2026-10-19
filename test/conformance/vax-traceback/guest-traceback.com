$ ! PLAN.md Phase 18 step 5a (doc/developer/vax-object-language.md,
$ ! section 16): VaxTrace linked from the object poc wrote, which
$ ! tools/vax-do sent and converted, with poc's runtime assembled by
$ ! MACRO; run as it is, for the traceback of its divide by zero, then
$ ! linked /DEBUG and run under the debugger with TRACE.DBG's commands.
$ ! Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN LINK/EXECUTABLE=VAXTRACE.EXE VAXTRACE.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXTRACE.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ IF S THEN LINK/DEBUG/EXECUTABLE=VAXTRACE.EXE VAXTRACE.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "debug build status: ", S
$ IF S THEN DEFINE/USER DBG$INPUT TRACE.DBG
$ IF S THEN RUN VAXTRACE.EXE
$ IF S THEN WRITE SYS$OUTPUT "debug run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXTRACE.EXE;*
$ EXIT 1
