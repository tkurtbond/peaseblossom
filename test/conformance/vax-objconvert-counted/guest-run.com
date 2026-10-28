$ ! vax-objconvert-counted (doc/developer/vax-macro32-backend.md, section
$ ! 13.2, proposal 6): HAND-TWICE.MAR assembled by MACRO; its object written in
$ ! the counted form by OBJCONVERT -COUNTED, as TWICE.CNT, which
$ ! tools/vax-do brings back in binary, and that turned back into an
$ ! object, BACK.OBJ, by OBJCONVERT; both objects dumped (TWICE.DMP and
$ ! BACK.DMP, brought back too). Then what OBJCONVERT -COUNTED refuses,
$ ! each with its message and status, and no file left: an object with an
$ ! empty record, one with a record longer than 512 bytes, a file not of
$ ! records, a missing file, and a wrong command. Then RECORDSTEST, built
$ ! by poc's procedure from the objects tools/vax-do sent and converted
$ ! (which made OBJCONVERT ready). Everything made is deleted but the
$ ! files tools/vax-do brings back.
$ SET NOON
$ OBJCONVERT := $'F$PARSE("[.BIN]OBJCONVERT.EXE")'
$ MACRO/OBJECT=TWICE.OBJ HAND-TWICE.MAR
$ WRITE SYS$OUTPUT "MACRO status: ", $STATUS
$ OBJCONVERT "-counted" TWICE.OBJ TWICE.CNT
$ WRITE SYS$OUTPUT "OBJCONVERT -COUNTED status: ", $STATUS
$ OBJCONVERT TWICE.CNT BACK.OBJ
$ WRITE SYS$OUTPUT "OBJCONVERT status: ", $STATUS
$ DUMP/RECORDS/OUTPUT=TWICE.DMP TWICE.OBJ
$ DUMP/RECORDS/OUTPUT=BACK.DMP BACK.OBJ
$ OPEN/WRITE F EMPTY.OBJ
$ WRITE F "ABC"
$ WRITE F ""
$ CLOSE F
$ OPEN/WRITE F LONG.OBJ
$ L = "0123456789012345678901234567890123456789012345678901234567890123456789"
$ L = L + L + L
$ WRITE F L, L, L
$ CLOSE F
$ IN = "EMPTY.OBJ"
$ GOSUB REFUSED
$ IN = "LONG.OBJ"
$ GOSUB REFUSED
$ IN = "TWICE.CNT"
$ GOSUB REFUSED
$ IN = "MISSING.OBJ"
$ GOSUB REFUSED
$ DEFINE/USER SYS$ERROR ERR.TXT
$ OBJCONVERT -COUNTED TWICE.OBJ
$ WRITE SYS$OUTPUT "OBJCONVERT -COUNTED TWICE.OBJ status: ", $STATUS
$ GOSUB ERRORS
$ MACRO/OBJECT POCRTL.MAR
$ S = $STATUS
$ IF S THEN @RECORDSTEST
$ IF S THEN S = $STATUS
$ WRITE SYS$OUTPUT "build status: ", S
$ IF .NOT. S THEN GOTO CLEAN
$ DEFINE/USER SYS$ERROR ERR.TXT
$ RUN RECORDSTEST.EXE
$ WRITE SYS$OUTPUT "run status: ", $STATUS
$ GOSUB ERRORS
$ CLEAN:
$ DELETE/NOLOG TWICE.OBJ;*,BACK.OBJ;*,EMPTY.OBJ;*,LONG.OBJ;*
$ DELETE/NOLOG POCRTL.OBJ;*,RECORDSTEST.OPT;*,RECORDSTEST.EXE;*
$ IF F$SEARCH("*.DAT") .NES. "" THEN DELETE/NOLOG *.DAT;*
$ IF F$SEARCH("STREAM.TXT") .NES. "" THEN DELETE/NOLOG STREAM.TXT;*
$ EXIT 1
$ !
$ ! OBJCONVERT -COUNTED IN REFUSED.CNT: its message, its status, and whether
$ ! REFUSED.CNT was left (not OUT.CNT: tools/vax-do sends Out's object as
$ ! OUT.CNT)
$ REFUSED:
$ DEFINE/USER SYS$ERROR ERR.TXT
$ OBJCONVERT -COUNTED 'IN' REFUSED.CNT
$ WRITE SYS$OUTPUT "OBJCONVERT -COUNTED ", IN, " status: ", $STATUS
$ GOSUB ERRORS
$ IF F$SEARCH("REFUSED.CNT") .NES. "" THEN WRITE SYS$OUTPUT "REFUSED.CNT left"
$ IF F$SEARCH("REFUSED.CNT") .NES. "" THEN DELETE/NOLOG REFUSED.CNT;*
$ RETURN
$ !
$ ! what the last image wrote on SYS$ERROR, ERR.TXT, then deleted
$ ERRORS:
$ IF F$SEARCH("ERR.TXT") .EQS. "" THEN RETURN
$ TYPE ERR.TXT
$ DELETE/NOLOG ERR.TXT;*
$ RETURN
