$ ! poc -link for vax-dec-vms (PLAN.md, "Ongoing implementation
$ ! enhancements"): poc's runtime is assembled; HAND-FOREIGN.MAR is put in
$ ! the object library FOREIGN.OLB and HAND-FORSHR.MAR linked as the
$ ! shareable image FORSHR.EXE, found by the logical name FORSHR; then
$ ! VAXLINK.COM, poc's -build procedure, links the program with them by
$ ! its -link lines alone, and the image runs, its exit status what it
$ ! computed
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ MACRO/OBJECT HAND-FOREIGN.MAR
$ LIBRARY/CREATE FOREIGN.OLB HAND-FOREIGN.OBJ
$ MACRO/OBJECT HAND-FORSHR.MAR
$ CREATE FORSHR.OPT
HAND-FORSHR.OBJ
UNIVERSAL=FORSHR_THRICE
$ LINK/SHAREABLE=FORSHR.EXE FORSHR.OPT/OPTIONS
$ WRITE SYS$OUTPUT "FORSHR.EXE status: ", $STATUS
$ DEFINE FORSHR 'F$ENVIRONMENT("DEFAULT")'FORSHR.EXE
$ @VAXLINK
$ S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF S THEN RUN VAXLINK.EXE
$ IF S THEN WRITE SYS$OUTPUT "run status: ", $STATUS
$ DEASSIGN FORSHR
$ DELETE/NOLOG *.OBJ;*, FOREIGN.OLB;*, *.OPT;*, *.EXE;*
$ EXIT 1
