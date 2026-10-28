$ ! vax-external-variable (doc/developer/language-extensions.md, "External
$ ! variables"): poc's runtime is assembled; HAND-EXTDATA.MAR, the storage
$ ! of the program's external variables, is assembled, and HAND-EXTSHR.MAR
$ ! linked as the shareable image EXTSHR.EXE, found by the logical name
$ ! EXTSHR, which makes EXTSHR_LIMIT universal; then
$ ! VAXEXTERNALVARIABLE.COM, poc's -build procedure, links the program with
$ ! them by its -link lines, and the image runs, its exit status what its
$ ! checks added up to
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ MACRO/OBJECT HAND-EXTDATA.MAR
$ MACRO/OBJECT HAND-EXTSHR.MAR
$ CREATE EXTSHR.OPT
HAND-EXTSHR.OBJ
UNIVERSAL=EXTSHR_LIMIT
$ LINK/SHAREABLE=EXTSHR.EXE EXTSHR.OPT/OPTIONS
$ WRITE SYS$OUTPUT "EXTSHR.EXE status: ", $STATUS
$ DEFINE EXTSHR 'F$ENVIRONMENT("DEFAULT")'EXTSHR.EXE
$ @VAXEXTERNALVARIABLE
$ S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXEXTERNALVARIABLE.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DEASSIGN EXTSHR
$ DELETE/NOLOG *.OBJ;*, *.OPT;*, *.EXE;*
$ EXIT 1
