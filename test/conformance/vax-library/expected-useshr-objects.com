$ ! Written by poc for VaxLibUse.mod: links its modules' objects into USESHR.EXE
$ ! (doc/developer/vax-object-language.md, section 17). Run it where
$ ! the modules' .OBJ files are.
$ ! An object sent in binary from Linux or a BSD, fixed-length records,
$ ! is converted first, by OBJCONVERT, which poc's SETUP.COM defines.
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
$ IF F$FILE_ATTRIBUTES("VAXLIBUSE.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_1
$ OBJCONVERT VAXLIBUSE.OBJ VAXLIBUSE.OBJ
$ DELETE/NOLOG VAXLIBUSE.OBJ;-1
$CONVERTED_1:
$ CREATE USESHR.OPT
VAXLIBUSE.OBJ
POC$LIB_VAXLIB:VAXLIB.EXE/SHAREABLE
POC$LIB_POCRTL:POCRTL.EXE/SHAREABLE
$ LINK/EXECUTABLE=USESHR.EXE USESHR.OPT/OPTIONS
$ EXIT $STATUS
