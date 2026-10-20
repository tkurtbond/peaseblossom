$ ! Written by poc for VaxBuildSums.mod: converts its modules' objects
$ ! (doc/developer/vax-object-language.md, section 17). Run it where
$ ! the modules' .OBJ files are.
$ ! An object sent in binary from Linux or a BSD, fixed-length records,
$ ! is converted first, by OBJCONVERT, which poc's SETUP.COM defines.
$ ON WARNING THEN EXIT $STATUS
$ IF F$FILE_ATTRIBUTES("VAXBUILDSUMS.OBJ", "RFM") .NES. "FIX" THEN GOTO CONVERTED_1
$ OBJCONVERT VAXBUILDSUMS.OBJ VAXBUILDSUMS.OBJ
$ DELETE/NOLOG VAXBUILDSUMS.OBJ;-1
$CONVERTED_1:
$ EXIT $STATUS
