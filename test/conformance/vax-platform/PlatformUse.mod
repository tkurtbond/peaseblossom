MODULE PlatformUse;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposals 4, 5 and 8): what rtl/vax's Platform and Directories
     give, kept for the debugger run *)
  IMPORT Platform, Directories;
  VAR
    separator: CHAR; path, disk: ARRAY 64 OF CHAR; home, missing: BOOLEAN;
    pid, gone: INTEGER;
BEGIN
  separator := Directories.pathSeparator;
  Directories.MakePath("SYS$LOGIN", "X.MOD", path);
  home := Directories.IsDirectory("SYS$LOGIN");
  missing := Directories.IsDirectory("[.NO-SUCH-DIRECTORY]");
  Platform.GetEnv("SYS$DISK", disk);
  pid := Platform.PID;
  path[63] := 0X; (* the debugger examines path as a string *)
  gone := Platform.Unlink(path)
END PlatformUse.
