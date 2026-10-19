$ ! PLAN.md Phase 18 step 5a (doc/developer/vax-object-language.md,
$ ! section 16): VaxTrace linked from the object poc wrote, which
$ ! tools/vax-do sent and converted, with poc's runtime assembled by
$ ! MACRO; run as it is, for the traceback of its divide by zero, then
$ ! linked /DEBUG and run under the debugger with TRACE.DBG's commands.
$ ! Step 5b: VAXTRACEG.OBJ, the object poc -g wrote, linked /DEBUG and
$ ! run with SOURCE.DBG's, which show the source; and VaxDescribe,
$ ! built by the procedure poc -build wrote, run. Everything made is
$ ! deleted
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
$ IF S THEN LINK/DEBUG/EXECUTABLE=VAXTRACE.EXE VAXTRACEG.OBJ, POCRTL.OBJ
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "-g build status: ", S
$ IF S THEN DEFINE/USER DBG$INPUT SOURCE.DBG
$ IF S THEN RUN VAXTRACE.EXE
$ IF S THEN WRITE SYS$OUTPUT "-g run status: ", $STATUS
$ IF S THEN @VAXDESCRIBE
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "describe build status: ", S
$ IF S THEN RUN VAXDESCRIBE.EXE
$ IF S THEN WRITE SYS$OUTPUT "describe run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXTRACE.EXE;*,VAXDESCRIBE.EXE;*,VAXDESCRIBE.OPT;*,VAXDESCRIBE.OBJ;*
$ DELETE/NOLOG GARBAGECOLLECTEDHEAP.OBJ;*,RECORDFILES.OBJ;*,LINEOUTPUT.OBJ;*,REALDIGITS.OBJ;*
$ DELETE/NOLOG FORMATTEDTEXT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,OUT.OBJ;*
$ EXIT 1
