$ ! Written by poc for VaxLink.mod: assembles its modules and links VAXLINK.EXE
$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where
$ ! the modules' .MAR files are.
$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that
$ ! logical name is defined, else from the current directory.
$ ON WARNING THEN EXIT $STATUS
$ MACRO/OBJECT VAXLINK.MAR
$ CREATE VAXLINK.OPT
VAXLINK.OBJ
FOREIGN.OLB/LIBRARY
FORSHR/SHAREABLE
PSECT_ATTR=NO_SUCH_PSECT,NOSHR
$ RTL = "POCRTL.OBJ"
$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"
$ LINK/EXECUTABLE=VAXLINK.EXE VAXLINK.OPT/OPTIONS, 'RTL'
$ EXIT $STATUS
