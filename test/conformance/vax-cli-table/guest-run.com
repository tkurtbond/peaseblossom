$ ! Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
$ ! proposal 8): POCRTL, VMSDEF and VMSLIB built, then CLITABLE by the
$ ! procedure poc -build wrote, which compiles CLICOMMANDS.CLD by SET
$ ! COMMAND/OBJECT and links it. CLITABLE run by CLIRUN.COM, made here:
$ ! its own lines, then the data lines for ParsePrompting, the second
$ ! without its second parameter, which DCL asks for and the next line
$ ! answers; the "$" line after them is the end of input. DCL's messages
$ ! go to its SYS$OUTPUT, with a traceback, and to its SYS$ERROR. The
$ ! first is CLIRUN's /OUTPUT file, opened by DCL, so that the program's
$ ! Out and VMS's messages share it (a file named by DEFINE/USER
$ ! SYS$OUTPUT is opened by each, and one writes over the other); it is
$ ! shown without the tracebacks, whose addresses change with the code. Of
$ ! the second only the lines with "%" or "-" are shown. Then CLITABLE is
$ ! run as a foreign command. Everything made is deleted.
$ SET NOON
$ @POCRTL_SETUP
$ @POCRTL_BUILD
$ WRITE SYS$OUTPUT "POCRTL_BUILD: ", $STATUS
$ @VMSDEF_SETUP
$ @VMSDEF_BUILD
$ WRITE SYS$OUTPUT "VMSDEF_BUILD: ", $STATUS
$ @VMSLIB_SETUP
$ @VMSLIB_BUILD
$ WRITE SYS$OUTPUT "VMSLIB_BUILD: ", $STATUS
$ @CLITABLE
$ WRITE SYS$OUTPUT "CLITABLE built: ", $STATUS
$ !
$ WRITE SYS$OUTPUT "== RUN CLITABLE"
$ CREATE CLIRUN.COM
$ DECK
$ DEFINE/USER SYS$ERROR CLIERR.TXT
$ RUN CLITABLE
COPY X.TXT Y.TXT/LOG
COPY X.TXT
Y.TXT
SHOW A,B
$ EXIT $STATUS
$ EOD
$ @CLIRUN/OUTPUT=CLIOUT.TXT
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ OPEN/READ OUTPUT CLIOUT.TXT
$ SKIPPING = 0
$ NEXT_LINE:
$ READ/END_OF_FILE=OUTPUT_DONE OUTPUT LINE
$ IF F$EXTRACT(0, 6, LINE) .EQS. "%TRACE" THEN SKIPPING = 1
$ IF F$EXTRACT(0, 2, LINE) .EQS. "==" THEN SKIPPING = 0
$ IF F$EXTRACT(0, 2, LINE) .EQS. "  " .AND. F$EXTRACT(2, 1, LINE) .NES. " " THEN SKIPPING = 0
$ IF .NOT. SKIPPING THEN WRITE SYS$OUTPUT LINE
$ GOTO NEXT_LINE
$ OUTPUT_DONE:
$ CLOSE OUTPUT
$ SEARCH CLIERR.TXT "%TRACE"/MATCH=NOR/OUTPUT=CLIERR2.TXT
$ SEARCH CLIERR2.TXT "%","-"
$ !
$ WRITE SYS$OUTPUT "== CLITABLE as a foreign command"
$ HERE = F$ENVIRONMENT("DEFAULT")
$ CLITABLE := $'HERE'CLITABLE.EXE
$ CLITABLE "Mixed Case" OUT.TXT /LOG
$ WRITE SYS$OUTPUT "run: ", $STATUS
$ DELETE/SYMBOL/LOCAL CLITABLE
$ DELETE/NOLOG *.OBJ;*, *.OLB;*, *.EXE;*, *.OPT;*, CLIRUN.COM;*, CLIOUT.TXT;*, CLIERR*.TXT;*
$ EXIT 1
