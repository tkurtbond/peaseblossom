MODULE Directories;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 4): directories, and the names of the files in them, the
     same way on Unix and on VAX/VMS, through which poc's own source names
     its files for either; rtl/vax/Directories.Mod has the same interface.
     voc has no such module: rtl/voc/Directories.Mod is this one over voc's
     Platform, for the poc voc builds.

     On Unix a directory and a file's name in it are joined with "/", and
     a list of directories, such as POC_IMPORT_PATH, is separated by ":".
     IsDirectory and MakeDirectory are in Directories.c beside this file,
     compiled by clang from the system's own headers, as Platform.c is.

     A string handed to C must end in 0X within its array; one that does
     not names nothing: IsDirectory and MakeDirectory return FALSE. *)

  IMPORT SYSTEM;

  CONST
    (* what separates the directories of a list of them *)
    pathSeparator* = ":";

  PROCEDURE ["C", "Directories.-is-directory"] CIsDirectory(name: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "Directories.-make"] CMake(name: SYSTEM.ADDRESS): SYSTEM.INT32;

  (* Whether s has a terminating 0X inside its array. *)
  PROCEDURE Terminated(VAR s: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k < LEN(s)
  END Terminated;

  (* The file name in the directory dir in path, cut short if path is too
     small: dir and name with "/" between them, unless dir is "" or
     already ends in "/". *)
  PROCEDURE MakePath*(dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) & (i < LEN(path) - 1) DO path[i] := dir[i]; INC(i) END;
    IF (i > 0) & (path[i - 1] # "/") & (i < LEN(path) - 1) THEN path[i] := "/"; INC(i) END;
    j := 0;
    WHILE (j < LEN(name)) & (name[j] # 0X) & (i < LEN(path) - 1) DO path[i] := name[j]; INC(i); INC(j) END;
    IF LEN(path) > 0 THEN path[i] := 0X END
  END MakePath;

  (* Whether dir names a directory that exists. *)
  PROCEDURE IsDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN Terminated(dir) & (CIsDirectory(SYSTEM.ADR(dir)) # 0)
  END IsDirectory;

  (* Makes the directory dir and those it is in that are missing, as mkdir
     -p does; whether dir is a directory afterwards. *)
  PROCEDURE MakeDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT; e: SYSTEM.INT32;
  BEGIN
    IF ~Terminated(dir) THEN RETURN FALSE END;
    (* each directory on the way, ended where its "/" is; one that is
       there already fails, which does not matter *)
    k := 1;
    WHILE dir[k - 1] # 0X DO
      IF dir[k] = "/" THEN
        dir[k] := 0X; e := CMake(SYSTEM.ADR(dir)); dir[k] := "/"
      END;
      INC(k)
    END;
    e := CMake(SYSTEM.ADR(dir));
    RETURN CIsDirectory(SYSTEM.ADR(dir)) # 0
  END MakeDirectory;

END Directories.
