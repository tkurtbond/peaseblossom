$ ! PLAN.md Phase 17 step 3: PLATFORMFILES.COM, which poc -build wrote,
$ ! run after poc's runtime is assembled; then the image, with the
$ ! logical name PLATFORM_TEST_VALUE, the directory [.PFSUB], the
$ ! variable-length file PFVAR.TXT and two lines of input. The program
$ ! ends with [.PFSUB] its default directory, which an exit handler puts
$ ! back, and SYS$DISK defined in user mode, which image rundown deletes:
$ ! both are checked after. Everything made is deleted
$ SET NOON
$ HERE = F$ENVIRONMENT("DEFAULT")
$ DISK = F$TRNLNM("SYS$DISK")
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @PLATFORMFILES
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE PLATFORM_TEST_VALUE "files"
$ CREATE/DIRECTORY [.PFSUB]
$ CREATE PFVAR.TXT
word
something
$ RUN PLATFORMFILES
first line
second
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ IF F$ENVIRONMENT("DEFAULT") .EQS. HERE THEN WRITE SYS$OUTPUT "default directory put back"
$ IF F$TRNLNM("SYS$DISK") .EQS. DISK THEN WRITE SYS$OUTPUT "SYS$DISK as it was"
$ SET DEFAULT 'HERE'
$ DEASSIGN PLATFORM_TEST_VALUE
$ IF F$SEARCH("[.PFSUB]*.*") .NES. "" THEN DELETE/NOLOG [.PFSUB]*.*;*
$ SET PROTECTION=O:RWED PFSUB.DIR
$ DELETE/NOLOG PFSUB.DIR;
$ DELETE/NOLOG PFVAR.TXT;*
$ IF F$SEARCH("PLATFORM-FILES-*.TXT") .NES. "" THEN DELETE/NOLOG PLATFORM-FILES-*.TXT;*
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,FORMATTEDOUTPUT.OBJ;*,FORMATTEDTEXT.OBJ;*,REALDIGITS.OBJ;*,PLATFORM.OBJ;*,PLATFORMFILES.OBJ;*,PLATFORMFILES.OPT;*,PLATFORMFILES.EXE;*
$ EXIT 1
