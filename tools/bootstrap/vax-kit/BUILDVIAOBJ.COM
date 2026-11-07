$ ! BUILDVIAOBJ.COM - builds Peaseblossom's poc for VAX/VMS again, once
$ ! @BUILD has built it from [.KIT]'s MACRO-32 (README.TXT): poc compiles
$ ! its own source, [.SRC], to objects, which are linked with POCRTL.OBJ,
$ ! assembled from [.SRC.RTL]POCRTL.MAR, into [.OBJBUILD]POC.EXE. It uses
$ ! the POC.EXE in [.BIN], MACRO and LINK alone. Written by
$ ! tools/bootstrap/make-vax-kit (PLAN.md, "Ongoing implementation
$ ! enhancements", item 11; doc/vax-vms-guide.md, chapter 1).
$ !
$ !   @BUILDVIAOBJ [CHECK|INSTALL]
$ !
$ ! It refuses unless [.BIN]POC.EXE says the version VERSION.TXT does,
$ ! and the process has the paging file quota poc needs to compile itself.
$ ! P1 CHECK then has the new POC.EXE compile the same source again, in
$ ! [.OBJCHECK], and compares each object it writes, and its POC.COM,
$ ! with [.OBJBUILD]'s, by CHECKSUM and size: poc is a fixed point, so
$ ! they are the same. P1 INSTALL checks so, and when they are the same
$ ! copies the new POC.EXE into [.BIN], keeping the one @BUILD built as
$ ! [.BIN]POC-KIT.EXE. Without either the installed poc is left alone.
$ ! [.OBJBUILD] and [.OBJCHECK] are emptied first, and [.OBJCHECK] is
$ ! deleted when the check passes. Each compilation takes from a quarter
$ ! of an hour to three quarters of one on an emulated MicroVAX 3900. The
$ ! objects' creation time is SOURCE_DATE_EPOCH's, in seconds since 1970,
$ ! when that logical name is defined, else the time this starts, so that
$ ! the two compilations' objects can be the same. Each step's start,
$ ! end, status and CPU time are added to BUILD.LOG as well; the first
$ ! that fails stops it, with its status. A symbol here is seen by the
$ ! procedures it runs, so none is named as a command they use (CREATE,
$ ! LINK, MACRO).
$ SET NOON
$ MODE = F$EDIT(P1, "UPCASE,TRIM")
$ IF MODE .EQS. "" .OR. MODE .EQS. "CHECK" .OR. MODE .EQS. "INSTALL" THEN GOTO P1_OK
$ WRITE SYS$ERROR "BUILDVIAOBJ: P1 is CHECK, INSTALL or nothing, not ", MODE
$ EXIT %X10000014
$P1_OK:
$ PROC = F$ENVIRONMENT("PROCEDURE")
$ TOP = F$PARSE(PROC, , , "DEVICE") + F$PARSE(PROC, , , "DIRECTORY")
$ ! the top directory without its closing bracket, for a subdirectory
$ TOP_OPEN = F$EXTRACT(0, F$LENGTH(TOP) - 1, TOP)
$ CLOSE_BRACKET = F$EXTRACT(F$LENGTH(TOP) - 1, 1, TOP)
$ BIN_DIR = TOP_OPEN + ".BIN" + CLOSE_BRACKET
$ BUILD_DIR = TOP_OPEN + ".OBJBUILD" + CLOSE_BRACKET
$ CHECK_DIR = TOP_OPEN + ".OBJCHECK" + CLOSE_BRACKET
$ HOME = F$ENVIRONMENT("DEFAULT")
$ OUR_EPOCH = 0
$ !
$ ! what it needs, before anything is written
$ IF F$SEARCH(BIN_DIR + "POC.EXE") .NES. "" THEN GOTO POC_THERE
$ WRITE SYS$ERROR "BUILDVIAOBJ: poc is not built; @", TOP, "BUILD first"
$ EXIT %X10000014
$POC_THERE:
$ IF F$SEARCH(TOP_OPEN + ".SRC.DRIVER" + CLOSE_BRACKET + "POC.MOD") .NES. "" THEN GOTO SOURCE_THERE
$ WRITE SYS$ERROR "BUILDVIAOBJ: poc's source is not in ", TOP_OPEN, ".SRC", CLOSE_BRACKET
$ EXIT %X10000014
$SOURCE_THERE:
$ ! poc's heap is three quarters of the paging file quota it starts with,
$ ! and compiling itself it peaks at about 16 MB of heap (doc/developer/
$ ! vms-memory.md): 60,000 pages, 30 MB, leave room
$ LEFT = F$GETJPI("", "PAGFILCNT")
$ IF LEFT .GE. 60000 THEN GOTO QUOTA_OK
$ WRITE SYS$ERROR "BUILDVIAOBJ: poc compiling itself needs 60000 pages of paging file quota left; this process has ", LEFT
$ WRITE SYS$ERROR "BUILDVIAOBJ: SHOW PROCESS/QUOTAS shows it; the system manager raises PGFLQUOTA with AUTHORIZE"
$ EXIT %X10000014
$QUOTA_OK:
$ KIT_POC = "$" + BIN_DIR + "POC.EXE"
$ IMAGE = "KIT_POC"
$ GOSUB VERSION_OF
$ IF STATUS THEN GOTO VERSION_OK
$ WRITE SYS$ERROR "BUILDVIAOBJ: ", BIN_DIR, "POC.EXE says """, SAID, """, VERSION.TXT """, WANTED, """"
$ EXIT %X10000014
$VERSION_OK:
$ !
$ IF F$SEARCH(TOP + "BUILD.LOG") .EQS. "" THEN OPEN/WRITE BVO_LOG 'TOP'BUILD.LOG
$ IF F$SEARCH(TOP + "BUILD.LOG") .NES. "" THEN OPEN/APPEND BVO_LOG 'TOP'BUILD.LOG
$ STATUS = 1
$ LINE = F$TIME() + " @BUILDVIAOBJ " + MODE
$ GOSUB SAY
$ IF F$TRNLNM("SOURCE_DATE_EPOCH") .NES. "" THEN GOTO EPOCH_SET
$ GOSUB EPOCH_NOW
$ DEFINE/NOLOG SOURCE_DATE_EPOCH "''EPOCH'"
$ OUR_EPOCH = 1
$EPOCH_SET:
$ LINE = F$TIME() + " SOURCE_DATE_EPOCH is " + F$TRNLNM("SOURCE_DATE_EPOCH")
$ GOSUB SAY
$ !
$ STEP = "[.OBJBUILD]POC.EXE"
$ GOSUB START_STEP
$ DIR = BUILD_DIR
$ GOSUB EMPTY_DIR
$ IF .NOT. STATUS THEN GOTO FAILED
$ SET DEFAULT 'BUILD_DIR'
$ GOSUB WRITE_ARGS
$ KIT_POC @FULL.ARGS
$ STATUS = F$INTEGER($STATUS)
$ IF .NOT. STATUS THEN GOTO FAILED
$ MACRO/OBJECT=POCRTL.OBJ 'TOP_OPEN'.SRC.RTL'CLOSE_BRACKET'POCRTL.MAR
$ STATUS = F$INTEGER($STATUS)
$ IF .NOT. STATUS THEN GOTO FAILED
$ DEFINE/NOLOG POC$RTL 'BUILD_DIR'
$ @'BUILD_DIR'POC.COM
$ STATUS = F$INTEGER($STATUS)
$ DEASSIGN POC$RTL
$ IF .NOT. STATUS THEN GOTO FAILED
$ NEW_POC = "$" + BUILD_DIR + "POC.EXE"
$ IMAGE = "NEW_POC"
$ GOSUB VERSION_OF
$ IF STATUS THEN GOTO NEW_VERSION_OK
$ LINE = F$TIME() + " " + STEP + " says """ + SAID + """, VERSION.TXT """ + WANTED + """"
$ GOSUB SAY
$ STATUS = %X10000014
$ GOTO FAILED
$NEW_VERSION_OK:
$ GOSUB END_STEP
$ IF MODE .EQS. "" THEN GOTO FINISHED
$ !
$ STEP = "[.OBJCHECK], the fixed point"
$ GOSUB START_STEP
$ DIR = CHECK_DIR
$ GOSUB EMPTY_DIR
$ IF .NOT. STATUS THEN GOTO FAILED
$ SET DEFAULT 'CHECK_DIR'
$ GOSUB WRITE_ARGS
$ NEW_POC @FULL.ARGS
$ STATUS = F$INTEGER($STATUS)
$ IF .NOT. STATUS THEN GOTO FAILED
$ COMPARED = 0
$ DIFFERENT = 0
$NEXT_OBJECT:
$ FILE = F$SEARCH(BUILD_DIR + "*.OBJ;", 1)
$ IF FILE .EQS. "" THEN GOTO OBJECTS_COMPARED
$ NAME = F$PARSE(FILE, , , "NAME")
$ ! assembled, not compiled: [.OBJCHECK] has none
$ IF NAME .EQS. "POCRTL" THEN GOTO NEXT_OBJECT
$ COMPARED = COMPARED + 1
$ NAME = NAME + ".OBJ"
$ GOSUB COMPARE
$ GOTO NEXT_OBJECT
$OBJECTS_COMPARED:
$ WRITTEN = 0
$NEXT_WRITTEN:
$ IF F$SEARCH(CHECK_DIR + "*.OBJ;", 1) .EQS. "" THEN GOTO WRITTEN_COUNTED
$ WRITTEN = WRITTEN + 1
$ GOTO NEXT_WRITTEN
$WRITTEN_COUNTED:
$ IF WRITTEN .EQ. COMPARED THEN GOTO SAME_COUNT
$ LINE = F$TIME() + " " + STEP + ": " + F$STRING(WRITTEN) + " objects, [.OBJBUILD] " + F$STRING(COMPARED)
$ GOSUB SAY
$ DIFFERENT = DIFFERENT + 1
$SAME_COUNT:
$ NAME = "POC.COM"
$ GOSUB COMPARE
$ IF DIFFERENT .EQ. 0 THEN GOTO FIXED_POINT
$ LINE = F$TIME() + " " + STEP + ": " + F$STRING(DIFFERENT) + " differ; left in [.OBJCHECK]"
$ GOSUB SAY
$ STATUS = %X10000014
$ GOTO FAILED
$FIXED_POINT:
$ LINE = F$TIME() + " " + STEP + ": " + F$STRING(COMPARED) + " objects and POC.COM the same"
$ GOSUB SAY
$ DIR = CHECK_DIR
$ GOSUB EMPTY_DIR
$ SET DEFAULT 'TOP'
$ SET PROTECTION=O:RWED OBJCHECK.DIR
$ DELETE/NOLOG OBJCHECK.DIR;*
$ GOSUB END_STEP
$ IF MODE .NES. "INSTALL" THEN GOTO FINISHED
$ !
$ STEP = "[.BIN]POC.EXE"
$ GOSUB START_STEP
$ IF F$SEARCH(BIN_DIR + "POC-KIT.EXE") .NES. "" THEN GOTO KIT_KEPT
$ COPY/NOLOG 'BIN_DIR'POC.EXE 'BIN_DIR'POC-KIT.EXE
$ STATUS = F$INTEGER($STATUS)
$ IF .NOT. STATUS THEN GOTO FAILED
$KIT_KEPT:
$ ! a new version of [.BIN]POC.EXE, with the old one's protection
$ COPY/NOLOG 'BUILD_DIR'POC.EXE 'BIN_DIR'POC.EXE
$ STATUS = F$INTEGER($STATUS)
$ IF .NOT. STATUS THEN GOTO FAILED
$ PURGE/NOLOG 'BIN_DIR'POC.EXE
$ GOSUB END_STEP
$ !
$FINISHED:
$ IF MODE .EQS. "INSTALL" THEN LINE = F$TIME() + " installed poc built via objects; @" + TOP + "SETUP uses it"
$ IF MODE .NES. "INSTALL" THEN LINE = F$TIME() + " built poc via objects in " + BUILD_DIR + "POC.EXE"
$ GOSUB SAY
$ GOSUB FORGET_EPOCH
$ CLOSE BVO_LOG
$ SET DEFAULT 'HOME'
$ EXIT 1
$FAILED:
$ LINE = F$TIME() + " " + STEP + ": failed, status " + F$FAO("%X!XL", STATUS)
$ GOSUB SAY
$ GOSUB FORGET_EPOCH
$ CLOSE BVO_LOG
$ SET DEFAULT 'HOME'
$ EXIT STATUS
$ !
$ ! FULL.ARGS in the current directory, beside [.SRC]: the arguments, one
$ ! a line, the command being longer than DCL's; objects are poc's
$ ! default on VMS
$WRITE_ARGS:
$ CREATE FULL.ARGS
-OC
-clear-library-path
-import-path
[-.SRC.FRONT]
-import-path
[-.SRC.BACK.VAX]
-import-path
[-.SRC.BACK.VAX.VMS]
-import-path
[-.SRC.DRIVER]
-import-path
[-.SRC.DRIVER.NO-LLVM]
-import-path
[-.SRC.RTL]
-import-path
[-.SRC.GEN]
-build
[-.SRC.DRIVER]POC.MOD
$ RETURN
$ !
$ ! DIR made, or emptied of its files; STATUS whether it could be
$EMPTY_DIR:
$ STATUS = 1
$ IF F$PARSE(DIR) .EQS. "" THEN CREATE/DIRECTORY 'DIR'
$ IF F$PARSE(DIR) .EQS. "" THEN STATUS = %X10000014
$ IF .NOT. STATUS THEN RETURN
$ ! a search of another file first, so that this one starts afresh
$ RESET = F$SEARCH(TOP + "VERSION.TXT", 3)
$ IF F$SEARCH(DIR + "*.*;*", 3) .EQS. "" THEN RETURN
$ DELETE/NOLOG 'DIR'*.*;*
$ STATUS = F$INTEGER($STATUS)
$ RETURN
$ !
$ ! NAME in [.OBJBUILD] and [.OBJCHECK]: DIFFERENT counts it unless both
$ ! are there with the same size and CHECKSUM
$COMPARE:
$ A = BUILD_DIR + NAME
$ B = CHECK_DIR + NAME
$ IF F$SEARCH(B, 2) .EQS. "" THEN GOTO COMPARE_DIFFERS
$ IF F$FILE_ATTRIBUTES(A, "EOF") .NE. F$FILE_ATTRIBUTES(B, "EOF") THEN GOTO COMPARE_DIFFERS
$ IF F$FILE_ATTRIBUTES(A, "FFB") .NE. F$FILE_ATTRIBUTES(B, "FFB") THEN GOTO COMPARE_DIFFERS
$ CHECKSUM 'A'
$ SUM_A = CHECKSUM$CHECKSUM
$ CHECKSUM 'B'
$ IF SUM_A .NES. CHECKSUM$CHECKSUM THEN GOTO COMPARE_DIFFERS
$ RETURN
$COMPARE_DIFFERS:
$ DIFFERENT = DIFFERENT + 1
$ LINE = F$TIME() + " " + STEP + ": " + NAME + " differs"
$ GOSUB SAY
$ RETURN
$ !
$ ! what the image IMAGE names says to -VERSION, SAID, and what VERSION.TXT
$ ! says it should, WANTED, its "Peaseblossom" being "poc"; STATUS whether
$ ! they are the same
$VERSION_OF:
$ SAID = ""
$ OPEN/READ BVO_VERSION 'TOP'VERSION.TXT
$ READ BVO_VERSION WANTED
$ CLOSE BVO_VERSION
$ WANTED = "poc" + F$EXTRACT(F$LOCATE(" ", WANTED), F$LENGTH(WANTED), WANTED)
$ DEFINE/USER_MODE SYS$OUTPUT 'TOP'BVO-VERSION.TMP
$ 'IMAGE' -VERSION
$ IF F$SEARCH(TOP + "BVO-VERSION.TMP") .EQS. "" THEN GOTO VERSION_READ
$ OPEN/READ BVO_VERSION 'TOP'BVO-VERSION.TMP
$ READ/END_OF_FILE=VERSION_CLOSE BVO_VERSION SAID
$VERSION_CLOSE:
$ CLOSE BVO_VERSION
$ DELETE/NOLOG 'TOP'BVO-VERSION.TMP;*
$VERSION_READ:
$ STATUS = SAID .EQS. WANTED
$ RETURN
$ !
$ ! EPOCH, the time now in seconds since 1970, the clock's time taken as
$ ! UTC: the days since 1970-01-01 by the Gregorian calendar's eras of
$ ! 400 years, each year counted from March
$EPOCH_NOW:
$ T = F$TIME()
$ Y = F$INTEGER(F$CVTIME(T, , "YEAR"))
$ M = F$INTEGER(F$CVTIME(T, , "MONTH"))
$ D = F$INTEGER(F$CVTIME(T, , "DAY"))
$ IF M .LE. 2 THEN Y = Y - 1
$ ERA = Y / 400
$ YEAR_OF_ERA = Y - ERA * 400
$ MP = M - 3
$ IF M .LE. 2 THEN MP = M + 9
$ DAY_OF_YEAR = (153 * MP + 2) / 5 + D - 1
$ DAY_OF_ERA = YEAR_OF_ERA * 365 + YEAR_OF_ERA / 4 - YEAR_OF_ERA / 100 + DAY_OF_YEAR
$ DAYS = ERA * 146097 + DAY_OF_ERA - 719468
$ EPOCH = DAYS * 86400 + F$INTEGER(F$CVTIME(T, , "HOUR")) * 3600 + -
    F$INTEGER(F$CVTIME(T, , "MINUTE")) * 60 + F$INTEGER(F$CVTIME(T, , "SECOND"))
$ RETURN
$FORGET_EPOCH:
$ IF OUR_EPOCH THEN DEASSIGN SOURCE_DATE_EPOCH
$ OUR_EPOCH = 0
$ RETURN
$ !
$START_STEP:
$ LINE = F$TIME() + " " + STEP + ": started"
$ GOSUB SAY
$ CPU_START = F$GETJPI("", "CPUTIM")
$ RETURN
$END_STEP:
$ CPU = (F$GETJPI("", "CPUTIM") - CPU_START) / 100
$ LINE = F$TIME() + " " + STEP + ": done, " + F$STRING(CPU) + " s of CPU"
$ GOSUB SAY
$ RETURN
$SAY:
$ WRITE SYS$OUTPUT LINE
$ WRITE BVO_LOG LINE
$ RETURN
