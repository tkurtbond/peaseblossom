$ ! Written by poc for VaxLibUse.mod: assembles its modules and links USESHR.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! The libraries it uses are found by the logical names their setup
$ ! procedures define (section 18).
$ ON WARNING THEN EXIT $STATUS
$ IF F$TRNLNM("POC$LIB_VAXLIB") .NES. "" THEN GOTO NEED_1
$ WRITE SYS$ERROR "program USESHR needs library VAXLIB: run its VAXLIB_SETUP.COM first"
$ EXIT %X1000002C
$NEED_1:
$ IF F$TRNLNM("POC$LIB_POCRTL") .NES. "" THEN GOTO NEED_2
$ WRITE SYS$ERROR "program USESHR needs library POCRTL: run its POCRTL_SETUP.COM first"
$ EXIT %X1000002C
$NEED_2:
$ MACRO/OBJECT VAXLIBUSE.MAR
$ CREATE USESHR.OPT
VAXLIBUSE.OBJ
POC$LIB_VAXLIB:VAXLIB.EXE/SHAREABLE
POC$LIB_POCRTL:POCRTL.EXE/SHAREABLE
$ LINK/EXECUTABLE=USESHR.EXE USESHR.OPT/OPTIONS
$ EXIT $STATUS
