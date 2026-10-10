MODULE Directories;

  (* PLAN.md Phase 16 step 4: voc's version of rtl/llvm/Directories.Mod,
     with the same interface, over voc's Platform module, which has no such
     procedures. Stage 0 (tools/bootstrap/stage0) compiles it with poc's own
     source, as it does FileDescriptorOutput. IsDirectory changes to the
     directory and back, and MakeDirectory runs mkdir -p, as poc's source
     did before it had this module. *)

  IMPORT Platform;

  CONST
    (* what separates the directories of a list of them *)
    pathSeparator* = ":";

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

  (* Whether dir names a directory that exists: whether the process can
     change to it, which it then changes back from. *)
  PROCEDURE IsDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR saved: ARRAY 256 OF CHAR; ok: BOOLEAN; e: Platform.ErrorCode;
  BEGIN
    COPY(Platform.CWD, saved);
    ok := Platform.Chdir(dir) = 0;
    IF ok THEN e := Platform.Chdir(saved) END;
    RETURN ok
  END IsDirectory;

  (* Makes the directory dir and those it is in that are missing, by mkdir
     -p, given dir in single quotes; whether dir is a directory
     afterwards. mkdir's own message is discarded: the caller words its
     own, as each system words mkdir's differently. *)
  PROCEDURE MakeDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR command: ARRAY 1100 OF CHAR; suffix: ARRAY 14 OF CHAR; i, k: LONGINT; status: INTEGER;
  BEGIN
    command := "mkdir -p '"; k := 10; i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) & (k < LEN(command) - 18) DO
      IF dir[i] = "'" THEN (* ' ends the quotes, \' is one, ' starts them again *)
        command[k] := "'"; command[k + 1] := "\"; command[k + 2] := "'"; command[k + 3] := "'"; INC(k, 4)
      ELSE command[k] := dir[i]; INC(k)
      END;
      INC(i)
    END;
    suffix := "' 2>/dev/null"; i := 0;
    WHILE suffix[i] # 0X DO command[k] := suffix[i]; INC(k); INC(i) END;
    command[k] := 0X;
    status := Platform.System(command);
    RETURN IsDirectory(dir)
  END MakeDirectory;

END Directories.
