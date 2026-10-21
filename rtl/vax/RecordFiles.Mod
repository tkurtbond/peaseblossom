MODULE RecordFiles;

  (* PLAN.md Phase 18 step 4c (doc/developer/vax-object-language.md,
     sections 10, 15.3 and 15.9): a file of variable-length records,
     written one record at a time, as poc's object writer writes an
     object on VMS (src/back/vax/vms/ObjectRecords.Mod) and
     tools/objconvert's converter writes one from a counted file. VAX
     only: rtl/llvm has no such module.

     Create makes a sequential file of variable-length records of at most
     maximum bytes, with no record attributes (not text, as MACRO's
     objects are not), under the name as given: RMS makes it a new version
     when the file exists, and it is written directly, not under a name of
     its own until registered as Files.New's is. Put writes one record
     ($PUT); Close closes the file, and a second Close does nothing. A Put
     or Close that fails, or a length outside 0 to maximum, stops the
     program with a message naming the file and HALT(99), as Files does
     for an error it cannot report. A File is not registered for
     finalization: one never closed is closed by RMS when the image exits,
     its records kept.

     Describe gives a file's resultant name and the RMS attributes the
     debugger's source file record holds (Phase 18 step 5b, section
     16.6), for poc -g. *)

  IMPORT SYSTEM;

  CONST
    nameLength = 256; (* a name and its 0X, as RMS takes at most 255 *)
    controlSize = 768; (* PocRtl.mar's POC_F_SIZE, as Files' is *)
    longest = 32765; (* the longest variable-length record (RMS 5.22) *)

  TYPE
    Name = ARRAY nameLength OF CHAR;
    (* the file's FAB, RAB, NAM block, XABFHC and XABDAT, and its
       resultant name, laid out as Files' *)
    Control = ARRAY controlSize OF CHAR;
    (* what POC_RECORD_ATTRIBUTES gives: 16 bytes of attributes, then the
       resultant name as a counted string *)
    Attributes = ARRAY 16 + nameLength OF CHAR;
    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      control: Control;
      name: Name; (* as given to Create *)
      maximum: INTEGER;
      open: BOOLEAN
    END;

  PROCEDURE ["VMS"] POC_RECORD_CREATE(VAR control: Control; VAR name: Name; length: SYSTEM.INT32;
                                      maximum: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_RECORD_PUT(VAR control: Control; VAR record: ARRAY OF SYSTEM.BYTE;
                                   length: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CLOSE(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_RECORD_ATTRIBUTES(VAR control: Control; VAR name: Name; length: SYSTEM.INT32;
                                          VAR attributes: Attributes): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_FAIL(VAR message: Name; messageLength: SYSTEM.INT32;
                                  VAR name: Name; nameLength: SYSTEM.INT32);

  (* the length of s up to its 0X *)
  PROCEDURE Length0X(VAR s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length0X;

  (* An error the caller cannot be told about: says what and of which
     file, on SYS$ERROR, and stops the program. *)
  PROCEDURE Fail(message: ARRAY OF CHAR; f: File);
    VAR text: Name;
  BEGIN
    COPY(message, text);
    POC_FILE_FAIL(text, Length0X(text), f.name, Length0X(f.name))
  END Fail;

  (* A new file called name, for records of at most maximum bytes, 1 to
     32,765: NIL if it cannot be made *)
  PROCEDURE Create*(name: ARRAY OF CHAR; maximum: INTEGER): File;
    VAR f: File; n: INTEGER;
  BEGIN
    n := Length0X(name);
    IF (n = 0) OR (n >= nameLength) OR (maximum < 1) OR (maximum > longest) THEN RETURN NIL END;
    NEW(f);
    IF f = NIL THEN RETURN NIL END;
    COPY(name, f.name); f.maximum := maximum;
    IF ~ODD(POC_RECORD_CREATE(f.control, f.name, n, maximum)) THEN RETURN NIL END;
    f.open := TRUE;
    RETURN f
  END Create;

  (* A record, the first length bytes of bytes *)
  PROCEDURE Put*(f: File; VAR bytes: ARRAY OF SYSTEM.BYTE; length: INTEGER);
  BEGIN
    IF ~f.open THEN Fail("record written to a closed file", f) END;
    IF (length < 0) OR (length > f.maximum) OR (length > LEN(bytes)) THEN
      Fail("record of a length the file does not take", f)
    END;
    IF ~ODD(POC_RECORD_PUT(f.control, bytes, length)) THEN Fail("record not written", f) END
  END Put;

  (* The n bytes of a from at, least significant first, as a number *)
  PROCEDURE Unsigned(VAR a: Attributes; at, n: INTEGER): LONGINT;
    VAR value: LONGINT;
  BEGIN
    value := 0;
    WHILE n > 0 DO DEC(n); value := value * 256 + ORD(a[at + n]) END;
    RETURN value
  END Unsigned;

  (* The file name's resultant name, its creation time (XAB$Q_CDT, the 8
     bytes of created, least significant first), end-of-file block
     (XAB$L_EBK), first free byte (XAB$W_FFB) and record format and
     organization (XAB$B_RFO): FALSE if it cannot be opened, or a name
     does not fit *)
  PROCEDURE Describe*(name: ARRAY OF CHAR; VAR resultant, created: ARRAY OF CHAR;
                      VAR endBlock, firstFree, format: LONGINT): BOOLEAN;
    VAR control: Control; given: Name; a: Attributes; n, i: INTEGER;
  BEGIN
    n := Length0X(name);
    IF (n = 0) OR (n >= nameLength) OR (LEN(created) < 8) THEN RETURN FALSE END;
    COPY(name, given);
    IF ~ODD(POC_RECORD_ATTRIBUTES(control, given, n, a)) THEN RETURN FALSE END;
    n := ORD(a[16]);
    IF n >= LEN(resultant) THEN RETURN FALSE END;
    FOR i := 0 TO n - 1 DO resultant[i] := a[17 + i] END;
    resultant[n] := 0X;
    FOR i := 0 TO 7 DO created[i] := a[i] END;
    endBlock := Unsigned(a, 8, 4); firstFree := Unsigned(a, 12, 2); format := ORD(a[14]);
    RETURN TRUE
  END Describe;

  PROCEDURE Close*(f: File);
  BEGIN
    IF f.open THEN
      f.open := FALSE;
      IF ~ODD(POC_FILE_CLOSE(f.control)) THEN Fail("file not closed", f) END
    END
  END Close;

END RecordFiles.
