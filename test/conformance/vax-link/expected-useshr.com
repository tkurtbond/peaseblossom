$ ! Written by poc for VaxLinkUse.mod: assembles its modules and links USESHR.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! The libraries it uses are found by the logical names their setup
$ ! procedures define (section 18).
$ ON WARNING THEN EXIT $STATUS
$ IF F$TRNLNM("POC$LIB_VAXLINK") .NES. "" THEN GOTO NEED_1
$ WRITE SYS$ERROR "program USESHR needs library VAXLINK: run its VAXLINK_SETUP.COM first"
$ EXIT %X1000002C
$NEED_1:
$ IF F$TRNLNM("POC$LIB_POCRTL") .NES. "" THEN GOTO NEED_2
$ WRITE SYS$ERROR "program USESHR needs library POCRTL: run its POCRTL_SETUP.COM first"
$ EXIT %X1000002C
$NEED_2:
$ MACRO/OBJECT VAXLINKUSE.MAR
$ CREATE USESHR.OPT
VAXLINKUSE.OBJ
POC$LIB_VAXLINK:VAXLINK.EXE/SHAREABLE
POC$LIB_POCRTL:POCRTL.EXE/SHAREABLE
FOREIGN.OLB/LIBRARY
PSECT_ATTR=NO_SUCH_PSECT,NOSHR ! twice
$ LINK/EXECUTABLE=USESHR.EXE USESHR.OPT/OPTIONS
$ EXIT $STATUS
