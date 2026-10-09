$ ! PLAN.md Phase 16 step 2: the procedures poc wrote run, after poc's
$ ! runtime is assembled: VAXBUILDSUMS.COM (-compile's), then VAXBUILD.COM
$ ! (-build's); then the image, whose exit status is what it computed
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VAXBUILDSUMS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "compile status: ", S
$ IF S THEN @VAXBUILD
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXBUILD.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG POCRTL.OBJ;*,VAXBUILD.OBJ;*,VAXBUILDSUMS.OBJ;*,VAXBUILD.OPT;*,VAXBUILD.EXE;*
$ EXIT 1
