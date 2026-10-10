MODULE PlatformOut;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposals 3 to 8): Platform's and Directories' procedures, on the
     names the command line gives, which differ between Unix and VMS: 1 a directory
     there is, 2 one there is not, 3 one to make, two levels below one
     there is not yet, 4 a variable or logical name. A file doomed.tmp is
     there to be deleted. *)
  IMPORT Platform, Directories, Modules, Out;
  VAR dir, missing, made, name, path, value: ARRAY 256 OF CHAR; s: ARRAY 8 OF CHAR;

  PROCEDURE Bool(text: ARRAY OF CHAR; b: BOOLEAN);
  BEGIN
    Out.String(text); IF b THEN Out.String(" TRUE") ELSE Out.String(" FALSE") END; Out.Ln
  END Bool;

  PROCEDURE Path(dir: ARRAY OF CHAR);
  BEGIN
    Directories.MakePath(dir, "x.mod", path); Out.String("path ["); Out.String(path); Out.String("]"); Out.Ln
  END Path;

BEGIN
  Modules.GetArg(1, dir); Modules.GetArg(2, missing); Modules.GetArg(3, made); Modules.GetArg(4, name);
  Out.String("separator "); Out.Char(Directories.pathSeparator); Out.Ln;
  Path(dir); Path(""); Path("lib"); Path("lib/"); Path("DISK:"); Path("[LIB]");
  Directories.MakePath("dir", "x.mod", s); Out.String("cut short ["); Out.String(s); Out.String("]"); Out.Ln;
  Bool("is a directory:", Directories.IsDirectory(dir));
  Bool("missing is a directory:", Directories.IsDirectory(missing));
  Bool("made is a directory:", Directories.IsDirectory(made));
  Bool("made:", Directories.MakeDirectory(made));
  Bool("made is a directory:", Directories.IsDirectory(made));
  Bool("made again:", Directories.MakeDirectory(made));
  Platform.GetEnv(name, value); Out.String("value ["); Out.String(value); Out.String("]"); Out.Ln;
  Platform.GetEnv("POC_NO_SUCH_NAME", value); Out.String("no value ["); Out.String(value); Out.String("]"); Out.Ln;
  value := "doomed.tmp";
  Bool("deleted:", Platform.Unlink(value) = 0);
  value := "no-such-file.tmp";
  Bool("deleted a missing file:", Platform.Unlink(value) = 0);
  Bool("PID positive:", Platform.PID > 0);
  Bool("CWD known:", Platform.CWD[0] # 0X);
  Out.String("System "); Out.Int(Platform.System("true"), 0); Out.Ln;
  Platform.Exit(3)
END PlatformOut.
