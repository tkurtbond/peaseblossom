$ ! Written by poc for Tables.mod: assembles its modules and links TABLES.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ MACRO/OBJECT TABLES.MAR
$ SET COMMAND/OBJECT=ONE.OBJ ONE.CLD
$ SET COMMAND/OBJECT=TWO.OBJ TWO.CLD
$ CREATE TABLES.OPT
TABLES.OBJ
ONE.OBJ
TWO.OBJ
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/EXECUTABLE=TABLES.EXE TABLES.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
