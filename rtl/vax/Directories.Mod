MODULE Directories;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 4): rtl/llvm/Directories.Mod's interface for VAX/VMS, over
     the services rtl/vax/PocRtl.mar calls.

     A directory ends with ":" (a device, or a logical name standing for a
     directory), "]" or ">", and a file's name follows it at once; a list
     of directories, such as POC$IMPORT, is separated by ",", since a
     directory has ":" in it. A directory given without one of those ends
     is taken as a logical name, and ":" added. RMS takes a name of at most
     255 characters; a longer one names nothing here.

     A subdirectory goes inside the brackets ([A] and B give [A.B]), so
     a directory named by a logical name is translated first: RMS finds
     nothing through LOG:[.B] or LOG:[B] unless LOG is a rooted logical
     name (found on the development system, 2026-10-12). *)

  IMPORT SYSTEM, Platform;

  CONST
    (* what separates the directories of a list of them *)
    pathSeparator* = ",";

    nameLength = 256; (* a name and its 0X *)

  TYPE
    Name = ARRAY nameLength OF CHAR;
    (* a search for the files a pattern names (StartSearch, NextFile),
       LIB$FIND_FILE's context *)
    Search* = RECORD
      context: SYSTEM.INT32
    END;

  VAR
    given: Name; (* the name given to a service *)

  (* the status of RMS's $PARSE of the name, which looks its directory up,
     and of LIB$CREATE_DIR's making it *)
  PROCEDURE ["VMS"] POC_PARSE(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_CREATE_DIRECTORY(VAR name: Name; length: INTEGER): INTEGER;
  (* LIB$FIND_FILE's next file, blank-padded to size, and its status;
     LIB$FIND_FILE_END *)
  PROCEDURE ["VMS"] POC_FIND_FILE(VAR name: Name; length: INTEGER; VAR context: SYSTEM.INT32;
                                  VAR value: Name; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_FIND_FILE_END(VAR context: SYSTEM.INT32): INTEGER;

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

  (* The subdirectory name of the directory dir in path, cut short if path
     is too small: name inside dir's brackets, [A] and B giving [A.B], []
     and B [.B], and a rooted directory's [A.] and B [A.B]. A dir that
     does not end in "]" or ">" is a logical name, or a device, and is
     translated (Platform.GetEnv; a search list's first string), until it
     does, at most ten times; one that cannot be gives dir[B], and "" gives
     [.B], a subdirectory of the default directory. *)
  PROCEDURE MakeSubdirectory*(dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR
      d, translated: Name; i, k: LONGINT; translations: INTEGER; close, last: CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) & (i < nameLength - 1) DO d[i] := dir[i]; INC(i) END;
    d[i] := 0X;
    translations := 0;
    WHILE (i > 0) & ~((d[i - 1] = "]") OR (d[i - 1] = ">")) & (translations < 10) DO
      last := d[i - 1];
      IF last = ":" THEN d[i - 1] := 0X END;
      Platform.GetEnv(d, translated);
      IF translated[0] = 0X THEN
        d[i - 1] := last; translations := 10 (* not a logical name *)
      ELSE
        i := 0;
        WHILE (translated[i] # 0X) & (translated[i] # pathSeparator) DO d[i] := translated[i]; INC(i) END;
        d[i] := 0X; INC(translations)
      END
    END;
    k := 0;
    IF (i > 0) & ((d[i - 1] = "]") OR (d[i - 1] = ">")) THEN
      close := d[i - 1]; DEC(i);
      WHILE (k < i) & (k < LEN(path) - 1) DO path[k] := d[k]; INC(k) END;
      IF (i > 0) & (d[i - 1] # ".") & (k < LEN(path) - 1) THEN path[k] := "."; INC(k) END
    ELSE
      close := "]";
      WHILE (k < i) & (k < LEN(path) - 1) DO path[k] := d[k]; INC(k) END;
      IF i > 0 THEN
        IF ~EndsDirectory(d[i - 1]) & (k < LEN(path) - 1) THEN path[k] := ":"; INC(k) END;
        IF k < LEN(path) - 1 THEN path[k] := "["; INC(k) END
      ELSIF LEN(path) > 2 THEN
        path[0] := "["; path[1] := "."; k := 2
      END
    END;
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) & (k < LEN(path) - 1) DO path[k] := name[i]; INC(i); INC(k) END;
    IF k < LEN(path) - 1 THEN path[k] := close; INC(k) END;
    IF LEN(path) > 0 THEN path[k] := 0X END
  END MakeSubdirectory;

  (* Where the file's own name starts in path: after its last ":", "]" or
     ">", or 0. *)
  PROCEDURE NameStart*(path: ARRAY OF CHAR): INTEGER;
    VAR i, start: INTEGER;
  BEGIN
    i := 0; start := 0;
    WHILE (i < LEN(path)) & (path[i] # 0X) DO
      IF EndsDirectory(path[i]) THEN start := i + 1 END;
      INC(i)
    END;
    RETURN start
  END NameStart;

  (* A search for the files a pattern names, through NextFile *)
  PROCEDURE StartSearch*(VAR search: Search);
  BEGIN
    search.context := 0
  END StartSearch;

  (* The next file the pattern names, in name, cut short if name is too
     small: FALSE, the search ended, when there is no other
     (LIB$FIND_FILE, then LIB$FIND_FILE_END). A name is RMS's whole
     specification without its version, DUA1:[A]B.MOD; a pattern without
     a wildcard gives the file it names, if it is there. *)
  PROCEDURE NextFile*(VAR search: Search; pattern: ARRAY OF CHAR; VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR length, status, i, end: INTEGER; found: Name;
  BEGIN
    IF LEN(name) = 0 THEN RETURN FALSE END;
    name[0] := 0X;
    IF Fill(pattern, length) THEN
      (* a file's name, not a directory's: without the ":" Fill adds *)
      i := 0; WHILE (i < LEN(pattern)) & (pattern[i] # 0X) DO INC(i) END;
      IF ~EndsDirectory(pattern[i - 1]) THEN DEC(length) END;
      status := POC_FIND_FILE(given, length, search.context, found, nameLength - 1)
    ELSE
      status := 0
    END;
    IF ~ODD(status) THEN
      status := POC_FIND_FILE_END(search.context); search.context := 0;
      RETURN FALSE
    END;
    (* the specification, its blanks and version dropped *)
    i := 0;
    WHILE (i < nameLength - 1) & (found[i] # " ") & (found[i] # ";") DO INC(i) END;
    end := i; i := 0;
    WHILE (i < end) & (i < LEN(name) - 1) DO name[i] := found[i]; INC(i) END;
    name[i] := 0X;
    RETURN TRUE
  END NextFile;

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
