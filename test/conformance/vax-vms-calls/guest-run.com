$ ! Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1,
$ ! proposal 8): VMSCALLS.COM, which poc -build wrote, run after poc's
$ ! runtime is assembled; then the image, with POC_VMSCALLS_LNM defined
$ ! as a process logical name for its $TRNLNM. Everything made is deleted
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @VMSCALLS
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE/PROCESS POC_VMSCALLS_LNM "translated value"
$ RUN VMSCALLS
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ DEASSIGN/PROCESS POC_VMSCALLS_LNM
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*
$ DELETE/NOLOG VMSARGUMENTS.OBJ;*,VMSCALLS.OBJ;*,VMSCALLS.OPT;*,VMSCALLS.EXE;*
$ EXIT 1
