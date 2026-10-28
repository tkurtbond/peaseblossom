$ ! Written by poc for Use.mod: links its modules' objects into USE.EXE
$ ! (doc/developer/vax-object-language.md, section 17). Run it where
$ ! the modules' .OBJ files are.
$ ! An object sent in binary from Linux or a BSD, fixed-length records,
$ ! is converted first, by OBJCONVERT, which poc's SETUP.COM defines.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ IF F$FILE_ATTRIBUTES("USE.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_1
$ OBJCONVERT USE.OBJ USE.OBJ
$ DELETE/NOLOG USE.OBJ;-1
$CONVERTED_1:
$ IF F$FILE_ATTRIBUTES("TWICE.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_2
$ OBJCONVERT TWICE.OBJ TWICE.OBJ
$ DELETE/NOLOG TWICE.OBJ;-1
$CONVERTED_2:
$ SET COMMAND/OBJECT=TABLE.OBJ TABLE.CLD
$ CREATE USE.OPT
USE.OBJ
TABLE.OBJ
TWICE.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/EXECUTABLE=USE.EXE USE.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
