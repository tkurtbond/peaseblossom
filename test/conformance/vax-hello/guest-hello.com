$ ! PLAN.md Phase 16 step 2: HAND-HELLO.MAR assembled, linked and run; its
$ ! line, then each step's status, go to this procedure's output
$ ON WARNING THEN EXIT $STATUS
$ MACRO/OBJECT=HELLO.OBJ HAND-HELLO.MAR
$ LINK/EXECUTABLE=HELLO.EXE HELLO.OBJ
$ RUN HELLO.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ DELETE/NOLOG HELLO.OBJ;*,HELLO.EXE;*
$ EXIT 1
