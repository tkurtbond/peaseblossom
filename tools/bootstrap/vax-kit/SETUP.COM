$ ! SETUP.COM - makes Peaseblossom's poc usable in this process, once
$ ! BUILD.COM has built it (README.TXT): defines the command POC, and runs
$ ! the setup procedures of the libraries of one size model that are built,
$ ! POCRTL's, and VMSDEF's and VMSLIB's once the STARLET kit is. Run it once
$ ! a session, or from LOGIN.COM. It defines OBJCONVERT too, which
$ ! converts an object poc wrote on Linux or a BSD and FTP sent in binary;
$ ! the procedures poc writes there run it. Written by tools/bootstrap/make-vax-kit
$ ! (doc/developer/vax-macro32-backend.md, section 21, proposals 4 and 10).
$ !
$ !   @SETUP [O2|OC]
$ !
$ ! P1 is the size model, O2 by default, as poc's is. A library's logical
$ ! names name one directory, so a process builds against one model's
$ ! libraries at a time: run @SETUP OC to change to -OC's, and @SETUP O2
$ ! to change back. poc finds the libraries by itself, in
$ ! [.LIB.POC] beside its [.BIN]; POC$LIBRARY is only for others.
$ MODEL = F$EDIT(P1, "UPCASE,TRIM")
$ IF MODEL .EQS. "" THEN MODEL = "O2"
$ IF MODEL .EQS. "O2" .OR. MODEL .EQS. "OC" THEN GOTO MODEL_OK
$ WRITE SYS$ERROR "SETUP: P1 is O2 or OC, not ", MODEL
$ EXIT %X10000014
$MODEL_OK:
$ PROC = F$ENVIRONMENT("PROCEDURE")
$ TOP = F$PARSE(PROC, , , "DEVICE") + F$PARSE(PROC, , , "DIRECTORY")
$ TOP_OPEN = F$EXTRACT(0, F$LENGTH(TOP) - 1, TOP)
$ CLOSE_BRACKET = F$EXTRACT(F$LENGTH(TOP) - 1, 1, TOP)
$ IMAGE = TOP_OPEN + ".BIN" + CLOSE_BRACKET + "POC.EXE"
$ IF F$SEARCH(IMAGE) .NES. "" THEN GOTO BUILT
$ WRITE SYS$ERROR "SETUP: poc is not built; @", TOP, "BUILD first"
$ EXIT %X10000014
$BUILT:
$ LIBRARY_DIR = TOP_OPEN + ".LIB.POC.VAX-DEC-VMS." + MODEL + CLOSE_BRACKET
$ IF F$SEARCH(LIBRARY_DIR + "POCRTL.OLB") .NES. "" THEN GOTO LIBRARIES_BUILT
$ WRITE SYS$ERROR "SETUP: the -", MODEL, " libraries are not built; @", TOP, "BUILD ", MODEL, " first"
$ EXIT %X10000014
$LIBRARIES_BUILT:
$ POC :== $'IMAGE'
$ OBJCONVERT :== $'TOP_OPEN'.BIN'CLOSE_BRACKET'OBJCONVERT.EXE
$ I = 0
$NEXT_LIBRARY:
$ LIBRARY_NAME = F$ELEMENT(I, " ", "POCRTL VMSDEF VMSLIB")
$ IF LIBRARY_NAME .EQS. " " THEN EXIT 1
$ I = I + 1
$ IF F$SEARCH(LIBRARY_DIR + LIBRARY_NAME + ".OLB") .NES. "" THEN @'LIBRARY_DIR''LIBRARY_NAME'_SETUP
$ GOTO NEXT_LIBRARY
