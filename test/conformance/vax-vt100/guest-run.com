$ ! PLAN.md Phase 17 step 3 (design section 19.17, proposal 4):
$ ! VT100SAME.COM and VT100DIFF.COM (llvm-vt100's programs), which poc
$ ! -build wrote, run after poc's runtime is assembled; then each image,
$ ! its output to this procedure's, a file. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VT100SAME
$ IF S THEN S = $STATUS
$ IF S THEN @VT100DIFF
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ WRITE SYS$OUTPUT "== vt100same"
$ RUN VT100SAME.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ WRITE SYS$OUTPUT "== vt100diff"
$ RUN VT100DIFF.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,OUT.OBJ;*
$ DELETE/NOLOG VT100.OBJ;*
$ DELETE/NOLOG VT100SAME.OBJ;*,VT100SAME.OPT;*,VT100SAME.EXE;*
$ DELETE/NOLOG VT100DIFF.OBJ;*,VT100DIFF.OPT;*,VT100DIFF.EXE;*
$ EXIT 1
