$ ! PLAN.md Phase 16 step 4: PLATFORMOUT.COM, which poc -build wrote, run
$ ! after poc's runtime is assembled; then the image, as a foreign
$ ! command, given SYS$LOGIN, a directory there is not, one to make below
$ ! one there is not yet, and a logical name, a search list; DOOMED.TMP
$ ! has two versions, of which Unlink deletes the highest. What is left
$ ! of it, and the directories made, are deleted after
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @PLATFORMOUT
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ CREATE DOOMED.TMP
version 1
$ CREATE DOOMED.TMP
version 2
$ DEFINE POC_PLATFORM_TEST "[A]","[B]"
$ PLATFORMOUT :== $SYS$LOGIN:PLATFORMOUT.EXE
$ PLATFORMOUT SYS$LOGIN [.NO-SUCH-DIRECTORY] [.MADE.SUB] POC_PLATFORM_TEST
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ F = F$SEARCH("DOOMED.TMP")
$ IF F .NES. "" THEN WRITE SYS$OUTPUT "left: ", F$PARSE(F,,,"NAME"), -
    F$PARSE(F,,,"TYPE"), F$PARSE(F,,,"VERSION")
$ IF F .NES. "" THEN DELETE/NOLOG DOOMED.TMP;*
$ IF F$SEARCH("[.MADE]SUB.DIR") .NES. "" THEN SET PROTECTION=O:RWED [.MADE]SUB.DIR
$ IF F$SEARCH("[.MADE]SUB.DIR") .NES. "" THEN DELETE/NOLOG [.MADE]SUB.DIR;
$ IF F$SEARCH("MADE.DIR") .NES. "" THEN SET PROTECTION=O:RWED MADE.DIR
$ IF F$SEARCH("MADE.DIR") .NES. "" THEN DELETE/NOLOG MADE.DIR;
$ DEASSIGN POC_PLATFORM_TEST
$ DELETE/SYMBOL/GLOBAL PLATFORMOUT
$ CLEAN:
$ DELETE/NOLOG POCRTL.OBJ;*,OUT.OBJ;*,LINEOUTPUT.OBJ;*,MODULES.OBJ;*,PLATFORM.OBJ;*,PLATFORMOUT.OBJ;*,PLATFORMOUT.OPT;*,PLATFORMOUT.EXE;*
$ EXIT 1
