$ ! PLAN.md Phase 18 step 6a: the procedure poc -vax-objects -build wrote
$ ! links the objects poc wrote, which tools/vax-do sent and converted,
$ ! with poc's runtime, assembled first; then the image, whose exit status
$ ! is what it computed, as vax-build's is
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VAXBUILD
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXBUILD.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXBUILD.OPT;*,VAXBUILD.EXE;*
$ EXIT 1
