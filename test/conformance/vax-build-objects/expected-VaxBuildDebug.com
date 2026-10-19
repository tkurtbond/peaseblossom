$ ! Written by poc for VaxBuild.mod: links its modules' objects into VAXBUILDDEBUG.EXE
$ ! (doc/developer/vax-object-language.md, section 17). Run it where
$ ! the modules' .OBJ files are.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ CREATE VAXBUILDDEBUG.OPT
VAXBUILD.OBJ
VAXBUILDSUMS.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/DEBUG/EXECUTABLE=VAXBUILDDEBUG.EXE VAXBUILDDEBUG.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
