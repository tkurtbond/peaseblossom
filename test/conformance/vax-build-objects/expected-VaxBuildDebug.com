$ ! Written by poc for VaxBuild.mod: links its modules' objects into VAXBUILDDEBUG.EXE
$ ! (doc/developer/vax-object-language.md, section 17). Run it where
$ ! the modules' .OBJ files are.
$ ! An object sent in binary from Linux or a BSD, fixed-length records,
$ ! is converted first, by OBJCONVERT, which poc's SETUP.COM defines.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ IF F$FILE_ATTRIBUTES("VAXBUILDSUMS.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_1
$ OBJCONVERT VAXBUILDSUMS.OBJ VAXBUILDSUMS.OBJ
$ DELETE/NOLOG VAXBUILDSUMS.OBJ;-1
$CONVERTED_1:
$ IF F$FILE_ATTRIBUTES("VAXBUILD.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_2
$ OBJCONVERT VAXBUILD.OBJ VAXBUILD.OBJ
$ DELETE/NOLOG VAXBUILD.OBJ;-1
$CONVERTED_2:
$ CREATE VAXBUILDDEBUG.OPT
VAXBUILD.OBJ
VAXBUILDSUMS.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/DEBUG/EXECUTABLE=VAXBUILDDEBUG.EXE VAXBUILDDEBUG.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
