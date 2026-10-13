$ ! PLAN.md Phase 17 step 3 (design section 19.5): COMMANDS.COM and the
$ ! other four, which poc -build wrote, run after poc's runtime is
$ ! assembled; then each image, in llvm-modules-commands' order, what it
$ ! writes to SYS$ERROR typed after its output and before its status,
$ ! where Unix's 2>&1 shows it. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @COMMANDS
$ IF S THEN S = $STATUS
$ IF S THEN @HALTCODE
$ IF S THEN S = $STATUS
$ IF S THEN @HALT
$ IF S THEN S = $STATUS
$ IF S THEN @ASSERTCODE
$ IF S THEN S = $STATUS
$ IF S THEN @ASSERTZERO
$ IF S THEN S = $STATUS
$ IF .NOT. S THEN WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ P = "COMMANDS"
$ GOSUB RUN_ONE
$ P = "HALTCODE"
$ GOSUB RUN_ONE
$ P = "HALT"
$ GOSUB RUN_ONE
$ P = "ASSERTCODE"
$ GOSUB RUN_ONE
$ P = "ASSERTZERO"
$ GOSUB RUN_ONE
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,GARBAGECOLLECTEDHEAP.OBJ;*,LINEOUTPUT.OBJ;*,PLATFORM.OBJ;*,MODULES.OBJ;*,OUT.OBJ;*,GREETER.OBJ;*
$ DELETE/NOLOG COMMANDS.OBJ;*,COMMANDS.OPT;*,COMMANDS.EXE;*,HALTCODE.OBJ;*,HALTCODE.OPT;*,HALTCODE.EXE;*
$ DELETE/NOLOG HALT.OBJ;*,HALT.OPT;*,HALT.EXE;*,ASSERTCODE.OBJ;*,ASSERTCODE.OPT;*,ASSERTCODE.EXE;*
$ DELETE/NOLOG ASSERTZERO.OBJ;*,ASSERTZERO.OPT;*,ASSERTZERO.EXE;*
$ EXIT 1
$ ! the image P, its name in lowercase first, as llvm-modules-commands'
$ ! "== <name>"
$ RUN_ONE:
$ WRITE SYS$OUTPUT "== ", F$EDIT(P, "LOWERCASE")
$ DEFINE/USER_MODE SYS$ERROR 'P'.ERR
$ RUN 'P'
$ S = $STATUS
$ IF F$SEARCH(P + ".ERR") .NES. "" THEN TYPE 'P'.ERR
$ IF F$SEARCH(P + ".ERR") .NES. "" THEN DELETE/NOLOG 'P'.ERR;*
$ WRITE SYS$OUTPUT "status: ", S
$ RETURN
