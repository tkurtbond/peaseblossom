$ ! Written by poc: defines the logical names of the library VAXLIB
$ ! (doc/developer/vax-macro32-backend.md, section 18, proposal 6):
$ ! POC$LIB_VAXLIB, the directory this procedure is in, and VAXLIB,
$ ! its shareable image, which the image activator looks for. Run it
$ ! once a session, or from LOGIN.COM, before building or running a
$ ! program that uses the library.
$ PROC = F$ENVIRONMENT("PROCEDURE")
$ DIR = F$PARSE(PROC,,,"DEVICE") + F$PARSE(PROC,,,"DIRECTORY")
$ DEFINE/NOLOG POC$LIB_VAXLIB 'DIR'
$ DEFINE/NOLOG VAXLIB 'DIR'VAXLIB.EXE
$ EXIT 1
