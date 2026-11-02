$ ! The predeclared unsigned types (doc/developer/predeclared-unsigned-types.md,
$ ! step 4): CARDINAL.COM, which poc -build wrote under the model the test
$ ! gives, run after poc's runtime is assembled; then the image. Everything
$ ! made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @CARDINAL
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ RUN CARDINAL.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*
$ DELETE/NOLOG LINEOUTPUT.OBJ;*,OUT.OBJ;*,REALDIGITS.OBJ;*
$ DELETE/NOLOG CARDINAL.OBJ;*,CARDINAL.OPT;*,CARDINAL.EXE;*
$ EXIT 1
