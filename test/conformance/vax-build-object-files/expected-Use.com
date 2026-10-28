$ ! Written by poc for Use.mod: assembles its modules and links USE.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! An object sent in binary from Linux or a BSD, fixed-length records,
$ ! is converted first, by OBJCONVERT, which poc's SETUP.COM defines.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ IF F$FILE_ATTRIBUTES("TWICE.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_1
$ OBJCONVERT TWICE.OBJ TWICE.OBJ
$ DELETE/NOLOG TWICE.OBJ;-1
$CONVERTED_1:
$ IF F$FILE_ATTRIBUTES("OTHER.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_2
$ OBJCONVERT OTHER.OBJ OTHER.OBJ
$ DELETE/NOLOG OTHER.OBJ;-1
$CONVERTED_2:
$ MACRO/OBJECT USE.MAR
$ CREATE USE.OPT
USE.OBJ
TWICE.OBJ
OTHER.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/EXECUTABLE=USE.EXE USE.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
