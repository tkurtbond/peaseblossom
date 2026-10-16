$ ! doc-vax-guide: the VAX/VMS Guide's example programs built by the
$ ! procedures poc -build wrote, against POCRTL.OBJ, and each run as the
$ ! guide's session of its name runs it, under "== <name>". A build's
$ ! log is shown only if it fails. Everything made is deleted.
$ SET NOON
$ MACRO/OBJECT POCRTL.MAR
$ PROGRAMS = "HELLO,VERSIONS,WHERELOGIN,WHERELOGIN2,DATES,FACTORIAL,WORDS,SYSTEMINFO,GREET,SHELL"
$ I = 0
$NEXT_BUILD:
$ P = F$ELEMENT(I, ",", PROGRAMS)
$ IF P .EQS. "," THEN GOTO BUILT
$ @'P'/OUTPUT=BUILD.LOG
$ IF .NOT. $STATUS THEN WRITE SYS$OUTPUT "build ", P, " failed: ", $STATUS
$ IF .NOT. $STATUS THEN TYPE BUILD.LOG
$ DELETE/NOLOG BUILD.LOG;*
$ I = I + 1
$ GOTO NEXT_BUILD
$BUILT:
$ WRITE SYS$OUTPUT "== hello"
$ RUN HELLO
$ WRITE SYS$OUTPUT "== versions"
$ RUN VERSIONS
$ WRITE SYS$OUTPUT "== wherelogin"
$ RUN WHERELOGIN
$ WRITE SYS$OUTPUT "== dates"
$ RUN DATES
$ WRITE SYS$OUTPUT "== factorial"
$ RUN FACTORIAL
$ WRITE SYS$OUTPUT "== words"
$ RUN WORDS
$ WRITE SYS$OUTPUT "== systeminfo"
$ RUN SYSTEMINFO
$ WRITE SYS$OUTPUT "== greet"
$ HERE = F$ENVIRONMENT("DEFAULT")
$ DEFINE/PROCESS GREET_IMAGE 'HERE'GREET.EXE
$ SET COMMAND GREET.CLD
$ GREET world
$ GREET/TIMES=2/NOEXCLAIM world,"Dear Reader"
$ GREET/TIMES=many world
$ GREET/LOUD world
$ DEASSIGN/PROCESS GREET_IMAGE
$ WRITE SYS$OUTPUT "== shell"
$ RUN SHELL
greet world
greet/noexclaim "Dear Reader"
count
exit
$ IF F$SEARCH("NOTES.TXT") .NES. "" THEN DELETE/NOLOG NOTES.TXT;*
$ DELETE/NOLOG *.OBJ;*, *.EXE;*, *.OPT;*
$ EXIT 1
