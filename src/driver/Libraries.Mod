MODULE Libraries;

  (* Phase 12 step 2c: poc's libraries, as PLAN.md's step 2 design has them.

     A library is a named set of modules, compiled for one target and size
     model, in the directory <base>/<triple>/<O2|OC>/ (its tuple directory):
     each module's .sym, .ll and .o, the archive lib<name>.a, the shared
     library, and the manifest <name>.library. The manifest is text, one fact
     a line, the words separated by one space:

       library <name>
       poc <version>                    (the poc that wrote it, Version.number)
       triple <triple>
       model <O2|OC>
       lto                              (its objects are LLVM bitcode, for -flto)
       needs <library>                  (each library its modules import from)
       c++                              (a module has a part in C++)
       link <arg>                       (each -link <arg> it was built with)
       module <Module> <key>            (each module, with its key)
       import <Module> <Imported> <key> (each import, with the key compiled against)
       source <Module> <key>            (each module's source file, hashed as a key is)

     so poc can tell, before a link, whether a library was compiled against
     the interface of a module that another library now has; a link line's
     argument is the rest of the line, spaces and all, for every link of
     a program that uses the library. A library
     another version of poc wrote, or one written before manifests recorded
     the version, is refused (Phase 13 step 1): nothing promises that two
     versions' objects link together. Beside it, for
     each of its modules, <Module>.owner holds the library's name: that is
     how a module an import names is found without listing a directory. A
     module belongs to one library only.

     The library path is the list of base directories searched, in order:
     -library-path, POC_LIBRARY_PATH, then <poc's directory>/../lib/poc. The
     first one whose tuple directory has <Module>.owner owns the module; a
     warning names any later one that has it too (Phase 12 step 2e).

     Under poc -g (Phase 13 step 3) a library is built in, and looked for
     first in, <base>/<triple>/<O2|OC>-g/, its copy compiled with debug
     information, so that a debugger sees into it; a base without that
     directory is searched as usual. Both copies have the same interface,
     and the same module keys, so either links with the other's
     importers. poc's own lib/poc is "installed" (IsInstalled): a program
     linking one of its shared libraries names it only absolutely.

     Nothing here knows about LLVM: the driver builds and links, this module
     finds, reads and writes manifests, and checks that the libraries a
     program would link agree with each other. *)

  IMPORT Files, Platform, Err, Version;

  CONST
    nameLength* = 256;
    pathLength* = 1024;
    keyLength* = 16;
    lineLength = 2048;
    linkLength* = lineLength - 5; (* what follows "link " on its line *)

  TYPE
    Name* = ARRAY nameLength OF CHAR;
    Path* = ARRAY pathLength OF CHAR;
    Key* = ARRAY keyLength + 1 OF CHAR;

    PathEntry* = POINTER TO PathEntryDesc;
    PathEntryDesc* = RECORD
      dir*: Path;
      next*: PathEntry
    END;

    (* one import of a module, with the key of the imported module's
       interface it was compiled against *)
    ImportKey* = POINTER TO ImportKeyDesc;
    ImportKeyDesc* = RECORD
      name*: Name;
      key*: Key;
      next*: ImportKey
    END;

    Member* = POINTER TO MemberDesc;
    MemberDesc* = RECORD
      name*: Name;
      key*: Key;
      source*: Key; (* of the file it was compiled from; "" when unknown *)
      imports*: ImportKey;
      next*: Member
    END;

    Need* = POINTER TO NeedDesc;
    NeedDesc* = RECORD
      name*: Name;
      next*: Need
    END;

    (* an argument for the link of every program that links a library
       (Ongoing implementation enhancements, item 1) *)
    LinkArgument* = POINTER TO LinkArgumentDesc;
    LinkArgumentDesc* = RECORD
      arg*: ARRAY linkLength OF CHAR;
      next*: LinkArgument
    END;

    (* a key an object defines or refers to (Phase 12 step 2f) *)
    ObjectKey* = POINTER TO ObjectKeyDesc;
    ObjectKeyDesc* = RECORD
      module*: Name;
      model*: ARRAY 3 OF CHAR;
      key*: Key;
      next*: ObjectKey
    END;

    (* what a module's object says of itself (ReadObject) *)
    ObjectInfo* = RECORD
      defined*: ObjectKey; (* its own key *)
      imports*: ObjectKey; (* the keys of its imports it was compiled against *)
      targetModule*, target*: Name; (* from <Module>.-target.<triple> *)
      usesCollector*: BOOLEAN (* it calls GarbageCollectedHeap *)
    END;

    (* a module whose hidden copies WarnHidden has looked for *)
    Checked = POINTER TO CheckedDesc;
    CheckedDesc = RECORD
      name: Name;
      next: Checked
    END;

    Library* = POINTER TO LibraryDesc;
    LibraryDesc* = RECORD
      name*: Name;
      dir*: Path; (* its tuple directory *)
      triple*: Name;
      model*: ARRAY 3 OF CHAR;
      pocVersion*: Name; (* the poc that wrote it; empty if its manifest does not say *)
      modules*: Member;
      needs*: Need;
      lto*: BOOLEAN; (* its objects are LLVM bitcode (Phase 12 step 2g) *)
      cxx*: BOOLEAN; (* a module of it has a part in C++, so clang++ links it *)
      links*: LinkArgument; (* its -link arguments, in order *)
      used*: BOOLEAN; (* linked into the program being built *)
      refused: BOOLEAN; (* its manifest was wrong, said once (Load) *)
      next: Library; (* in loaded *)
      linkNext*: Library (* in linkOrder *)
    END;

  VAR
    pathHead, pathTail: PathEntry;
    triple: Name;
    model: ARRAY 3 OF CHAR;
    excluded: Name; (* the library being built, never taken from the path *)
    debug: BOOLEAN; (* poc -g: <model>-g first (SetDebug) *)
    defaultDir: Path; (* poc's own lib/poc, "" when it has none *)
    loaded: Library;
    checked: Checked;
    (* the used libraries, each before those it needs (ComputeLinkOrder) *)
    linkOrder*: Library;
    (* how many manifests could not be used (Load reported each) *)
    errors*: INTEGER;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; suffix: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (suffix[j] # 0X) & (i < LEN(s) - 1) DO s[i] := suffix[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Append;

  PROCEDURE JoinPath(dir, name: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
  BEGIN
    COPY(dir, result); Append(result, "/"); Append(result, name)
  END JoinPath;

  (* ---- The library path ---- *)

  PROCEDURE AddPathDir*(dir: ARRAY OF CHAR);
    VAR e: PathEntry;
  BEGIN
    IF dir[0] = 0X THEN RETURN END;
    NEW(e); COPY(dir, e.dir); e.next := NIL;
    IF pathTail = NIL THEN pathHead := e ELSE pathTail.next := e END;
    pathTail := e
  END AddPathDir;

  (* dirs separated by ":", as POC_LIBRARY_PATH has them *)
  PROCEDURE AddPathList*(list: ARRAY OF CHAR);
    VAR i, j: INTEGER; piece: Path;
  BEGIN
    i := 0;
    WHILE list[i] # 0X DO
      j := 0;
      WHILE (list[i] # 0X) & (list[i] # ":") DO piece[j] := list[i]; INC(j); INC(i) END;
      piece[j] := 0X;
      AddPathDir(piece);
      IF list[i] = ":" THEN INC(i) END
    END
  END AddPathList;

  PROCEDURE ClearPath*;
  BEGIN
    pathHead := NIL; pathTail := NIL
  END ClearPath;

  PROCEDURE FirstPathEntry*(): PathEntry;
  BEGIN
    RETURN pathHead
  END FirstPathEntry;

  PROCEDURE Exists(path: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File;
  BEGIN
    f := Files.Old(path);
    IF f # NIL THEN Files.Close(f) END;
    RETURN f # NIL
  END Exists;

  (* <dir>/../lib/poc, dir the directory poc's executable is in, as an
     absolute path, in result; with create, made first if it is not there.
     FALSE when it is not there (or cannot be made). The shell finds it
     (command -v, through PATH when program, argument 0, names no
     directory), as a file cannot be opened to test that it is there: voc's
     Files.Old opens for writing first, which the running executable
     refuses. *)
  (* /tmp/poc-<what>-<pid>, for a command's output *)
  PROCEDURE ScratchFile(what: ARRAY OF CHAR; VAR scratch: ARRAY OF CHAR);
    VAR number: ARRAY 12 OF CHAR; n, i: INTEGER;
  BEGIN
    n := Platform.PID; i := 0;
    REPEAT number[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
    COPY("/tmp/poc-", scratch); Append(scratch, what); Append(scratch, "-");
    n := 0; WHILE scratch[n] # 0X DO INC(n) END;
    WHILE i > 0 DO DEC(i); scratch[n] := number[i]; INC(n) END;
    scratch[n] := 0X
  END ScratchFile;

  PROCEDURE PocLibraryDir*(program: ARRAY OF CHAR; create: BOOLEAN; VAR result: ARRAY OF CHAR): BOOLEAN;
    VAR
      scratch: ARRAY 64 OF CHAR; command: ARRAY 2 * pathLength OF CHAR;
      i, status: INTEGER; f: Files.File; r: Files.Rider;
  BEGIN
    result[0] := 0X;
    i := 0;
    WHILE program[i] # 0X DO
      IF program[i] = "'" THEN RETURN FALSE END; (* not worth quoting *)
      INC(i)
    END;
    ScratchFile("library-path", scratch);
    (* through any symbolic links to poc, to the directory it is really in,
       so that a link to it from elsewhere (~/bin/poc) finds its library;
       readlink without -f, which each of the four systems has *)
    command := "p=$(command -v '"; Append(command, program);
    Append(command, "') && while [ -h ");
    Append(command, '"$p" ]; do l=$(readlink "$p"); ');
    Append(command, 'case "$l" in /*) p=$l ;; *) p=$(dirname "$p")/$l ;; esac; done && d=');
    Append(command, '"$(dirname "$p")/../lib/poc"');
    IF create THEN Append(command, ' && mkdir -p "$d"') END;
    Append(command, ' && cd "$d" 2>/dev/null && pwd >');
    Append(command, scratch);
    status := Platform.System(command);
    f := Files.Old(scratch);
    IF f # NIL THEN
      Files.Set(r, f, 0); Files.ReadLine(r, result); Files.Close(f)
    END;
    status := Platform.Unlink(scratch);
    RETURN result[0] # 0X
  END PocLibraryDir;

  (* The last entry of the path: PocLibraryDir, when it is there *)
  PROCEDURE AddDefaultPathDir*(program: ARRAY OF CHAR);
  BEGIN
    IF PocLibraryDir(program, FALSE, defaultDir) THEN AddPathDir(defaultDir) END
  END AddDefaultPathDir;

  (* dir, a tuple directory, is in poc's own lib/poc *)
  PROCEDURE IsInstalled*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    IF defaultDir[0] = 0X THEN RETURN FALSE END;
    i := 0;
    WHILE (defaultDir[i] # 0X) & (dir[i] = defaultDir[i]) DO INC(i) END;
    RETURN (defaultDir[i] = 0X) & (dir[i] = "/")
  END IsInstalled;

  (* ---- Target ---- *)

  (* the target and size model ("O2" or "OC") libraries are looked for and
     built for *)
  PROCEDURE SetTarget*(targetTriple, sizeModel: ARRAY OF CHAR);
  BEGIN
    COPY(targetTriple, triple); COPY(sizeModel, model)
  END SetTarget;

  (* poc -g: libraries are built in, and looked for first in, <model>-g *)
  PROCEDURE SetDebug*(on: BOOLEAN);
  BEGIN
    debug := on
  END SetDebug;

  (* base/<triple>/<model>, or <model>-g with withDebug *)
  PROCEDURE ModelDirectory(base: ARRAY OF CHAR; withDebug: BOOLEAN; VAR dir: ARRAY OF CHAR);
  BEGIN
    IF base[0] = 0X THEN COPY(".", dir) ELSE COPY(base, dir) END;
    Append(dir, "/"); Append(dir, triple); Append(dir, "/"); Append(dir, model);
    IF withDebug THEN Append(dir, "-g") END
  END ModelDirectory;

  (* base/<triple>/<model>, where a library is built: <model>-g under -g *)
  PROCEDURE TupleDirectory*(base: ARRAY OF CHAR; VAR dir: ARRAY OF CHAR);
  BEGIN
    ModelDirectory(base, debug, dir)
  END TupleDirectory;

  (* The owner of name in the tuple directory dir, from <Module>.owner *)
  PROCEDURE ReadOwner(dir, name: ARRAY OF CHAR; VAR owner: ARRAY OF CHAR): BOOLEAN;
    VAR path: Path; f: Files.File; r: Files.Rider;
  BEGIN
    JoinPath(dir, name, path); Append(path, ".owner");
    f := Files.Old(path);
    IF f # NIL THEN Files.Set(r, f, 0); Files.ReadLine(r, owner); Files.Close(f) END;
    RETURN f # NIL
  END ReadOwner;

  (* The tuple directory under base with the module name, in dir, and its
     library in owner: under -g, <model>-g if it has the module, else
     <model> *)
  PROCEDURE FindOwner(base, name: ARRAY OF CHAR; VAR dir, owner: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF debug THEN
      ModelDirectory(base, TRUE, dir);
      IF ReadOwner(dir, name, owner) THEN RETURN TRUE END
    END;
    ModelDirectory(base, FALSE, dir);
    RETURN ReadOwner(dir, name, owner)
  END FindOwner;

  PROCEDURE HasOwner*(dir, name: ARRAY OF CHAR; VAR owner: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN ReadOwner(dir, name, owner)
  END HasOwner;

  PROCEDURE GetTarget*(VAR targetTriple, sizeModel: ARRAY OF CHAR);
  BEGIN
    COPY(triple, targetTriple); COPY(model, sizeModel)
  END GetTarget;

  (* The library whose tuple directory for sizeModel under base,
     <base>/<triple>/<sizeModel>, has the module name: its name in owner and
     that directory in dir. FALSE when it has none. For saying where a
     module the path does not give was found anyway. *)
  PROCEDURE OwnerIn*(base, sizeModel, name: ARRAY OF CHAR; VAR owner, dir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF base[0] = 0X THEN COPY(".", dir) ELSE COPY(base, dir) END;
    Append(dir, "/"); Append(dir, triple); Append(dir, "/"); Append(dir, sizeModel);
    RETURN ReadOwner(dir, name, owner)
  END OwnerIn;

  PROCEDURE Exclude*(name: ARRAY OF CHAR);
  BEGIN
    COPY(name, excluded)
  END Exclude;

  (* ---- Reading manifests ---- *)

  (* the first four words of line, "" for the ones missing *)
  PROCEDURE SplitLine(line: ARRAY OF CHAR; VAR w0, w1, w2, w3: ARRAY OF CHAR);
    VAR i, n, j: INTEGER; ch: CHAR;
  BEGIN
    w0[0] := 0X; w1[0] := 0X; w2[0] := 0X; w3[0] := 0X;
    i := 0; n := 0;
    WHILE (line[i] # 0X) & (n < 4) DO
      WHILE line[i] = " " DO INC(i) END;
      j := 0;
      WHILE (line[i] # 0X) & (line[i] # " ") DO
        ch := line[i];
        CASE n OF
        0: IF j < LEN(w0) - 1 THEN w0[j] := ch END
        | 1: IF j < LEN(w1) - 1 THEN w1[j] := ch END
        | 2: IF j < LEN(w2) - 1 THEN w2[j] := ch END
        | 3: IF j < LEN(w3) - 1 THEN w3[j] := ch END
        END;
        INC(i); INC(j)
      END;
      IF j > 0 THEN
        CASE n OF
        0: w0[j] := 0X | 1: w1[j] := 0X | 2: w2[j] := 0X | 3: w3[j] := 0X
        END;
        INC(n)
      END
    END
  END SplitLine;

  PROCEDURE FindMember*(lib: Library; name: ARRAY OF CHAR): Member;
    VAR m: Member;
  BEGIN
    m := lib.modules;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    RETURN m
  END FindMember;

  PROCEDURE AddMember*(lib: Library; name, key: ARRAY OF CHAR): Member;
    VAR m, tail: Member;
  BEGIN
    NEW(m); COPY(name, m.name); COPY(key, m.key); m.source[0] := 0X; m.imports := NIL; m.next := NIL;
    IF lib.modules = NIL THEN lib.modules := m
    ELSE
      tail := lib.modules;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := m
    END;
    RETURN m
  END AddMember;

  PROCEDURE AddImport*(m: Member; name, key: ARRAY OF CHAR);
    VAR i, tail: ImportKey;
  BEGIN
    NEW(i); COPY(name, i.name); COPY(key, i.key); i.next := NIL;
    IF m.imports = NIL THEN m.imports := i
    ELSE
      tail := m.imports;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := i
    END
  END AddImport;

  PROCEDURE AddNeed*(lib: Library; name: ARRAY OF CHAR);
    VAR n: Need;
  BEGIN
    n := lib.needs;
    WHILE (n # NIL) & (n.name # name) DO n := n.next END;
    IF n = NIL THEN NEW(n); COPY(name, n.name); n.next := lib.needs; lib.needs := n END
  END AddNeed;

  (* arg added at the end of list *)
  PROCEDURE AddLinkArgument*(VAR list: LinkArgument; arg: ARRAY OF CHAR);
    VAR a, tail: LinkArgument;
  BEGIN
    NEW(a); COPY(arg, a.arg); a.next := NIL;
    IF list = NIL THEN list := a
    ELSE
      tail := list;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := a
    END
  END AddLinkArgument;

  PROCEDURE NewLibrary*(name, dir: ARRAY OF CHAR): Library;
    VAR lib: Library;
  BEGIN
    NEW(lib); COPY(name, lib.name); COPY(dir, lib.dir);
    COPY(triple, lib.triple); COPY(model, lib.model);
    lib.modules := NIL; lib.needs := NIL; lib.lto := FALSE; lib.cxx := FALSE; lib.links := NIL; lib.used := FALSE; lib.next := NIL; lib.linkNext := NIL;
    RETURN lib
  END NewLibrary;

  (* The library name whose manifest is in dir, read once. NIL, having said
     why on Err, when the manifest cannot be read, is not for this target
     and size model, or was written by another version of poc; a manifest
     refused is remembered, so it is said once. Without check, only read:
     whatever target, size model and version it is for, and neither looked
     for among nor added to the libraries loaded - for what a copy about to
     be replaced has (LoadInstalled). *)
  PROCEDURE Load(name, dir: ARRAY OF CHAR; check: BOOLEAN): Library;
    VAR
      lib: Library; path: Path; f: Files.File; r: Files.Rider; line: ARRAY lineLength OF CHAR;
      w0, w1, w2, w3: Name; m: Member; ok: BOOLEAN; i: INTEGER;
  BEGIN
    IF check THEN
      lib := loaded;
      WHILE (lib # NIL) & ((lib.name # name) OR (lib.dir # dir)) DO lib := lib.next END;
      IF lib # NIL THEN
        IF lib.refused THEN RETURN NIL ELSE RETURN lib END
      END
    END;
    JoinPath(dir, name, path); Append(path, ".library");
    f := Files.Old(path);
    IF f = NIL THEN
      Err.String("poc: cannot read the manifest "); Err.String(path); Err.Ln;
      INC(errors);
      RETURN NIL
    END;
    lib := NewLibrary(name, dir); lib.triple[0] := 0X; lib.model[0] := 0X; lib.pocVersion[0] := 0X;
    lib.refused := TRUE;
    IF check THEN lib.next := loaded; loaded := lib END;
    ok := TRUE; m := NIL;
    Files.Set(r, f, 0);
    REPEAT
      Files.ReadLine(r, line);
      SplitLine(line, w0, w1, w2, w3);
      IF w0 = "library" THEN ok := w1 = name
      ELSIF w0 = "poc" THEN COPY(w1, lib.pocVersion)
      ELSIF w0 = "triple" THEN COPY(w1, lib.triple)
      ELSIF w0 = "model" THEN COPY(w1, lib.model)
      ELSIF w0 = "needs" THEN AddNeed(lib, w1)
      ELSIF w0 = "lto" THEN lib.lto := TRUE
      ELSIF w0 = "c++" THEN lib.cxx := TRUE
      ELSIF w0 = "link" THEN
        (* the rest of the line, after "link " *)
        ok := (line[4] = " ") & (line[5] # 0X);
        IF ok THEN
          i := 5; WHILE line[i] # 0X DO line[i - 5] := line[i]; INC(i) END;
          line[i - 5] := 0X;
          AddLinkArgument(lib.links, line)
        END
      ELSIF w0 = "module" THEN m := AddMember(lib, w1, w2)
      ELSIF w0 = "import" THEN
        m := FindMember(lib, w1);
        ok := m # NIL;
        IF ok THEN AddImport(m, w2, w3) END
      ELSIF w0 = "source" THEN
        m := FindMember(lib, w1);
        ok := m # NIL;
        IF ok THEN COPY(w2, m.source) END
      ELSIF w0[0] # 0X THEN ok := FALSE
      END
    UNTIL r.eof OR ~ok;
    Files.Close(f);
    IF ~ok THEN
      Err.String("poc: the manifest "); Err.String(path); Err.String(" is malformed"); Err.Ln;
      INC(errors);
      RETURN NIL
    ELSIF ~check THEN
      (* only read *)
    ELSIF (lib.triple # triple) OR (lib.model # model) THEN
      Err.String("poc: the manifest "); Err.String(path); Err.String(" is for ");
      Err.String(lib.triple); Err.String(" "); Err.String(lib.model); Err.String(", not ");
      Err.String(triple); Err.String(" "); Err.String(model); Err.Ln;
      INC(errors);
      RETURN NIL
    ELSIF lib.pocVersion # Version.number THEN
      Err.String("poc: the library "); Err.String(name); Err.String(" in "); Err.String(dir);
      IF lib.pocVersion[0] = 0X THEN Err.String(" was written by a poc that did not record its version")
      ELSE Err.String(" was written by poc "); Err.String(lib.pocVersion)
      END;
      Err.String(", not "); Err.String(Version.number); Err.String(": rebuild it"); Err.Ln;
      INC(errors);
      RETURN NIL
    END;
    lib.refused := FALSE;
    RETURN lib
  END Load;

  (* A warning, once per module, for each library after e on the path that
     has name too: the one found first, lib, hides it *)
  PROCEDURE WarnHidden(name: ARRAY OF CHAR; lib: Library; e: PathEntry);
    VAR dir: Path; owner: Name; c: Checked;
  BEGIN
    c := checked;
    WHILE (c # NIL) & (c.name # name) DO c := c.next END;
    IF c # NIL THEN RETURN END;
    NEW(c); COPY(name, c.name); c.next := checked; checked := c;
    WHILE e # NIL DO
      IF FindOwner(e.dir, name, dir, owner) & (dir # lib.dir) & (owner # excluded) THEN
        Err.String("poc: warning: module "); Err.String(name); Err.String(" is taken from library ");
        Err.String(lib.name); Err.String(" ("); Err.String(lib.dir); Err.String("), which hides library ");
        Err.String(owner); Err.String("'s ("); Err.String(dir); Err.String(")"); Err.Ln
      END;
      e := e.next
    END
  END WarnHidden;

  (* The library name installed in the directory dir, as its manifest
     says, for -install-library to remove the files of before it copies
     another over it: read whatever target, size model or version of poc
     it was written for (installing over a copy an older poc wrote is how
     it is rebuilt), and not loaded for use. NIL, having said why, when the
     manifest cannot be read or is malformed. *)
  PROCEDURE LoadInstalled*(name, dir: ARRAY OF CHAR): Library;
  BEGIN
    RETURN Load(name, dir, FALSE)
  END LoadInstalled;

  (* The library on the path that has the module name, loaded; NIL when
     none has it (or its manifest was wrong, which Load reported) *)
  PROCEDURE FindModule*(name: ARRAY OF CHAR): Library;
    VAR e: PathEntry; dir: Path; owner: Name; lib: Library;
  BEGIN
    e := pathHead;
    WHILE e # NIL DO
      IF FindOwner(e.dir, name, dir, owner) & (owner # excluded) THEN
        lib := Load(owner, dir, TRUE);
        IF lib # NIL THEN WarnHidden(name, lib, e.next) END;
        RETURN lib
      END;
      e := e.next
    END;
    RETURN NIL
  END FindModule;

  (* The library called name on the path, loaded; NIL when there is none *)
  PROCEDURE FindLibrary*(name: ARRAY OF CHAR): Library;
    VAR e: PathEntry; dir, path: Path;
  BEGIN
    IF name = excluded THEN RETURN NIL END;
    e := pathHead;
    WHILE e # NIL DO
      IF debug THEN
        ModelDirectory(e.dir, TRUE, dir);
        JoinPath(dir, name, path); Append(path, ".library");
        IF Exists(path) THEN RETURN Load(name, dir, TRUE) END
      END;
      ModelDirectory(e.dir, FALSE, dir);
      JoinPath(dir, name, path); Append(path, ".library");
      IF Exists(path) THEN RETURN Load(name, dir, TRUE) END;
      e := e.next
    END;
    RETURN NIL
  END FindLibrary;

  (* ---- Writing a library's manifest ---- *)

  PROCEDURE WriteString(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO Files.Write(w, s[i]); INC(i) END
  END WriteString;

  PROCEDURE WriteLine(VAR w: Files.Rider; a, b, c, d: ARRAY OF CHAR);
  BEGIN
    WriteString(w, a);
    IF b[0] # 0X THEN Files.Write(w, " "); WriteString(w, b) END;
    IF c[0] # 0X THEN Files.Write(w, " "); WriteString(w, c) END;
    IF d[0] # 0X THEN Files.Write(w, " "); WriteString(w, d) END;
    Files.Write(w, 0AX)
  END WriteLine;

  (* <lib.dir>/<lib.name>.library, and <lib.dir>/<Module>.owner for each of
     its modules. FALSE, having said so on Err, when a file cannot be
     written. *)
  PROCEDURE WriteManifest*(lib: Library): BOOLEAN;
    VAR path: Path; f: Files.File; w: Files.Rider; m: Member; i: ImportKey; n: Need; a: LinkArgument;
  BEGIN
    JoinPath(lib.dir, lib.name, path); Append(path, ".library");
    f := Files.New(path);
    IF f = NIL THEN Err.String("poc: cannot write "); Err.String(path); Err.Ln; RETURN FALSE END;
    Files.Set(w, f, 0);
    WriteLine(w, "library", lib.name, "", "");
    WriteLine(w, "poc", Version.number, "", "");
    WriteLine(w, "triple", lib.triple, "", "");
    WriteLine(w, "model", lib.model, "", "");
    IF lib.lto THEN WriteLine(w, "lto", "", "", "") END;
    n := lib.needs;
    WHILE n # NIL DO WriteLine(w, "needs", n.name, "", ""); n := n.next END;
    IF lib.cxx THEN WriteLine(w, "c++", "", "", "") END;
    a := lib.links;
    WHILE a # NIL DO WriteLine(w, "link", a.arg, "", ""); a := a.next END;
    m := lib.modules;
    WHILE m # NIL DO WriteLine(w, "module", m.name, m.key, ""); m := m.next END;
    m := lib.modules;
    WHILE m # NIL DO
      IF m.source[0] # 0X THEN WriteLine(w, "source", m.name, m.source, "") END;
      m := m.next
    END;
    m := lib.modules;
    WHILE m # NIL DO
      i := m.imports;
      WHILE i # NIL DO WriteLine(w, "import", m.name, i.name, i.key); i := i.next END;
      m := m.next
    END;
    Files.Register(f); Files.Close(f);
    m := lib.modules;
    WHILE m # NIL DO
      JoinPath(lib.dir, m.name, path); Append(path, ".owner");
      f := Files.New(path);
      IF f = NIL THEN Err.String("poc: cannot write "); Err.String(path); Err.Ln; RETURN FALSE END;
      Files.Set(w, f, 0); WriteLine(w, lib.name, "", "", "");
      Files.Register(f); Files.Close(f);
      m := m.next
    END;
    RETURN TRUE
  END WriteManifest;

  (* ---- A module's object (Phase 12 step 2f) ----

     A module compiled by poc says in its object's symbols what it is: it
     defines <Module>.-key.<O2|OC>.<key> and <Module>.-target.<triple>, and
     refers to <Import>.-key.<O2|OC>.<key> for each module it imports. Read
     with nm -P ("name type ..." a line, on Linux and the three BSDs), for a
     module given as its .sym and .o. *)

  (* the module and the rest of a symbol "<module><marker><rest>" *)
  PROCEDURE SplitSymbol(symbol, marker: ARRAY OF CHAR; VAR module, rest: ARRAY OF CHAR): BOOLEAN;
    VAR i, j, k: INTEGER;
  BEGIN
    i := 0;
    WHILE symbol[i] # 0X DO
      j := 0;
      WHILE (marker[j] # 0X) & (symbol[i + j] = marker[j]) DO INC(j) END;
      IF (marker[j] = 0X) & (i > 0) THEN
        FOR k := 0 TO i - 1 DO module[k] := symbol[k] END;
        module[i] := 0X;
        k := 0;
        WHILE symbol[i + j + k] # 0X DO rest[k] := symbol[i + j + k]; INC(k) END;
        rest[k] := 0X;
        RETURN TRUE
      END;
      INC(i)
    END;
    RETURN FALSE
  END SplitSymbol;

  PROCEDURE AddObjectKey(VAR list: ObjectKey; module, rest: ARRAY OF CHAR);
    VAR k: ObjectKey; i, j: INTEGER;
  BEGIN
    NEW(k); COPY(module, k.module);
    (* rest is "<O2|OC>.<key>" *)
    k.model[0] := rest[0]; k.model[1] := rest[1]; k.model[2] := 0X;
    i := 3; j := 0;
    WHILE (rest[i] # 0X) & (j < keyLength) DO k.key[j] := rest[i]; INC(i); INC(j) END;
    k.key[j] := 0X;
    k.next := list; list := k
  END AddObjectKey;

  (* What the object at path says of itself, in info. FALSE, having said
     why, when nm cannot read it. *)
  PROCEDURE ReadObject*(path: ARRAY OF CHAR; VAR info: ObjectInfo): BOOLEAN;
    VAR
      scratch: ARRAY 64 OF CHAR; command: ARRAY 2 * pathLength OF CHAR; line: ARRAY lineLength OF CHAR;
      w0, w1, w2, w3: Name; module, rest: Name; f: Files.File; r: Files.Rider; i, status: INTEGER;
  BEGIN
    info.defined := NIL; info.imports := NIL; info.targetModule[0] := 0X; info.target[0] := 0X;
    info.usesCollector := FALSE;
    i := 0;
    WHILE path[i] # 0X DO
      IF path[i] = "'" THEN Err.String("poc: cannot read "); Err.String(path); Err.Ln; RETURN FALSE END;
      INC(i)
    END;
    ScratchFile("object", scratch);
    command := "nm -P '"; Append(command, path); Append(command, "' >"); Append(command, scratch);
    status := Platform.System(command);
    f := Files.Old(scratch);
    IF (status # 0) OR (f = NIL) THEN
      IF f # NIL THEN Files.Close(f) END;
      status := Platform.Unlink(scratch);
      Err.String("poc: nm cannot read "); Err.String(path); Err.Ln;
      RETURN FALSE
    END;
    Files.Set(r, f, 0);
    REPEAT
      Files.ReadLine(r, line);
      SplitLine(line, w0, w1, w2, w3);
      IF w1 = "U" THEN
        IF SplitSymbol(w0, ".-key.", module, rest) THEN AddObjectKey(info.imports, module, rest)
        ELSIF SplitSymbol(w0, ".", module, rest) & (module = "GarbageCollectedHeap") THEN
          info.usesCollector := TRUE
        END
      ELSIF w1[0] # 0X THEN
        IF SplitSymbol(w0, ".-key.", module, rest) THEN AddObjectKey(info.defined, module, rest)
        ELSIF SplitSymbol(w0, ".-target.", module, rest) THEN
          COPY(module, info.targetModule); COPY(rest, info.target)
        END
      END
    UNTIL r.eof;
    Files.Close(f);
    status := Platform.Unlink(scratch);
    RETURN TRUE
  END ReadObject;

  (* ---- A module's LLVM IR (Phase 12 step 2g) ----

     The .ll poc writes for a module says the same as its object, in the
     text: "@<Module>.-key.<O2|OC>.<key> = constant", "@<Module>.-target.
     <triple> = constant", "@<Import>.-key.<O2|OC>.<key> = external global",
     and a call of the collector names @GarbageCollectedHeap. on a line
     that is not its declaration. Read as text, for a module given as its
     .sym and .ll, since nm cannot read bitcode on OpenBSD or NetBSD. *)

  (* the line at r, its first LEN(line) - 1 characters *)
  PROCEDURE ReadTextLine(VAR r: Files.Rider; VAR line: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0; Files.Read(r, ch);
    WHILE ~r.eof & (ch # 0AX) DO
      IF i < LEN(line) - 1 THEN line[i] := ch; INC(i) END;
      Files.Read(r, ch)
    END;
    line[i] := 0X
  END ReadTextLine;

  (* whether s has pattern at position i *)
  PROCEDURE HasAt(s: ARRAY OF CHAR; i: INTEGER; pattern: ARRAY OF CHAR): BOOLEAN;
    VAR j: INTEGER;
  BEGIN
    j := 0;
    WHILE (pattern[j] # 0X) & (s[i + j] = pattern[j]) DO INC(j) END;
    RETURN pattern[j] = 0X
  END HasAt;

  (* whether s has pattern anywhere *)
  PROCEDURE Contains(s, pattern: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO
      IF HasAt(s, i, pattern) THEN RETURN TRUE END;
      INC(i)
    END;
    RETURN FALSE
  END Contains;

  (* What the IR at path says of itself, in info, as ReadObject. FALSE,
     having said why, when it cannot be read. *)
  PROCEDURE ReadIR*(path: ARRAY OF CHAR; VAR info: ObjectInfo): BOOLEAN;
    VAR
      f: Files.File; r: Files.Rider; line: ARRAY lineLength OF CHAR; symbol, module, rest: Name;
      i: INTEGER;
  BEGIN
    info.defined := NIL; info.imports := NIL; info.targetModule[0] := 0X; info.target[0] := 0X;
    info.usesCollector := FALSE;
    f := Files.Old(path);
    IF f = NIL THEN Err.String("poc: cannot read "); Err.String(path); Err.Ln; RETURN FALSE END;
    Files.Set(r, f, 0);
    REPEAT
      ReadTextLine(r, line);
      IF line[0] = "@" THEN
        i := 1;
        WHILE (line[i] # 0X) & (line[i] # " ") & (i - 1 < LEN(symbol) - 1) DO symbol[i - 1] := line[i]; INC(i) END;
        symbol[i - 1] := 0X;
        IF HasAt(line, i, " = constant ") THEN
          IF SplitSymbol(symbol, ".-key.", module, rest) THEN AddObjectKey(info.defined, module, rest)
          ELSIF SplitSymbol(symbol, ".-target.", module, rest) THEN
            COPY(module, info.targetModule); COPY(rest, info.target)
          END
        ELSIF HasAt(line, i, " = external global ") THEN
          IF SplitSymbol(symbol, ".-key.", module, rest) THEN AddObjectKey(info.imports, module, rest) END
        END
      END;
      IF ~HasAt(line, 0, "declare ") & Contains(line, "@GarbageCollectedHeap.") THEN
        info.usesCollector := TRUE
      END
    UNTIL r.eof;
    Files.Close(f);
    RETURN TRUE
  END ReadIR;

  (* whether the file at path is LLVM bitcode: "BC" C0 DE *)
  PROCEDURE IsBitcode*(path: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; r: Files.Rider; b: ARRAY 4 OF CHAR; i: INTEGER;
  BEGIN
    f := Files.Old(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(r, f, 0);
    FOR i := 0 TO 3 DO Files.Read(r, b[i]) END;
    Files.Close(f);
    RETURN ~r.eof & (b[0] = "B") & (b[1] = "C") & (b[2] = 0C0X) & (b[3] = 0DEX)
  END IsBitcode;

  (* ---- The libraries a program links ---- *)

  PROCEDURE Use*(lib: Library);
  BEGIN
    lib.used := TRUE
  END Use;

  PROCEDURE ^ Visit(lib: Library; VAR ok: BOOLEAN);

  (* each library lib needs, used and visited *)
  PROCEDURE VisitNeeds(lib: Library; VAR ok: BOOLEAN);
    VAR n: Need; needed: Library;
  BEGIN
    n := lib.needs;
    WHILE ok & (n # NIL) DO
      needed := FindLibrary(n.name);
      IF needed = NIL THEN
        Err.String("poc: library "); Err.String(lib.name); Err.String(" needs library "); Err.String(n.name);
        Err.String(", which is not on the library path"); Err.Ln;
        ok := FALSE
      ELSE
        needed.used := TRUE; Visit(needed, ok)
      END;
      n := n.next
    END
  END VisitNeeds;

  (* depth first; lib goes to the front of linkOrder after everything it
     needs, so each library comes before those it needs *)
  PROCEDURE Visit(lib: Library; VAR ok: BOOLEAN);
    VAR l: Library;
  BEGIN
    l := linkOrder;
    WHILE (l # NIL) & (l # lib) DO l := l.linkNext END;
    IF l # NIL THEN RETURN END;
    VisitNeeds(lib, ok);
    lib.linkNext := linkOrder; linkOrder := lib
  END Visit;

  (* The libraries a program links: every one Use named and every one they
     need, in linkOrder. Before that, what a link cannot be trusted with is
     refused, on Err: a library that is not on the path; a module that two of
     the libraries both have (a process must not hold two collectors); a
     library compiled against an interface of a module that differs from the
     one the library now providing it has (their keys). FALSE after any of
     these. *)
  PROCEDURE ComputeLinkOrder*(): BOOLEAN;
    VAR lib, owner: Library; m, provided: Member; i: ImportKey; ok: BOOLEAN;
  BEGIN
    ok := TRUE; linkOrder := NIL;
    lib := loaded;
    WHILE ok & (lib # NIL) DO
      IF lib.used THEN Visit(lib, ok) END;
      lib := lib.next
    END;
    lib := linkOrder;
    WHILE ok & (lib # NIL) DO
      m := lib.modules;
      WHILE ok & (m # NIL) DO
        owner := FindModule(m.name);
        IF owner # lib THEN
          Err.String("poc: module "); Err.String(m.name); Err.String(" is in library "); Err.String(lib.name);
          Err.String(" ("); Err.String(lib.dir); Err.String(")");
          IF owner # NIL THEN
            Err.String(" and in library "); Err.String(owner.name);
            Err.String(" ("); Err.String(owner.dir); Err.String(")")
          END;
          Err.String("; a program can link only one of them"); Err.Ln;
          ok := FALSE
        END;
        i := m.imports;
        WHILE ok & (i # NIL) DO
          owner := FindModule(i.name);
          IF owner = NIL THEN
            Err.String("poc: module "); Err.String(m.name); Err.String(" of library "); Err.String(lib.name);
            Err.String(" imports "); Err.String(i.name); Err.String(", which no library on the library path has");
            Err.Ln;
            ok := FALSE
          ELSE
            provided := FindMember(owner, i.name);
            IF (provided = NIL) OR (provided.key # i.key) THEN
              Err.String("poc: library "); Err.String(lib.name); Err.String(" was compiled against ");
              Err.String(i.name); Err.String(" "); Err.String(i.key); Err.String(", but library ");
              Err.String(owner.name); Err.String(" ("); Err.String(owner.dir); Err.String(") has ");
              Err.String(i.name); Err.String(" ");
              IF provided # NIL THEN Err.String(provided.key) END;
              Err.String("; rebuild "); Err.String(lib.name); Err.Ln;
              ok := FALSE
            END
          END;
          i := i.next
        END;
        m := m.next
      END;
      lib := lib.linkNext
    END;
    RETURN ok
  END ComputeLinkOrder;

BEGIN
  pathHead := NIL; pathTail := NIL; loaded := NIL; checked := NIL; linkOrder := NIL;
  triple[0] := 0X; model[0] := 0X; excluded[0] := 0X; errors := 0
END Libraries.
