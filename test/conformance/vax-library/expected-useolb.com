$ ! Written by poc for VaxLibUse.mod: assembles its modules and links USEOLB.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! The libraries it uses are found by the logical names their setup
$ ! procedures define (section 18).
$ ON WARNING THEN EXIT $STATUS
$ IF F$TRNLNM("POC$LIB_VAXLIB") .NES. "" THEN GOTO NEED_1
$ WRITE SYS$ERROR "program USEOLB needs library VAXLIB: run its VAXLIB_SETUP.COM first"
$ EXIT %X1000002C
$NEED_1:
$ IF F$TRNLNM("POC$LIB_POCRTL") .NES. "" THEN GOTO NEED_2
$ WRITE SYS$ERROR "program USEOLB needs library POCRTL: run its POCRTL_SETUP.COM first"
$ EXIT %X1000002C
$NEED_2:
$ MACRO/OBJECT VAXLIBUSE.MAR
$ CREATE USEOLB.OPT
VAXLIBUSE.OBJ
POC$LIB_VAXLIB:VAXLIB.OLB/LIBRARY
POC$LIB_POCRTL:POCRTL.OLB/LIBRARY
$ LINK/EXECUTABLE=USEOLB.EXE USEOLB.OPT/OPTIONS
$ EXIT $STATUS
