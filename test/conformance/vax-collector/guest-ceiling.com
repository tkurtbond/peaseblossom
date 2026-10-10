$ ! PLAN.md Phase 16 step 4: HEAPCEILING.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, whose heap stops at
$ ! the ceiling the collector takes from the paging file quota
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @HEAPCEILING
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN HEAPCEILING.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,HEAPCEILING.OBJ;*,HEAPCEILING.OPT;*,HEAPCEILING.EXE;*
$ EXIT 1
