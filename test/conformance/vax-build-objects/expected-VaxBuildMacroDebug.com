$ ! Written by poc for VaxBuild.mod: assembles its modules and links VAXBUILDMACRODEBUG.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ MACRO/DEBUG/OBJECT VAXBUILDSUMS.MAR
$ MACRO/DEBUG/OBJECT VAXBUILD.MAR
$ CREATE VAXBUILDMACRODEBUG.OPT
VAXBUILD.OBJ
VAXBUILDSUMS.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/DEBUG/EXECUTABLE=VAXBUILDMACRODEBUG.EXE VAXBUILDMACRODEBUG.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
