$ ! Written by poc for Value.mod: assembles its modules and links VALUE.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! The libraries it uses are found by the logical names their setup
$ ! procedures define (section 18).
$ ON WARNING THEN EXIT $STATUS
$ IF F$TRNLNM("POC$LIB_POCRTL") .NES. "" THEN GOTO NEED_1
$ WRITE SYS$ERROR "program VALUE needs library POCRTL: run its POCRTL_SETUP.COM first"
$ EXIT %X1000002C
$NEED_1:
$ MACRO/OBJECT VALUE.MAR
$ CREATE VALUE.OPT
VALUE.OBJ
POC$LIB_POCRTL:POCRTL.OLB/LIBRARY
SYMBOL=SEVEN_VALUE,7
$ LINK/EXECUTABLE=VALUE.EXE VALUE.OPT/OPTIONS
$ EXIT $STATUS
