MODULE Directories;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 4): rtl/llvm/Directories.Mod's interface for VAX/VMS, over
     the services rtl/vax/PocRtl.mar calls.

     A directory ends with ":" (a device, or a logical name standing for a
     directory), "]" or ">", and a file's name follows it at once; a list
     of directories, such as POC_IMPORT_PATH, is separated by ",", since a
     directory has ":" in it. A directory given without one of those ends
     is taken as a logical name, and ":" added. RMS takes a name of at most
     255 characters; a longer one names nothing here. *)

  CONST
    (* what separates the directories of a list of them *)
    pathSeparator* = ",";

    nameLength = 256; (* a name and its 0X *)

  TYPE
    Name = ARRAY nameLength OF CHAR;

  VAR
    given: Name; (* the name given to a service *)

  (* the status of RMS's $PARSE of the name, which looks its directory up,
     and of LIB$CREATE_DIR's making it *)
  PROCEDURE ["VMS"] POC_PARSE(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_CREATE_DIRECTORY(VAR name: Name; length: INTEGER): INTEGER;

  (* Whether c ends a directory. *)
  PROCEDURE EndsDirectory(c: CHAR): BOOLEAN;
  BEGIN
    RETURN (c = ":") OR (c = "]") OR (c = ">")
  END EndsDirectory;

  (* dir up to its 0X in given, with ":" after it if it does not end a
     directory, and its length in length; FALSE if it is "" or longer than
     RMS takes *)
  PROCEDURE Fill(VAR dir: ARRAY OF CHAR; VAR length: INTEGER): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) DO
      IF i = nameLength - 1 THEN RETURN FALSE END;
      given[i] := dir[i]; INC(i)
    END;
    IF i = 0 THEN RETURN FALSE END;
    IF ~EndsDirectory(given[i - 1]) THEN
      IF i = nameLength - 1 THEN RETURN FALSE END;
      given[i] := ":"; INC(i)
    END;
    given[i] := 0X; length := SHORT(i);
    RETURN TRUE
  END Fill;

  (* The file name in the directory dir in path, cut short if path is too
     small: dir and name joined, with ":" between them when dir does not
     end a directory - a logical name standing for one - and nothing
     between them when it does, or when dir is "". *)
  PROCEDURE MakePath*(dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) & (i < LEN(path) - 1) DO path[i] := dir[i]; INC(i) END;
    IF (i > 0) & (i < LEN(path) - 1) & ~EndsDirectory(path[i - 1]) THEN path[i] := ":"; INC(i) END;
    j := 0;
    WHILE (j < LEN(name)) & (name[j] # 0X) & (i < LEN(path) - 1) DO path[i] := name[j]; INC(i); INC(j) END;
    IF LEN(path) > 0 THEN path[i] := 0X END
  END MakePath;

  (* Whether dir names a directory that exists: RMS parses it, which looks
     the directory up ($PARSE, with no file name). *)
  PROCEDURE IsDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR length: INTEGER;
  BEGIN
    RETURN Fill(dir, length) & ODD(POC_PARSE(given, length))
  END IsDirectory;

  (* Makes the directory dir and those it is in that are missing
     (LIB$CREATE_DIR); whether dir is a directory afterwards. *)
  PROCEDURE MakeDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR length: INTEGER;
  BEGIN
    RETURN Fill(dir, length) & ODD(POC_CREATE_DIRECTORY(given, length))
  END MakeDirectory;

END Directories.
