# File-name operations: what other languages do, and a proposal for Directories

Written 2026-10-10, after Phase 16 step 4 moved `pathSeparator`, `MakePath`,
`IsDirectory` and `MakeDirectory` into a module of their own, `Directories`
(7e25bbb). It surveys the file-name procedures of Ada, OCaml, Python, Common
Lisp, CHICKEN Scheme, Emacs 18.59 (which has VMS code) and Emacs 31.1. It says
what each source *does*, read from the local source and, where marked, run.
It ends with the places in poc's own source that still treat names as Unix
names, and a proposal. Nothing here changes poc.

## 1. Sources

| Language | Local source read | Run |
|---|---|---|
| Ada 2012 | GNAT `libgnat/a-direct.ads/.adb` (`Ada.Directories`), `a-dhfina.ads/.adb` (`Ada.Directories.Hierarchical_File_Names`), `a-dirval*.adb`, `s-os_lib.ads`, gcc tree 8564ce94d6a (2026-02-09); GNAT's removed VMS port `a-dirval-vms.adb`, `osint.ads`, `g-dirope.ads` at f9648959b41^ (VMS support removed 2014-07-31) | GNAT 16.2.1 |
| OCaml | `ocaml/stdlib/filename.ml/.mli` (f28bfbcb23, 2024-12-20) | `ocaml` (Fedora) |
| Python | `/usr/lib64/python3.14/{posixpath,ntpath,genericpath}.py`, `pathlib/__init__.py` | Python 3.14 |
| Common Lisp | the standard's text (dpANS, as GCL 2.7.1 ships it: `info/chap-19.texi` "Filenames", `info/chap-20.texi` "Files"; the CLHS is the same text); ECL 24.5.10 `src/c/pathname.d` | SBCL 2.6.8 |
| CHICKEN | `chicken-5.4.0/pathname.scm` (`chicken.pathname`) | `csi` 5.4.0 |
| Emacs 18.59 | `src/fileio.c`, `src/sysdep.c` (`sys_translate_vms`, `sys_translate_unix`), `lisp/files.el` | - |
| Emacs 31.1 | `src/fileio.c`, `lisp/files.el` | Emacs 30.2 (the installed one; the 31.1 functions below have the same code) |

## 2. The models

Each language has its own idea of what a file name is. These ideas decide
what VMS support costs.

1. **A string with one separator character.** OCaml, Python's `os.path`,
   CHICKEN and GNAT's Ada work on strings. A small table of facts
   describes each system: the separator(s), the current and parent names, and
   how a name starts at a root. OCaml's `Filename` is the cleanest example:
   one functor-like `SYSDEPS` signature with `Unix`, `Win32` and `Cygwin`
   instances, and the generic `basename`/`dirname`/`extension` written once
   over an `is_dir_sep` predicate. Win32's `is_dir_sep` also counts `:`, so
   `C:foo` splits after the colon.
2. **A record of components.** Common Lisp's pathname is
   *host, device, directory, name, type, version*. The directory is a list:
   `(:absolute "a" "b")`, `(:relative :up "lib")`. A namestring is parsed into
   that record and printed back from it. `merge-pathnames` fills missing
   components from defaults. The standard's own examples use VMS, TOPS-20 and
   Symbolics LMFS namestrings. VMS's `NODE::DEV:[DIR]NAME.TYPE;VERSION` maps
   onto the six components one for one, and `pathname-version` exists for
   systems like it. SBCL on Unix reports the version as `NIL`. Section 3.5
   covers chapter 19 in detail.
3. **Strings, with "directory name" distinct from "directory file name".**
   Emacs keeps strings, but separates two spellings of a directory:
   `file-name-as-directory` gives the name to put a file name after
   (`/a/b/`, VMS `[A.B]`), and `directory-file-name` gives the name of the file
   that *is* the directory (`/a/b`, VMS `[A]B.DIR.1`). On Unix the two differ
   by a slash. On VMS they differ in syntax. The distinction survived into
   Emacs 31.1, where `directory-name-p` tests for it, long after the VMS code
   it was invented for was removed. (VMS removal was announced in Emacs 22's
   NEWS: "Support for VMS will be removed.")
4. **Pure syntax objects, separate from the file system.** Python's `pathlib`
   has `PurePosixPath` and `PureWindowsPath`, which do every name operation
   for that syntax on *any* host, and `Path`, which adds the I/O for the host.
   CHICKEN's `normalize-pathname` takes an optional platform argument
   (`'windows` or `'unix`) for the same reason. This separation is what a
   cross-compiler needs. poc on Linux writes a `.COM` procedure full of VMS
   names.

## 3. The operations compared

"-" means the language has no such operation. Names are given as the language
spells them.

| Operation | Ada | OCaml | Python | Common Lisp | CHICKEN | Emacs 18.59 | Emacs 31.1 |
|---|---|---|---|---|---|---|---|
| Join a directory and a name | `Compose(Dir, Name, Ext)` | `concat` | `join(a, *p)` | `merge-pathnames`, `make-pathname` | `make-pathname dirs file ext` | (`concat` after `file-name-as-directory`) | `file-name-concat dir &rest` |
| Directory part | `Containing_Directory` | `dirname` | `dirname`, `split` | `directory-namestring`, `pathname-directory` | `pathname-directory` | `file-name-directory` | same |
| Name without directory | `Simple_Name` | `basename` | `basename` | `file-namestring` | `pathname-file` + ext | `file-name-nondirectory` | same |
| Extension | `Extension` | `extension` | `splitext` | `pathname-type` | `pathname-extension` | - (Lisp: none) | `file-name-extension` |
| Name without extension | `Base_Name` | `remove_extension`, `chop_extension` | `splitext` | `pathname-name` | `pathname-strip-extension` | - | `file-name-sans-extension`, `file-name-base` |
| Replace the extension | `Compose(.., Ext)` | - | `PurePath.with_suffix` | `make-pathname :type .. :defaults` | `pathname-replace-extension` | - | `file-name-with-extension` |
| Test a suffix | - | `check_suffix` (case-blind on Win32) | - | - | - | - | - |
| Version | - | - | - | `pathname-version` | - | `file-name-sans-versions` (VMS `;n` and `.n`) | `file-name-sans-versions` (backup `~` only) |
| Absolute? | `HFN.Is_Full_Name`, `Is_Relative_Name` | `is_relative`, `is_implicit` | `isabs` | `(car (pathname-directory p))` | `absolute-pathname?` | `file-name-absolute-p` | same |
| Root? | `HFN.Is_Root_Directory_Name` | - | `splitroot` | - | `decompose-directory` | - | - |
| Drive / device | (only stripped by `Simple_Name`) | (Win32 `drive_and_path`) | `splitdrive`, `splitroot` | `pathname-device`, `pathname-host` | `decompose-directory` origin | (VMS `dev:` scanned in `expand-file-name`) | (DOS_NT `c:`) |
| As directory / as file | - | - | - | (`:directory` vs `:name`) | - | `file-name-as-directory`, `directory-file-name` | same, plus `directory-name-p` |
| Parent | `Containing_Directory` | `dirname` | `dirname`, `PurePath.parent` | (`:up`/`:back`) | - | (`[-]`) | `file-name-parent-directory` |
| First / rest of a relative name | `HFN.Initial_Directory`, `HFN.Relative_Name` | - | `PurePath.parts` | (directory list) | `decompose-directory` | - | `file-name-split` |
| Lexical normalization | - | - | `normpath` | (`:back` removal in merge) | `normalize-pathname [platform]` | inside `expand-file-name` | inside `expand-file-name` |
| Absolute, canonical | `Full_Name`; `OS_Lib.Normalize_Pathname` | - | `abspath`, `realpath` | `truename` | - | `expand-file-name` | `expand-file-name`, `file-truename` |
| Relative to a directory | - | - | `relpath` | `enough-namestring` | - | - | `file-relative-name` |
| Fill missing parts from defaults | - | - | (`join`'s drive rule) | `merge-pathnames`, `*default-pathname-defaults*` | - | (`expand-file-name`) | (`expand-file-name`) |
| Parse part of a string | - | - | - | `parse-namestring` `:start :end :junk-allowed` | - | - | - |
| Make the containing directories | (`Create_Path`) | - | (`os.makedirs`) | `ensure-directories-exist` | (`create-directory` `parents?`) | - | `make-directory` `parents` |
| Case rule | `Name_Case_Equivalence` | - | `normcase` | (`:case :common`) | - | (VMS: `Fupcase` of every name) | `file-name-case-insensitive-p` |
| Valid name? | (`Validity.Is_Valid_Simple_Name`, internal) | - | `ntpath.isreserved` | (parse error) | - | - | - |
| List separator | `OS_Lib.Path_Separator` | - | `os.pathsep` | - | - | - | `path-separator` |
| Host/Unix syntax translation | GNAT `To_Canonical_File_Spec`, `To_Host_File_Spec` (VMS) | - | - | logical pathnames, `translate-logical-pathname` | - | `sys_translate_unix`, `sys_translate_vms` | - |

### 3.1 Edge cases, run

The same five names, run on each implementation:

| Name | Ada `Simple_Name` / `Extension` / `Base_Name` | OCaml `dirname` / `basename` / `extension` | Python `split` / `splitext` | SBCL dir / name / type | CHICKEN `decompose-pathname` | Emacs dir / nondir / ext |
|---|---|---|---|---|---|---|
| `a/b/` | `b` / `""` / `b` | `a` / `b` / `""` | `('a/b','')` / `('a/b/','')` | `(:relative "a" "b")` / NIL / NIL | `"a/b"` `#f` `#f` | `a/b/` / `""` / nil |
| `a.tar.gz` | `a.tar.gz` / `gz` / `a.tar` | `.` / `a.tar.gz` / `.gz` | `('', 'a.tar.gz')` / `('a.tar','.gz')` | NIL / `a.tar` / `gz` | `#f "a.tar" "gz"` | nil / `a.tar.gz` / `gz` |
| `.bashrc` | `.bashrc` / **`bashrc`** / **`""`** | `.` / `.bashrc` / `""` | `('.bashrc','')` | NIL / `.bashrc` / NIL | `#f ".bashrc" #f` | nil / `.bashrc` / nil |
| `foo.` | `foo.` / `""` / `foo` | `.` / `foo.` / `.` | `('foo','.')` | NIL / `foo` / `""` | `#f "foo." #f` | nil / `foo.` / `""` |
| `/` | `/` / `""` / `/` | `/` / `/` / `""` | `('/','')` | `(:absolute)` / NIL / NIL | `"/" #f #f` | `/` / `""` / nil |

What the table shows:

- **The leading dot.** Everyone except GNAT agrees that `.bashrc` has no
  extension. GNAT's `Base_Name(".bashrc")` is `""` and its `Extension` is
  `bashrc`. Its `Base_Name` comment even says "If the first dot is the first
  character of the file name, the base name is the empty string."
- **Whether the extension includes the dot.** OCaml and Python include it
  (`.gz`), so `root ^ ext = name` always holds. Ada, Common Lisp, CHICKEN and
  Emacs leave it out (`gz`), and Emacs has a `PERIOD` argument to put it back.
  `foo.` separates them. OCaml and Python give `.`. Emacs, Ada and SBCL give `""`,
  which Emacs and SBCL keep apart from no extension (nil). Ada can't tell the
  two apart, and CHICKEN gives no extension. On VMS this
  case is ordinary: every file has a type, perhaps empty (`FOO.`), and RMS
  writes `FOO.;1`.
- **A trailing separator.** Emacs treats `a/b/` as a directory name and
  gives `a/b/` and `""`. OCaml, Ada and CHICKEN ignore the trailing slash and
  give `b`. Python splits after it. Emacs's reading is the only one that
  carries over to VMS, where `[A.B]` *is* the trailing-separator form and has
  no other spelling.
- **A GNAT bug.** `Hierarchical_File_Names.Compose("a", "b", "txt")` gives
  `a/btxt`, with no dot. `Ada.Directories.Compose` with the same arguments
  gives `a/b.txt` (both run). GNAT's body simply concatenates
  `Separated_Dir & Relative_Name & Extension`.
- **`HFN.Is_Full_Name` is not lexical in GNAT.** It compares `Full_Name(Name)`
  with `Name`, so `/a/../b` is not "full" while `/a/b` is (run). Its other
  predicates are lexical.

### 3.2 Windows, where it differs

Python's `ntpath` has the most complete Windows rules, and the others are
subsets of them:

- `\` and `/` both separate. `\` is written.
- `splitroot` returns drive, root and tail, with drive + root + tail = the
  name: `C:\x` is `('C:', '\', 'x')`, `C:x` is `('C:', '', 'x')` (a drive with
  no root: relative to that drive's current directory), and `\x` is
  `('', '\', 'x')` (a root with no drive). `\\srv\share\d\f` is
  `('\\srv\share', '\', 'd\f')`, and `\\?\UNC\` and `\\.\device` are drives
  too.
- So "absolute" is three-valued. `isabs("C:x")` and `isabs("\x")` are both
  False (run). OCaml's `is_relative "C:x"` is false, so OCaml calls it
  absolute. GNAT's `Is_Root_Directory_Name` accepts `C:` as a root.
- `join("C:\a", "D:b")` is `D:b`: a component with another drive discards
  everything before it (run).
- Names compare without regard to case (`normcase` lowercases).
  `isreserved` refuses `CON`, `NUL`, `COM1` and the like, names ending in a
  dot or space, and `<>:"|?*`. OCaml's Win32 `check_suffix` ignores case.
- The list separator is `;`.

Emacs 31.1 handles `c:` only at the start (`file_name_directory`'s DOS_NT
branch) and expands a bare `c:` to that drive's current directory with
`getdefdir`, which is a file-system operation rather than a syntax one.

### 3.3 VMS: Emacs 18.59

Emacs 18.59 has real VMS code: about 96 `VMS` conditionals in `fileio.c`.
What it does:

- **Directory and name parts.** `file-name-directory` and
  `file-name-nondirectory` scan back to the last `/`, or on VMS the last
  `:`, `]` or `>`. So `DEV:[A.B]F.C;3` is `DEV:[A.B]` and `F.C;3`.
  `DEV:F.C` is `DEV:` and `F.C`. The directory part keeps its terminator, so
  directory + name = the whole name. This is the rule poc's
  `rtl/vax/Directories.MakePath` already uses.
- **`file-name-as-directory`.** It turns a directory *file* into a directory
  *name*: `X.DIR` gives `[.X]`, `DEV:X.DIR` gives `DEV:[X]`, and
  `DEV:[X]Y.DIR` gives `DEV:[X.Y]`. It accepts `.DIR`, `.DIR.1` and
  `.DIR;1` in either case, and "blindly" drops the type. A name already
  ending in `:`, `]` or `>` is returned as it is.
- **`directory-file-name`** goes the other way: `[X.Y.Z]` gives
  `[X.Y]Z.DIR.1`, and `[X]` gives `[000000]X.DIR.1`, the master file
  directory. It first calls `SYS$PARSE` with `NAM$M_SYNCHK` (syntax only, no
  disk access) so that RMS resolves `[--]` and the like. A `DEV:` that is a
  logical name is translated. A rooted logical name (`DEV:[000000]`, whose
  translation ends in `.]`) is translated and the procedure recurses.
- **`expand-file-name` on VMS** uppercases the name first ("Filenames on VMS
  are always upper case"). It treats any `:` as making a name absolute and
  merges `dev1:[dir]dev2:` down to `dev2:`. It collapses `[A.B.-]` to `[A]`
  and `[A][.B]` to `[A.B]`, and `[A][B]` to `[B]` (the brackets compared by
  `p[0] == p[1] + 2`, since `]`/`[` and `>`/`<` are two apart in ASCII).
  Before VMS 4.4, `-` in a file name became `_`.
- **`file-name-absolute-p` on VMS:** any `:` or `<`, or a `[` not followed
  by `.` or `-`. So `[.X]` and `[-]` are relative and `[X]` is absolute. The
  source itself comments "This criterion is probably wrong for `<`."
- **Versions.** `file-name-sans-versions` strips `;n` or, after the
  directory, a second `.n`: `FOO.BAR.3` is version 3. VMS accepts either
  separator.
- **Mixed syntax.** `sys_translate_unix` turns `/dev/a/b/f.c` into
  `dev:[a.b]f.c`, `./` into `[` or `.`, and `../` into `-`.
  `sys_translate_vms` goes the other way. `expand-file-name` calls the first
  whenever a name contains `/`, so a VMS user could type Unix names.

### 3.4 VMS: GNAT

GNAT's VMS port (removed in 2014) went the other way. `Ada.Directories` and
`GNAT.Directory_Operations` handled **only Unix-syntax names**
(`g-dirope.ads`: "On OpenVMS, only Unix style path names are supported, not
VMS style"). It relied on the DEC C RTL to translate them, and kept
`osint.ads`'s `To_Canonical_File_Spec`/`To_Host_File_Spec` family
(`SYS$DEVICE:[DIR]FILE.EXT;69` to and from `/sys$device/dir/file.ext.69`) for
the compiler's own use. `a-dirval-vms.adb` enforced ODS-2 limits on those
Unix-syntax names: at most 39 characters before and after a single `.`,
letters, digits, `_`, `$`, `-` and `.` only, at most 1024 characters in all,
and `Is_Path_Name_Case_Sensitive` returning False.

poc can't take that route. The decision for Phase 16 is the base kit only,
with no VAXCRTL, so nothing would translate `/` names for poc's RMS calls.
Emacs 18's route, native VMS syntax with an optional Unix-to-VMS translation,
is the one that fits.

### 3.5 Common Lisp: the standard's chapter 19

Chapter 19 is the only standard surveyed here whose model was meant from
the start for systems unlike Unix, VMS among them. Quotations are from the
dpANS text in GCL's `info/chap-19.texi` and `chap-20.texi`.

- **Two representations** (19.1). A *namestring* is the system's own string,
  whose syntax "involves the use of implementation-defined conventions".
  A *pathname* is a structured object with six components. Only *logical
  pathname* namestrings have syntax the standard defines. So a conforming
  program "must never unconditionally use a literal namestring" for a
  physical file, though it "can, if it is careful, successfully manipulate
  user-supplied data" containing one. That is poc's situation exactly: the
  names come from the command line, `POC_IMPORT_PATH` and the libraries'
  files, and poc only takes them apart and puts them together.
- **Six components** (19.2.1): *host* ("the name of the file system on which
  the file resides"), *device* ("the name of a logical or physical device
  containing files"), *directory*, *name*, *type* and *version*. The
  standard's examples spell VMS names with them. `(make-pathname :host
  "KATHY" :directory "CHAPMAN" :name "LOGIN" :type "COM")` prints as
  `KATHY::[CHAPMAN]LOGIN.COM`, so the DECnet node is the host. An
  implementation "with access to one or more VMS file systems" prints a
  pathname given no device as `SYS$DISK:[PUBLIC.GAMES]CHESS.DB`, so the
  device is filled from the process's default. `merge-pathnames`'s example
  is a TOPS-20 name, `CMUC::PS:<LISPIO>FORMAT.FASL.0`: node, device, angle
  brackets and a `.n` version. VMS accepts the same forms.
- **Three kinds of empty** (19.2.2.2). `NIL` means *unfilled*: merging
  replaces it. `:unspecific` means *absent*: it doesn't print, and merging
  leaves it alone. `""` is a value that is present but empty: SBCL's
  `(pathname-type "foo.")` is `""` and `(pathname-type "foo")` is `NIL`
  (run). A VMS name needs all three, since `FOO.` and `FOO` are different
  files to the program even though RMS defaults the second.
- **The directory is a list** (19.2.2.4.3): `(:absolute "A" "B")` or
  `(:relative "A")`, with `:wild`, `:wild-inferiors`, `:up` and `:back`.
  `(:relative)` means the same as `NIL`. The standard separates `:back`
  ("syntactic": depends only on the pathname) from `:up` ("semantic":
  depends on the file system, which can differ "via symbolic links"). This
  matters for a parent-directory operation. VMS's `[A.B.-]` is resolved by
  RMS from the text, so it is `:back`, and a lexical parent is exact. Unix's
  `a/b/..` is resolved by the kernel, so it is `:up`, and a lexical parent
  can be wrong.
- **Case** (19.2.2.1.2). Accessors take `:case :local` (the system's own
  case) or `:case :common` (uppercase means the system's customary case,
  lowercase means the opposite). Under `:common`, `"LOGIN"` is `LOGIN` on
  VMS and `login` on Unix. The aim is portable code that writes one name
  for both. poc's module names are mixed case and RMS uppercases them, so
  `:common` doesn't apply, but it is the standard's answer to the problem
  `SameName` addresses below.
- **Merging** (19.2.3, `merge-pathnames`). It fills each `NIL` component
  from the defaults. A `:relative` directory is appended to the defaults'
  directory, then "a string or `:wild` immediately followed by `:back`"
  pairs are removed. The device has its own rule: "If pathname explicitly
  specifies a host and not a device, and if the host component of
  default-pathname matches the host component of pathname, then the device
  is taken from the default-pathname; otherwise the device will be the
  default file device for that host." The version comes from the defaults
  only when the name doesn't. This is how RMS applies a default file
  specification (see 3.6), and it is the operation poc's callers need when
  a name may or may not bring its own device or directory.
- **`parse-namestring`** takes `:start`, `:end` and `:junk-allowed`, and
  returns the index where parsing stopped as a second value. That lets a
  caller parse names from inside a longer string, such as a list of
  directories.
- **`enough-namestring`** returns "the shortest reasonable string" `s` such
  that `(merge-pathnames s defaults)` names the same file. This is a relative
  name defined by merging rather than by prefixes, so it covers devices too.
- **Logical pathnames** (19.3) have the standard's one fixed syntax:
  `HOST:DIR;DIR;NAME.TYPE.VERSION`, uppercase words of letters, digits and
  hyphens, with a device that is always `:unspecific`. A table
  (`logical-pathname-translations`) maps them to physical pathnames. VMS
  logical names do the same job (`POC$ROOT:[SRC]`), but VMS translates them,
  not the program.
- **Chapter 20** has the file-system operations that go with the names:
  `probe-file` and `truename` (the real name of an existing file),
  `ensure-directories-exist` (which takes a *file's* name and makes the
  directories containing it), and `directory`.
- **The examples have slips.** `(pathname-directory (parse-namestring
  "[FOO.*.BAR]BAZ.LSP"))` is shown as `(:ABSOLUTE "FOO" "BAR")`, with the
  `:WILD` missing. Two identical `:case :local` calls are shown with
  different results. The Unix examples give `:UNSPECIFIC` for `foo`'s type
  where SBCL gives `NIL`. As the text itself says, the examples are
  implementation-dependent illustrations.

### 3.5.1 Common Lisp libraries: UIOP and cl-fad

The standard leaves namestring syntax to implementations, so portability
libraries grew up around it. Two are local: UIOP 3.3.6 (part of ASDF; read
in `~/.qlot/.../uiop-3.3.6/{pathname,filesystem,os}.lisp`, run as SBCL's
bundled ASDF 3.3.1) and cl-fad (`cl-fad-20220220-git/fad.lisp`).
pathname-utils, osicat, IOLib, file-attributes and trivial-file-size are not
installed here and were not checked.

- **UIOP's names** (all found in the source): `ensure-directory-pathname`,
  `pathname-parent-directory-pathname`, `subpathname`, `subpathp`,
  `enough-pathname`, `merge-pathnames*`, `pathname-root`, `split-name-type`,
  `parse-unix-namestring`, `pathname-equal`, `absolute-pathname-p` in
  `pathname.lisp`; `native-namestring`, `parse-native-namestring`,
  `directory-files`, `subdirectories`, `directory-exists-p`,
  `file-exists-p`, `ensure-all-directories-exist`, `delete-directory-tree`,
  `with-current-directory` in `filesystem.lisp`; `getcwd` in `os.lisp`.
- **cl-fad's names**: `pathname-as-directory`, `pathname-as-file`,
  `directory-pathname-p`, `list-directory`, `walk-directory`,
  `directory-exists-p`, `delete-directory-and-files`,
  `merge-pathnames-as-directory`, `pathname-parent-directory`, `copy-file`.
- **As directory / as file.** `ensure-directory-pathname` and
  `pathname-as-directory` move the name and type onto the end of the
  directory list. `pathname-as-file` moves the last directory back and
  re-parses it as name and type. This is Emacs's pair again, but Unix-shaped.
  On VMS, `[A]B.DIR;1` would become directory `(... "B.DIR")`, where Emacs
  18 drops the `.DIR` and gives `[A.B]`.
- **`merge-pathnames*` changes the standard's device rule on purpose.** Its
  docstring: "if the SPECIFIED pathname does not have an absolute
  directory, then the HOST and DEVICE both come from the DEFAULTS, whereas
  if the SPECIFIED pathname does have an absolute directory, then the HOST
  and DEVICE both come from the SPECIFIED pathname. This is what users want
  on a modern Unix or Windows operating system." Run with defaults
  `D:\x\old.t`:

  | Specified | standard `merge-pathnames` | UIOP `merge-pathnames*` | Windows means | VMS means (`D:[X]` defaults) |
  |---|---|---|---|---|
  | `C:a\f` (device, relative directory) | device C, `\x\a\` | device **D**, `\x\a\` | C:'s current directory + `a\` | `C:[`*default*`.A]F` (3.6.1, 1d) |
  | `\a\f` (absolute directory, no device) | device D, `\a\` | device **NIL**, `\a\` | the current drive's `\a\` | `D:[A]F` |
  | `C:f` (device only) | device C, `\x\` | device **D**, `\x\` | C:'s current directory | `C:[X]F` |

  The standard's rule gives the VMS answer in rows 2 and 3: field by
  field, as RMS fills a name (checked on the guest, 3.6.1: 1a, 1e). In row 1
  RMS takes the relative directory from the process's default directory,
  not from the defaults given (1d), which neither rule does. UIOP's rule loses the device the name gave in
  rows 1 and 3, which is wrong on Windows as well. Neither rule can give
  the Windows answer for rows 1 and 3, because that answer depends on
  C:'s current directory, which only the system knows.
- **`inter-directory-separator`** is `:` on Unix and `;` otherwise. UIOP's
  `os-cond` knows Unix, Windows, macOS and Genera, but not VMS. No VMS
  appears in UIOP's `os.lisp`.
- **SBCL's Windows parser** (`src/code/win32-pathname.lisp`, 2.4.3) stores
  `C:` as device `"C"`, and `//host/share` as device `:UNC` with the host
  and share as the first *directory* components, not as the host. Its own
  `FIXME` notes that using `\` as both escape and separator is
  "fundamental brokenness" (lp#673625).

The libraries' lesson for poc: the components were right, but each
library's rules for combining them were written for one family of systems.
poc's `Merge` has to choose its rule by syntax.

### 3.6 Devices

Unix names have no device. Windows and VMS names do, and poc's proposal
needs to handle them more fully than "a prefix".

**What a device is:**

| | Unix | Windows | VMS |
|---|---|---|---|
| In a name | none (`/dev/...` are files; mounts are invisible) | drive `C:`; share `\\server\share`; `\\.\COM1`, `\\?\` | `DUA1:`, `_DUA1:` (a leading `_` means physical, not translated), `$1$DUA1:` (allocation class); `NODE::` before it |
| Names standing for one | - | `SUBST`, mapped drives | logical names: `SYS$LOGIN:`, `SYS$DISK:`, `POC$ROOT:`; a concealed rooted one, `DISK$USER:[A.]`, makes `[A.]` its `[000000]` |
| Special devices | `/dev/null`, `/dev/tty` | `NUL`, `CON`, `PRN`, `AUX`, `COM1`-`9`, `LPT1`-`9` (reserved in every directory: `ntpath.isreserved`) | `NLA0:` (null), `TT:`, `SYS$INPUT:`, `SYS$OUTPUT:`, `SYS$ERROR:`, `SYS$COMMAND:` |
| Default | - | each drive has its own current directory | one default device (`SYS$DISK`) and one default directory (`SET DEFAULT`) |
| Root | `/` | `C:\`, `\\server\share\` | `DEV:[000000]` |

OCaml's `Filename.null` is `/dev/null` on Unix and `NUL` on Win32.

**"Absolute" has two parts.** Whether a name gives a device and whether its
directory starts at a root are separate questions, as Common Lisp's device
component and `:absolute`/`:relative` directory make them:

| Device | Root | Unix | Windows | VMS | What fills the rest |
|---|---|---|---|---|---|
| yes | yes | - | `C:\a\f` | `DEV:[A]F` | nothing |
| yes | no | - | `C:a\f` | `DEV:F`, `DEV:[.A]F` | that drive's current directory / the default directory |
| no | yes | `/a/f` | `\a\f` | `[A]F` | the current drive / `SYS$DISK` |
| no | no | `a/f` | `a\f` | `F`, `[.A]F`, `[-]F` | everything |

The languages disagree about the middle rows:
- Emacs 18 calls both middle rows absolute on VMS ("any `:`", or a `[` not
  followed by `.` or `-`), so it treats `DEV:[.A]` as absolute. Its test also
  makes `[]` absolute, though `[]` is the default directory.
- Python's `isabs` calls `C:a` and `\a` not absolute.
- OCaml's `is_relative "C:a"` is false, so OCaml calls `C:a` absolute.
- Emacs 31 resolves `c:` with `getdefdir`, that drive's current directory,
  which is a file-system call.
- GNAT's `Is_Root_Directory_Name` accepts `C:` alone as a root.

Only the two-part answer is right on both systems.

**A name's device replaces the directory's.** Python's
`join("C:\a", "D:b")` is `D:b` (run). Emacs 18's `expand-file-name` turns
`dev1:[dir]dev2:` into `dev2:`, though RMS itself refuses such a name
(3.6.1, 5g). `merge-pathnames` takes every component the
name gives and fills only the rest. poc's `MakePath` just concatenates, so
`MakePath("DUA1:[A]", "SYS$LOGIN:X.COM")` would give
`DUA1:[A]SYS$LOGIN:X.COM`. No caller in `src/` passes such a name today,
since they all pass module names, but a general procedure must not do this.

**Joining to a bare device needs no separator, and on Windows a separator
changes the meaning.** `C:` + `x` is `C:x` (relative to C:'s current
directory), and `C:\x` is a different file. Python's `join("C:", "x")`
gives `C:x`, and the proposal's `MakePath` rule (no `\` after a drive's
`:`) keeps this. VMS `DEV:` + `F` is `DEV:F`, as it is today.

**How RMS fills a VMS name from defaults.** RMS fills a name field by field
from a default file specification, then a related file specification (no
version from that one), then the process defaults (3.6.1, item 9). This is
`merge-pathnames` with VMS's components, with one exception: a *relative*
directory. 3.6.1 has the guest's answers. In short:
- `DUA0:F.C` keeps `DUA0:` and takes the default spec's directory, giving
  `DUA0:[X]F.C` (1a). On Windows that directory would come from the drive
  itself.
- `[.A]` and `[-]` are relative to the process's default directory (`SET
  DEFAULT`), even when the default spec has an absolute directory of its
  own. `[.A]F.C` with `DUA1:[X.Y]` gives `DUA1:[USERS.POC.A]F.C` (3a, 3b,
  3j, 1d).
- A logical name in the device field is translated. If its translation
  brings a directory, that directory is used (2a). If it is a device only,
  the default directory is used (2c). Such a logical followed by a relative
  directory, `POCTEST_DIR:[.A]`, is refused (2f).
- A name with a node takes no local defaults: `NODE::F.C` stays `NODE::F.C`
  (5b).

**Devices can't be compared or resolved from the text.** `SYS$LOGIN:` and
`DUA1:[USERS.POC]` can be the same directory, and so can a `SUBST` drive
and its target. Only the system can say:
- VMS: `$PARSE` puts the translated name in the expanded string, though
  concealed devices stay concealed unless `NAM$M_NOCONCEAL` is set. Emacs 18
  translated device logical names itself with `egetenv`, and recursed for a
  rooted one.
- Windows: `GetFullPathName`, which is what Python's `abspath` calls.
- Unix: `realpath`.

So `SameName` can only be lexical, and `FullName` belongs in `Directories`.

**Limits.** Checked on the guest (3.6.1):
- ODS-2 takes 8 directory levels and refuses a 9th (6a, 6b).
- A name and a type each take 39 characters and refuse a 40th (6c-6e).
- `-` is accepted in names and directories (6f, 6g). `,` and a second `.`
  are refused (6j, 6h). A space is silently removed: `a b.c` becomes
  `AB.C` (6i). So poc mustn't rely on RMS to refuse one.
- `[--]` from a two-level default gives `[000000]`, and `[---]` is refused
  (3d, 3e).

Not borne out: a 7-character node name parses (5c), so the DECnet Phase IV
limit of 6, if it is one, isn't a limit of the syntax. Not checked: the
length of logical names, and the characters allowed in device and logical
names.

### 3.6.1 Checked on the guest: `F$PARSE` (step 0)

Run 2026-10-10 on the SIMH VAX (VMS V5.5-2H4) with `tools/vax-do`, by a
procedure that calls `F$PARSE(spec, default)` (full parse) or
`F$PARSE(spec, default,,, "SYNTAX_ONLY")` for each case. Its text is in
Appendix A. `F$PARSE` calls RMS's `$PARSE`, so it applies the same defaults
`Files` will get. The process's state for the run:
- default directory `DUA1:[USERS.POC]`
- `SYS$DISK` = `DUA1:` in the process table
- `SYS$LOGIN` = `DUA1:[USERS.POC]`
- disks `DUA0:` (system) and `DUA1:` (user) mounted
- process logical names: `POCTEST_DIR` = `DUA1:[USERS.POC]`, `POCTEST_DEV` =
  `DUA1:`, `POCTEST_ROOT` = `DUA1:[USERS.]` (concealed)

`""` below means `F$PARSE` returned nothing: refused, or (for a full parse)
the directory doesn't exist. The run didn't capture *why* a parse failed.
"S" marks a `SYNTAX_ONLY` parse, "F" a full one.

| # | | Spec | Default | Result |
|---|---|---|---|---|
| 1a | S | `DUA0:F.C` | `DUA1:[X]` | `DUA0:[X]F.C;` |
| 1b | S | `DUA0:F.C` | | `DUA0:[USERS.POC]F.C;` |
| 1c | F | `DUA0:F.C` | | `""` (no `DUA0:[USERS.POC]`) |
| 1d | S | `DUA0:[.A]F.C` | `DUA1:[X]` | `DUA0:[USERS.POC.A]F.C;` |
| 1e | S | `[A]F` | `DUA0:` | `DUA0:[A]F.;` |
| 1f | S | `[A]F` | | `DUA1:[A]F.;` |
| 1g | S | `_DUA1:F.C` | | `_DUA1:[USERS.POC]F.C;` |
| 2a | S | `POCTEST_DIR:F.C` | `DUA0:[X]` | `DUA1:[USERS.POC]F.C;` |
| 2b | F | `POCTEST_DIR:F.C` | `DUA0:[X]` | `DUA1:[USERS.POC]F.C;` |
| 2c | S | `POCTEST_DEV:F.C` | `DUA0:[X]` | `DUA1:[X]F.C;` |
| 2d | F | `POCTEST_DEV:F.C` | `DUA0:[X]` | `""` (no `DUA1:[X]`) |
| 2e | F | `SYS$LOGIN:F.C` | | `DUA1:[USERS.POC]F.C;` |
| 2f | S | `POCTEST_DIR:[.A]F.C` | | `""` |
| 2g | F | `POCTEST_DIR:[.A]F.C` | | `""` |
| 3a | S | `[.A]F.C` | `DUA1:[X.Y]` | `DUA1:[USERS.POC.A]F.C;` |
| 3b | S | `[-]F.C` | `DUA1:[X.Y]` | `DUA1:[USERS]F.C;` |
| 3c | S | `[-.B]F.C` | `DUA1:[X.Y]` | `DUA1:[USERS.B]F.C;` |
| 3d | S | `[--]F.C` | `DUA1:[X.Y]` | `DUA1:[000000]F.C;` |
| 3e | S | `[---]F.C` | `DUA1:[X.Y]` | `""` |
| 3f | S | `[]F.C` | `DUA1:[X.Y]` | `DUA1:[USERS.POC]F.C;` |
| 3g | S | `[.A]F.C` | | `DUA1:[USERS.POC.A]F.C;` |
| 3h | F | `[-]F.C` | | `DUA1:[USERS]F.C;` |
| 3i | S | `<A.B>F.C` | | `DUA1:<A.B>F.C;` |
| 3j | S | `[.A]F.C` | `[.B]` | `DUA1:[USERS.POC.A]F.C;` |
| 4a | S | `FOO.` | `.OBJ` | `DUA1:[USERS.POC]FOO.;` |
| 4b | S | `FOO` | `.OBJ` | `DUA1:[USERS.POC]FOO.OBJ;` |
| 4c | S | `FOO.;` | `.OBJ;5` | `DUA1:[USERS.POC]FOO.;` |
| 4d | S | `FOO.BAR.3` | | `DUA1:[USERS.POC]FOO.BAR;3` |
| 4e | S | `FOO.BAR;3` | | `DUA1:[USERS.POC]FOO.BAR;3` |
| 4f | S | `FOO` | `.OBJ;5` | `DUA1:[USERS.POC]FOO.OBJ;5` |
| 4g | S | `;7` | `X.Y;5` | `DUA1:[USERS.POC]X.Y;7` |
| 4h | S | `FOO.BAR;-1` | | `DUA1:[USERS.POC]FOO.BAR;-1` |
| 5a | S | `NODE::DUA0:[A]F.C` | | `NODE::DUA0:[A]F.C;` |
| 5b | S | `NODE::F.C` | | `NODE::F.C;` |
| 5c | S | `LONGNOD::DUA0:[A]F.C` | | `LONGNOD::DUA0:[A]F.C;` |
| 5d | S | `POCTEST_ROOT:[POC]F.C` | | `POCTEST_ROOT:[POC]F.C;` |
| 5e | F | `POCTEST_ROOT:[POC]F.C` | | `POCTEST_ROOT:[POC]F.C;` |
| 5f | F | `POCTEST_ROOT:[000000]F.C` | | `POCTEST_ROOT:[000000]F.C;` |
| 5g | S | `DUA1:[X]DUA0:F.C` | | `""` |
| 5h | S | `DUA1:[X][Y]F.C` | | `""` |
| 5i | S | `DUA1:[000000]` | | `DUA1:[000000].;` |
| 6a | S | `[A.B.C.D.E.F.G.H]F.C` | | `DUA1:[A.B.C.D.E.F.G.H]F.C;` |
| 6b | S | `[A.B.C.D.E.F.G.H.I]F.C` | | `""` |
| 6c | S | 39-character name `.C` | | accepted |
| 6d | S | 40-character name `.C` | | `""` |
| 6e | S | `F.` + 40-character type | | `""` |
| 6f | S | `VAX-DEC-VMS.C` | | `DUA1:[USERS.POC]VAX-DEC-VMS.C;` |
| 6g | S | `[POC.LIB.VAX-DEC-VMS]F.C` | | `DUA1:[POC.LIB.VAX-DEC-VMS]F.C;` |
| 6h | S | `A.B.C` | | `""` |
| 6i | S | `a b.c` | | `DUA1:[USERS.POC]AB.C;` |
| 6j | S | `A,B.C` | | `""` |

What follows for the proposal:

1. **The extension's dot is confirmed as needed.** `FOO.` refuses the
   default type and `FOO` takes it (4a, 4b). An empty version `;` takes no
   default version either (4c).
2. **The VMS rule of `Merge` changes** (5.3). Device, name, type and
   version are filled field by field (1a, 1e, 4b, 4f, 4g). An absolute
   directory comes from the name or else the defaults. A relative directory
   stays relative: RMS resolves it against the process's default directory,
   never the defaults' (1d, 3a, 3j). So `Merge` leaves `[.A]` and `[-]` as
   they are instead of appending them, and the result names the same file
   RMS will open. A name with a node takes nothing from the defaults (5b).
3. **`SubDirectory` can't extend a bare logical name lexically** (5.3).
   `POCTEST_DEV:[.A]` works (a device) but `POCTEST_DIR:[.A]` is refused
   (2f), and the two look alike. The host form in `Directories` expands
   such a name with `$PARSE` first. The pure form refuses it.
4. **Full parses check that the directory exists** (1c, 2d). That is what
   `rtl/vax/Directories.IsDirectory` relies on.
5. **A version may be written `.3`**; RMS rewrites it as `;3` (4d). `Split`
   takes either.
6. **RMS keeps what was written**: angle brackets stay angle brackets (3i),
   a leading `_` stays (1g), and a concealed rooted logical stays
   concealed (5d-5f). `FullName`'s result is therefore not a canonical
   form for comparison unless it asks for `NAM$M_NOCONCEAL`.
7. **`IsValidName` must refuse spaces itself** (6i). It also refuses
   names over 39 characters, a second dot, and `,` (6c-6e, 6h, 6j).

**A second run, the same day** (Appendix B), checked directory files with
`F$SEARCH` on directories that exist, and `F$PARSE`'s third argument,
the *related* file spec. Same process defaults; read-only.

| # | | Spec | Default | Related | Result |
|---|---|---|---|---|---|
| 7a | search | `DUA1:[000000]USERS.DIR;1` | | | found |
| 7b | search | `DUA1:[USERS]POC.DIR;1` | | | found |
| 7c | search | `DUA1:[000000]000000.DIR;1` | | | found |
| 7d | search | `DUA1:[USERS]POC.DIR` | | | `DUA1:[USERS]POC.DIR;1` |
| 7e | search | `DUA1:[USERS]poc.dir;1` | | | `DUA1:[USERS]POC.DIR;1` |
| 7f | search | `DUA0:[000000]000000.DIR;1` | | | found |
| 7g | F | `DUA1:[USERS.POC]` | | | `DUA1:[USERS.POC].;` |
| 7h | S | `DUA1:[000000.USERS.POC]` | | | `DUA1:[000000.USERS.POC].;` |
| 7i | F | `DUA1:[000000.USERS.POC]` | | | `DUA1:[000000.USERS.POC].;` |
| 7j | F | `DUA1:[USERS]POC.DIR;1` | | | `DUA1:[USERS]POC.DIR;1` |
| 7k | F | `DUA1:[000000]` | | | `DUA1:[000000].;` |
| 8a | S | `F` | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[X.Y]F.Q;` |
| 8b | S | `[.A]F.C` | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[USERS.POC.A]F.C;` |
| 8c | S | `F.C` | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[X.Y]F.C;` |
| 8d | S | `.C` | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[X.Y]Z.C;` |
| 8e | S | `F` | `.OBJ` | `DUA0:[X.Y]Z.Q;4` | `DUA0:[X.Y]F.OBJ;` |
| 8f | S | `F` | `DUA1:[A]` | `DUA0:[X.Y]Z.Q;4` | `DUA1:[A]F.Q;` |
| 8g | S | (empty) | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[X.Y]Z.Q;` |
| 8h | S | `[-]F` | | `DUA0:[X.Y]Z.Q;4` | `DUA0:[USERS]F.Q;` |
| 8i | S | `DUA1:F` | | `DUA0:[X.Y]Z.Q;4` | `DUA1:[X.Y]F.Q;` |
| 9a | S | (empty) | `DUA0:[X.Y]Z.Q;4` | | `DUA0:[X.Y]Z.Q;4` |
| 9b | S | `[.A]F.C` | `DUA0:[X.Y]` | | `DUA0:[USERS.POC.A]F.C;` |
| 9c | S | `F.C` | `[.B]` | | `DUA1:[USERS.POC.B]F.C;` |
| 9d | S | `F.C` | `[-]` | | `DUA1:[USERS]F.C;` |

What follows:

8. **Directory files are where Emacs 18 put them.** `[DIR.SUB]`'s file is
   `[DIR]SUB.DIR;1` (7b), `[DIR]`'s is `[000000]DIR.DIR;1` (7a), and the
   master file directory `[000000]` is its own file, `[000000]000000.DIR;1`
   (7c, 7f). The search ignores case (7e) and finds version 1 with no
   version given (7d). `[000000.USERS.POC]` is accepted as another spelling
   of `[USERS.POC]` (7h, 7i), so `Split` takes it.
9. **Default and related specs both supply defaults other than the current
   directory, for the device, directory, name and type.** The order is the
   name, then the default spec, then the related spec, then the process
   (8e, 8f: the default spec's `.OBJ` and `DUA1:[A]` win over the related
   spec's). The related spec supplies no version (8a, 8g); the default spec
   does (9a). The directory comes from the related spec even when the name
   brings another device (8i: `DUA1:[X.Y]`), as with a default spec (1a).
10. **Neither supplies the base of a relative directory.** `[.A]` and `[-]`
    in the name resolve against the process's default directory whatever
    the default or related spec says (3a, 8b, 8h, 9b). So do `[.B]` and `[-]`
    in the default spec itself (9c, 9d). Only `SYS$SETDDIR` (`SET DEFAULT`)
    changes that base, and section 15 rules it out because DCL keeps it
    after poc exits. A directory relative to some other directory has to
    be built by poc with `SubDirectory`, before RMS sees it.

These were all `F$PARSE` and `F$SEARCH`, which call `$PARSE` and `$SEARCH`.
`Files` will call the services directly with a NAM block, and is expected
to see the same, but that is not yet checked.

### 3.7 What this means for poc

1. **The directory part keeps its terminator** (Emacs). This is the one
   split rule that works unchanged for `/`, `\`, `:`, `]` and `>`, and
   directory + name = the whole name. poc's VMS `MakePath` already relies on
   it.
2. **The directory name and the directory file are different names** (Emacs).
   On VMS they are `[A.B]` and `[A]B.DIR;1`. Every operation that makes a
   subdirectory or goes to a parent has to produce a directory name, not
   append a component with a separator.
3. **Syntax is a value, not just the host** (Python's pure paths, CHICKEN's
   platform argument). poc running on Linux has to make VMS names for the
   `.COM` it writes, and to check that an image name is valid on VMS.
   Today `VaxImagePaths` does that by hand. A syntax parameter also lets the
   VMS rules be tested by a fixture on all four hosts without the guest.
4. **Node, device and version are components** (Common Lisp's six). A VMS
   name has all six. Windows has a node (a share's server), a device (a
   drive or a share) and the rest except a version. Unix has only directory, name and type. Unfilled,
   absent and empty have to stay distinct (`NIL`, `:unspecific`, `""`).
5. **"Absolute" means two things: a device, and a rooted directory** (3.6).
   Code that needs a complete name asks for both.
6. **Merging, not concatenation, is the general way to combine names.**
   `merge-pathnames` fills what a name leaves out, and RMS does the same
   with default file specifications. A name that brings its own device or
   root must not just be appended to a directory.
7. **Purely lexical work and file-system work are kept separate.** In each
   language, lexical `..` removal is wrong across symbolic links
   (Python's `normpath` documents this; Common Lisp separates `:up` from
   `:back` because of it). On VMS a logical name, a rooted logical name or
   a search list can't be resolved without RMS. Emacs 18 called `SYS$PARSE`
   for exactly that reason.
8. **There are no exceptions or dynamic strings.** The Oberon form is a
   `VAR ARRAY OF CHAR` result plus a BOOLEAN that says whether it fit.
   Today's `MakePath` silently cuts a name short. Every other language
   surveyed allocates its result, so none of them has this problem.

## 4. Where poc's source still treats names as Unix names

Found by grep for `"/"` and `"."` in `src/` on the `vax` branch at 17b9696,
after 7e25bbb:

| Place | What it does | Operation it needs |
|---|---|---|
| `src/front/ModuleInterface.Mod:272` `SymFileName`, `:527` (`.mod`) | appends `.sym`/`.mod` character by character | add an extension |
| `src/driver/Poc.Mod:730` `CompiledFiles` | `X.sym` to `X.o`/`X.ll` by overwriting the last 3 characters | replace an extension |
| `src/driver/Poc.Mod:750` `PairFiles` | recognizes `.sym`/`.o`/`.ll` and swaps in `.sym` | extension, replace an extension |
| `src/driver/Poc.Mod:1491` `VaxImagePaths` | finds the last `/`, compares the last 4 characters with `.EXE` after uppercasing them by hand, replaces it with `.com` | name part, extension (case-blind on VMS), replace an extension, a VMS-syntax validity check |
| `src/driver/Poc.Mod:2328` | `dir[0] = "/"` decides whether the name is absolute, and if not, puts `CWD` and `"/"` before it | is absolute, join |
| `src/driver/Libraries.Mod:276` `IsInstalled` | prefix test followed by `dir[i] = "/"` | is in a directory |
| `src/driver/Libraries.Mod:297` `ModelDirectory`, `:347` `OwnerFor` | `base/triple/model` with `Append(dir, "/")` | subdirectory (twice): on VMS `DEV:[BASE.TRIPLE.MODEL]` |
| `src/driver/Libraries.Mod:378`, `OtherTargets` (the `for f in */...` command) | shell commands | none: Unix only, as section 15 says |

The two `ModelDirectory`-style joins are the ones that produce *wrong* VMS
names today. `MakePath("DUA1:[POC.LIB]", "vax-dec-vms")` would give
`DUA1:[POC.LIB]vax-dec-vms`, a file, where `DUA1:[POC.LIB.VAX-DEC-VMS]` is
meant. The rest are correct on VMS by luck (the extensions) or never run
there.

## 5. Proposal

### 5.1 Two layers

1. **`FileNames`**: a new module of pure Oberon (no `SYSTEM`, no system
   calls), the same source for every target, that takes the syntax as a
   parameter:

   ```oberon
   CONST unix* = 0; windows* = 1; vms* = 2;  (* syntaxes *)
   ```

   Every procedure works for every syntax on every host. This is Python's
   `PurePosixPath`/`PureWindowsPath` and CHICKEN's platform argument. One
   fixture can test all three syntaxes on Linux and the BSDs, with no guest.
   Since it is plain Oberon, voc compiles it for Stage 0 too.
   *Decided by the user, 2026-10-10:* it lives in a new `rtl/common`,
   shared by every target (`rtl/llvm`, `rtl/vax`, and `rtl/voc` for
   Stage 0) rather than copied into each. That directory goes on each
   target's import path and into the Stage 0 build. The first version
   implements `unix` and `vms` only. `windows` stays a reserved constant
   and the Windows rules in this document stay the design for later
   (5.4).
2. **`Directories`** (the existing module, one per target) adds
   `syntax* = FileNames.unix` (or `.vms`) and versions of the common
   procedures for the host syntax that just pass `syntax` on. It keeps
   what needs the system: `IsDirectory`, `MakeDirectory`, and the
   proposed `FullName` (below).

### 5.2 The decomposition

```oberon
TYPE
  Span* = RECORD start*, end*: LONGINT END;  (* characters start..end-1; empty if start = end *)
  Parts* = RECORD
    node*,       (* VMS "NODE::", "NODE"user pass"::"  Windows "\\server", "\\?\UNC\server", "\\."  Unix "" *)
    device*,     (* VMS "DUA1:", "SYS$LOGIN:", "_DUA1:"  Windows "C:", "\share", "\COM1"  Unix "" *)
    directory*,  (* "/a/b/"  "a/b/"  "\a\b\"  "a\b\"  "[A.B]"  "[.A]"  "[-]"  "<A>" *)
    name*,       (* "x.tar"  "X" *)
    extension*,  (* ".gz"  ".COM" - with its dot; "." alone is present but empty *)
    version*: Span  (* VMS ";3", ";", ".3"; empty elsewhere *)
  END;

PROCEDURE Split*(syntax: INTEGER; path: ARRAY OF CHAR; VAR parts: Parts): BOOLEAN;
PROCEDURE SplitFrom*(syntax: INTEGER; text: ARRAY OF CHAR; start: LONGINT;
                     VAR parts: Parts; VAR end: LONGINT): BOOLEAN;
```

The spans index `path`, so nothing is copied, and they lie end to end:
node + device + directory + name + extension + version = `path`. That is
Python's `splitroot` invariant over Common Lisp's six components, with
the node as the host, as in the standard's `KATHY::[CHAPMAN]LOGIN.COM`.
Each span includes its own punctuation, so an empty span means unfilled
(Common Lisp's `NIL`). A span holding only its punctuation, such as
extension `.` or version `;`, means present but empty (`""`). `Split`
returns FALSE only for a name the syntax can't parse, such as an unclosed
`[` on VMS. `SplitFrom` is `parse-namestring`'s `:start`/`:junk-allowed`
form: it stops at the first character that can't continue a name and
returns where. That lets a caller take names out of a longer text. On VMS,
`,` and spaces can't occur in an ODS-2 name, so it stops there. (A quoted
access-control string in a node, `NODE"user pass"::`, is the one place a
`,` or space can occur, and `SplitFrom` skips over quotes.)

Decisions this makes, each with its precedent:

- **Devices and nodes are their own spans** (Common Lisp). *Decided by the
  user, 2026-10-10:* a Windows share splits into server and share, node
  `\\server` and device `\share`, as VMS's `NODE::DEV:` splits. Python
  keeps the two as one "drive", and SBCL puts them in the directory under
  device `:UNC`. The node runs up to the separator before the share or
  device name, and either separator is accepted:

  | Name | node | device | rest |
  |---|---|---|---|
  | `\\server\share\d\f` | `\\server` | `\share` | `\d\f` |
  | `//server/share/d/f` | `//server` | `/share` | `/d/f` |
  | `\\?\UNC\server\share\f` | `\\?\UNC\server` | `\share` | `\f` |
  | `\\?\C:\f` | `\\?` | `\C:` | `\f` |
  | `\\.\COM1` | `\\.` | `\COM1` | |

  A share's directory is always rooted: `\\server\share` alone is its
  root, `\\server\share\`. `\\server` with no share is a node with no
  device and names nothing. `Split` accepts it, so `SplitFrom` can stop
  there, but `IsComplete` is FALSE for it. `DevicePart` (below) returns
  node + device for callers that want Python's drive. `Merge`,
  `IsInDirectory` and `SameName` compare the node and device together,
  ignoring case.
- **Rootedness belongs to the directory**, not to a separate span:
  `/` or `\` first, or on VMS `[` or `<` followed by anything but `.`,
  `-` or `]`. `[]`, `[.A]` and `[-]` are relative.
- **The extension keeps its dot** (OCaml, Python). *Decided by the user,
  2026-10-10.* The reasons:
  - Oberon has no nil string, so without the dot `FOO` (no type) and `FOO.`
    (empty type) would both be `""`, as they are in GNAT's `Extension`. RMS
    treats them differently: `FOO.` refuses a default type and `FOO` takes
    one. `Merge` needs that difference, Common Lisp's `NIL` versus `""`.
  - Every other span carries its punctuation, so the parts add back up.
  - poc's source already writes `.sym`, `.library`, `.owner` and `.EXE`.

  An extension given as an *argument* must be `""` (none: remove it), `"."`
  (empty: `FOO.`), or `"."` followed by characters that contain no `.` and
  no separator of the syntax. Anything else makes the procedure return
  FALSE, as Python's `with_suffix("txt")` raises "Invalid suffix". This is
  stricter than Emacs's `file-name-with-extension`, which accepts either
  form. On VMS a second dot would also be read as a version.
- **A leading dot is part of the name** (everyone but GNAT): `.bashrc` has no
  extension on Unix and Windows. VMS has no such case.
- **The directory part keeps its terminator** (Emacs). `a/b/` is all
  directory with an empty name. That is the only reading that matches
  `[A.B]`.
- **VMS versions are found before the extension** (Emacs 18
  `file-name-sans-versions`): `FOO.BAR;3` and `FOO.BAR.3` both have
  extension `.BAR` and version `;3`/`.3`.
- **`<` and `>` are accepted as `[` and `]`** on VMS. ODS-5's `^` escapes
  are not accepted, since VMS 5.5-2 has only ODS-2.

### 5.3 Procedures

Results are `VAR ARRAY OF CHAR`. Every procedure that builds a name is a
function returning whether the result fit, and leaves `""` when it didn't.
poc's callers can then report "name too long" instead of opening a truncated
name. Each name below is followed by its precedents.

**Parts** (pure, `FileNames`):

- `NodePart(syntax, path, VAR node)`, `DevicePart(syntax, path, VAR device)`
  (node + device: Python's `splitdrive`, Common Lisp `pathname-host` and
  `pathname-device`, `host-namestring`).
- `DirectoryPart(syntax, path, VAR dir)`: node + device + directory (Emacs
  `file-name-directory`, Common Lisp `directory-namestring` plus the device).
- `NamePart(syntax, path, VAR name)`: name + extension + version (Emacs
  `file-name-nondirectory`, Ada `Simple_Name`, Common Lisp `file-namestring`).
- `BaseName(syntax, path, VAR base)`: name only (Ada `Base_Name`, Emacs
  `file-name-base`, Common Lisp `pathname-name`).
- `Extension(syntax, path, VAR ext)`: with its dot; `""` for none, `"."`
  for an empty one.
- `Version(syntax, path, VAR version)`, `WithoutVersion(...)`: VMS only,
  `""` and the name itself elsewhere (Common Lisp `pathname-version`, Emacs
  18 `file-name-sans-versions`).
- `HasExtension(syntax, path, ext): BOOLEAN`: `ext` as 5.2 requires;
  ignores case on Windows and
  VMS (OCaml Win32 `check_suffix`). This replaces `VaxImagePaths`'s
  hand-uppercased `.EXE` and `PairFiles`'s character compares.

**Questions:**

- `HasDevice(syntax, path)`: a device span (always FALSE on Unix).
- `IsRooted(syntax, path)`: the directory starts at a root (above).
- `IsComplete(syntax, path)`: both on Windows and VMS, `IsRooted` on Unix.
  This is section 3.6's two-part "absolute". On VMS a device that is a
  logical name may bring its own directory, so `SYS$LOGIN:F` is complete
  in fact but not by this test. Only `FullName` can tell. These three
  replace the single `IsAbsolute` of the first draft, which followed
  Emacs 18 in calling `DEV:[.A]` absolute.
- `IsRoot(syntax, dir)`: `/`; `C:\`, `\\server\share\`; `DEV:[000000]`,
  and `[000000]` alone (Ada `HFN.Is_Root_Directory_Name`, UIOP
  `pathname-root`).
- `IsInDirectory(syntax, dir, path)`: `dir` is a directory-part prefix of
  `path`, with the same node and device, ignoring case on Windows and VMS
  (UIOP `subpathp`, which also requires `pathname-root`s to be equal).
  Replaces `IsInstalled`'s `dir[i] = "/"`.
- `SameName(syntax, a, b)`: equal, ignoring case on Windows and VMS (Ada
  `Name_Case_Equivalence`, Python `normcase`, UIOP `pathname-equal`).
  Lexical only: `SYS$LOGIN:` and the directory it stands for are different
  names here (3.6).
- `IsValidName(syntax, name)`: a name and extension the syntax accepts.
  Unix: no `/` or `0X`. Windows: `ntpath.isreserved`'s rules, which include
  the reserved device names. VMS ODS-2: 39 characters before and after a
  single dot, `A-Z a-z 0-9 $ _ -` (GNAT's `a-dirval-vms.adb`; hyphens are
  legal since VMS 4.4, Emacs 18). This is the check `VaxImagePaths` makes on
  `-o`'s last component, and the base of section 15's 39-character check.
- `IsValidDevice(syntax, device)`: Windows `A:`-`Z:`; VMS letters, digits,
  `$`, `_`, an optional leading `_`, ending in `:` (limits from memory,
  3.6).
- `listSeparator(syntax)`: `:`, `;`, `,`. The existing constant
  `Directories.pathSeparator` stays.
- `NullDevice(syntax, VAR name)`: `/dev/null`, `NUL`, `NLA0:` (OCaml
  `Filename.null`, Python `os.devnull`).

**Building:**

- `Merge(syntax, name, defaults, VAR result): BOOLEAN`: fills what `name`
  leaves out from `defaults` (Common Lisp `merge-pathnames`, RMS's default
  file specification). The rule depends on the syntax (3.5.1):
  - *VMS*: as RMS does (3.6.1). Device, name, type and version are filled
    field by field, so `C:F` with `D:[X]` gives `C:[X]F` (1a). An absolute
    directory comes from `name`, or else from `defaults`. A relative
    directory (`[.A]`, `[-]`, `[]`) is left in place, not appended to the
    defaults' directory, because RMS resolves it against the process's
    default directory and ignores the defaults' (1d, 3a, 3j). A `name` with
    a node is returned as it is (5b).
  - *Windows*: a name with a device other than the defaults' takes nothing
    from the defaults' directory. `C:a\f` with `D:\x\` stays `C:a\f`, as
    Python's `join` keeps `D:b`. A rooted name without a device takes the
    defaults' device: `\a\f` gives `D:\a\f`. The remaining relative part
    (`C:a\f`) is left for `FullName`.
  - *Unix*: a rooted name replaces the directory, and a relative one is
    appended.
  
  The version is filled only if `name` has no name, as the standard says.
- `MakePath(syntax, dir, name, VAR path): BOOLEAN`: today's rules (Unix
  `/` unless `dir` ends in one; Windows `\` unless it ends in `\`, `/` or a
  drive's `:`, since `C:\x` is not `C:x`; VMS nothing after `:`, `]`, `>`,
  and `:` after a bare logical name). Ada `Compose`, OCaml `concat`, Emacs
  `file-name-concat`. If `name` has a node, device or rooted directory,
  `MakePath` is `Merge(name, dir)`, so that
  `MakePath("DUA1:[A]", "SYS$LOGIN:X.COM")` gives `SYS$LOGIN:X.COM` rather
  than `DUA1:[A]SYS$LOGIN:X.COM`. *Decided by the user, 2026-10-10:*
  `Directories.MakePath` becomes `Directories.MakePath(dir, name, VAR
  path): BOOLEAN` too, passing the host syntax on. Every existing caller
  in `src/` switches to it and reports a name that doesn't fit, instead
  of using a name cut short.
- `Compose(syntax, dir, base, ext, VAR path): BOOLEAN`: `ext` with its dot,
  as 5.2 requires, so there is no question of adding one (GNAT's
  `HFN.Compose` drops it; `Ada.Directories.Compose` adds it).
- `ReplaceExtension(syntax, path, ext, VAR result): BOOLEAN`: `ext` as 5.2
  requires (`""` removes the extension, `"."` leaves an empty one); keeps node,
  device, directory and version (Common Lisp `make-pathname :type ..
  :defaults`, CHICKEN `pathname-replace-extension`, Emacs
  `file-name-with-extension`). This is what `CompiledFiles` and
  `PairFiles` do by hand.
- `SubDirectory(syntax, dir, name, VAR result): BOOLEAN`: the directory
  *name* of `name` inside `dir`. Unix `a/b` + `c` gives `a/b/c/`. Windows
  `C:` + `c` gives `C:c\`. VMS `DEV:[A.B]` + `C` gives `DEV:[A.B.C]`,
  `ROOT:[POC]` (a concealed rooted logical) gives `ROOT:[POC.C]`, and `""`
  gives `[.C]`. A bare `DEV:` is refused by this pure form, since a
  physical device or device-only logical takes `DEV:[.C]` (relative to the
  default directory: 1d, 2c), while a logical that brings a directory
  refuses `[.C]` (2f), and the two look alike. `Directories.SubDirectory`
  expands such a name with `$PARSE` first (`FullName`) and then extends
  the result. Common
  Lisp's appending to the directory list; Emacs's `file-name-as-directory`
  applied to `[A.B]C.DIR`; UIOP `subpathname`. `ModelDirectory` and
  `OwnerFor` need it. The ODS-2 limit of 8 directory levels is checked here
  (FALSE beyond it).
- `DirectoryFile(syntax, dir, VAR file): BOOLEAN` and
  `AsDirectory(syntax, file, VAR dir): BOOLEAN`: from a directory's name to
  the name of the file that is the directory, and back. This is Emacs's
  `directory-file-name`/`file-name-as-directory` pair with Emacs 18's VMS
  rules, checked on the guest (3.6.1, items 8-10). The node and device are
  kept. Unlike cl-fad's `pathname-as-file` and UIOP's
  `ensure-directory-pathname`, the VMS form adds and drops `.DIR;1`.
  Needed on VMS for deleting or renaming a directory, and for any
  operation that treats a directory as a file in its parent.

  | `dir` | `DirectoryFile` gives |
  |---|---|
  | `DEV:[DIR.SUB.SUBSUB]` | `DEV:[DIR.SUB]SUBSUB.DIR;1` |
  | `DEV:[DIR]` | `DEV:[000000]DIR.DIR;1` |
  | `DEV:[000000]` | `DEV:[000000]000000.DIR;1` |
  | `DEV:[000000.DIR.SUB]` | `DEV:[000000.DIR]SUB.DIR;1` |
  | `<DIR.SUB>` | `<DIR>SUB.DIR;1` |
  | `[.A.B]`, `[.A]` | `[.A]B.DIR;1`, `[]A.DIR;1` |
  | `[-.A]` | `[-]A.DIR;1` |
  | `[-]`, `[]`, a bare `DEV:`, a concealed `ROOT:[000000]` | FALSE: the parent's name isn't in the text; `Directories.DirectoryFile` expands it with `FullName` first |

  `AsDirectory` is the reverse. It takes a name of type `.DIR` (in any case)
  with version `;1` or none, and refuses any other. `DEV:[DIR]SUB.DIR;1`
  gives `DEV:[DIR.SUB]`, `DEV:[000000]DIR.DIR` gives `DEV:[DIR]`,
  `DEV:[000000]000000.DIR;1` gives `DEV:[000000]`, and `SUB.DIR` with no
  directory gives `[.SUB]`.

  On Unix the file system treats `a/b` and `a/b/` as the same directory,
  so the pair changes only the text. *Decided by the user, 2026-10-10:* it
  removes and adds the trailing `/`, as Emacs does. `DirectoryFile("a/b/")`
  gives `a/b`, and `AsDirectory("a/b")` gives `a/b/`. `/` stays `/` both
  ways, as Emacs 31's `directory-file-name` leaves it. This lets the pair
  work with the other procedures the same way on both systems.
  `DirectoryPart(DirectoryFile(d))` is the directory containing `d`: `a/`
  from `a/b/`, and `DEV:[DIR.SUB]` from `DEV:[DIR.SUB.SUBSUB]`.
- `ParentDirectory(syntax, dir, VAR parent): BOOLEAN`, lexical: Unix `a/b/`
  gives `a/`. VMS `DEV:[A.B]` gives `DEV:[A]`, `DEV:[A]` gives
  `DEV:[000000]`, and `[.A]` gives `[]`. FALSE at a device's root (Emacs 31
  `file-name-parent-directory`, Ada `Containing_Directory`'s `Use_Error`,
  UIOP `pathname-parent-directory-pathname`). On VMS this is exact, since
  RMS resolves `-` from the text (Common Lisp's `:back`). On Unix it is
  `:back` where the kernel does `:up`, so it can differ across a symbolic
  link. It is only for names poc builds, not for names the user gives.
- `RelativeName(syntax, path, defaults, VAR result): BOOLEAN`: Common Lisp
  `enough-namestring`, with its invariant `Merge(result, defaults)` = `path`
  (UIOP `enough-pathname`, Emacs `file-relative-name`, Python `relpath`).
  It drops the node and device when they match. For shorter names in
  messages. Low priority.

**System-dependent** (in `Directories` only, as today):

- `IsDirectory`, `MakeDirectory`: unchanged. `MakeDirectory` keeps taking a
  directory, not a file as `ensure-directories-exist` does.
- `FullName(name, VAR full): BOOLEAN`: the complete, canonical name (Ada
  `Full_Name`, Python `realpath`, Common Lisp `truename`). Unix: `realpath`
  in `Directories.c`. VMS: `$PARSE` without `SYNCHK`, which translates
  logical names, rooted directories, search lists and `[-]`, and fills the
  device from `SYS$DISK` and the directory from the default directory. That
  is what Emacs 18 used `SYS$PARSE` for. Windows, if it ever has an rtl:
  `GetFullPathName`, which resolves `C:a` against C:'s current directory.
  It replaces `Poc.Mod:2328`'s `CWD + "/" + dir`.
- `DefaultDirectory(VAR dir)`: the complete current directory, with its
  device (Common Lisp `*default-pathname-defaults*`, UIOP `getcwd`).
  Platform's `CWD` is that string already (section 15: `SYS$DISK` and
  `SYS$SETDDIR`'s directory joined on VMS). This gives it to `Merge`
  under a name that says what it is.

### 5.4 What is deliberately left out

- **Lexical normalization** (`normpath`, CHICKEN's `normalize-pathname`,
  Emacs's `[A.B.-]` collapsing). It is wrong across symbolic links on Unix
  and across rooted logicals on VMS. `FullName` covers poc's need for it.
  `Merge` does only the standard's `:back` removal for a relative directory
  it appends.
- **Logical pathnames** (Common Lisp 19.3). VMS logical names and Unix
  environment variables are the system's own forms of the same idea, and
  `GetEnv` already reads both.
- **Unix-to-VMS translation** (Emacs 18's `sys_translate_unix`, GNAT's
  `To_Host_File_Spec`, UIOP's `parse-unix-namestring`). It would let
  `-import-path rtl/vax` work on the guest unchanged. It is worth a
  follow-up once poc runs there, as a `FileNames.Translate(from, to, path,
  VAR result)` limited to relative names and `/dev/...`, if the user
  wants it.
- **Wildcards, search lists, `~`, environment substitution** (Emacs's
  `substitute-in-file-name`, Common Lisp's `:wild` and `translate-pathname`).
  Search lists are RMS's business.
- **`:case :common`**. poc's module names are mixed case and keep it on
  Unix, and RMS uppercases them on VMS. `SameName` and `HasExtension`
  ignore case where the system does.
- **Windows, in the first version** (decided by the user, 2026-10-10).
  poc has no Windows backend or runtime. `FileNames.windows` is reserved,
  and this document's Windows rules (3.2, 3.6, 5.2's share table, `Merge`'s
  Windows rule) are the design to follow when it is added. The parts
  record already has the node and device spans that Windows needs, so
  adding the syntax later means new cases in each procedure but no
  change to the interface.

### 5.5 Order of work

0. **Done 2026-10-10:** section 3.6's RMS claims checked on the guest with
   `tools/vax-do` and `F$PARSE` (3.6.1). The VMS rules of `Merge` and
   `SubDirectory` were corrected from the results.
1. `FileNames` with `Split`, the parts, the questions and the building
   procedures, in `rtl/common`, for `unix` and `vms`. A fixture runs
   a table of names through every procedure in every syntax on the four
   hosts. The table starts with sections 3.1-3.6's cases: `a/b/`,
   `.bashrc`, `foo.`, `/`, `C:x`, `C:`, `\x`, 5.2's five share and
   device-namespace names, `\\server`,
   `DEV:[A.B]F.C;3`, `FOO.BAR.3`, `FOO.;`, `[.X]`, `[-]`, `[]`, `<A.B>`,
   `NODE::DEV:F`, `NODE"u p"::DEV:F`, `_DUA1:[000000]`, `SYS$LOGIN:F`,
   `DEV:F`, `[A]F`, `[A.]`, `X.DIR;1`, plus the `Merge` rows of 3.5.1.
   Expected VMS answers for `Merge` come from 3.6.1's `F$PARSE` results, not
   from memory, and the fixture's VMS rows include 3.6.1's cases.
2. `Directories` gains `syntax` and the host forms. `src/` moves to them:
   the eight places in section 4 except the shell commands, with
   `SubDirectory` fixing `ModelDirectory`/`OwnerFor` for VMS.
3. `IsInDirectory`, `SameName`, `IsValidName` (folding section 15's
   39-character check into it), `DefaultDirectory`, then `FullName` on
   both targets. `RelativeName` last, if wanted.

### 5.6 Decisions and questions

Decided by the user, 2026-10-10:

1. A Windows share splits into server (node) and share (device) (5.2).
2. `FileNames` lives in `rtl/common` (5.1).
3. The first version has no Windows syntax (5.4).
4. `MakePath` callers switch to the form that returns whether the result
   fit (5.3).
5. The extension keeps its dot, and an extension given as an argument must
   start with one (5.2).
6. On Unix, `DirectoryFile` and `AsDirectory` remove and add the trailing
   `/` (5.3).

Open: none.

## Appendix A. The step 0 procedure

Run as `tools/vax-do -o <scratch dir> parsetest.com` on 2026-10-10 (3.6.1).
Its `SHOW` commands record the process's defaults. The `CALL T` lines are the
cases, and `T` prints each result. The process logical names it defines
are deassigned at the end.

```dcl
$ SET NOON
$ SHOW DEFAULT
$ SHOW LOGICAL SYS$DISK
$ SHOW LOGICAL SYS$LOGIN
$ SHOW DEVICE D
$ DEFINE/PROCESS POCTEST_DIR DUA1:[USERS.POC]
$ DEFINE/PROCESS POCTEST_DEV DUA1:
$ DEFINE/PROCESS/TRANSLATION=CONCEALED POCTEST_ROOT DUA1:[USERS.]
$ SAY = "WRITE SYS$OUTPUT"
$ SAY "---- 1. device given, directory from defaults"
$ CALL T "1a" "DUA0:F.C" "DUA1:[X]" "SYNTAX_ONLY"
$ CALL T "1b" "DUA0:F.C" "" "SYNTAX_ONLY"
$ CALL T "1c" "DUA0:F.C" "" ""
$ CALL T "1d" "DUA0:[.A]F.C" "DUA1:[X]" "SYNTAX_ONLY"
$ CALL T "1e" "[A]F" "DUA0:" "SYNTAX_ONLY"
$ CALL T "1f" "[A]F" "" "SYNTAX_ONLY"
$ CALL T "1g" "_DUA1:F.C" "" "SYNTAX_ONLY"
$ SAY "---- 2. logical names in the device field"
$ CALL T "2a" "POCTEST_DIR:F.C" "DUA0:[X]" "SYNTAX_ONLY"
$ CALL T "2b" "POCTEST_DIR:F.C" "DUA0:[X]" ""
$ CALL T "2c" "POCTEST_DEV:F.C" "DUA0:[X]" "SYNTAX_ONLY"
$ CALL T "2d" "POCTEST_DEV:F.C" "DUA0:[X]" ""
$ CALL T "2e" "SYS$LOGIN:F.C" "" ""
$ CALL T "2f" "POCTEST_DIR:[.A]F.C" "" "SYNTAX_ONLY"
$ CALL T "2g" "POCTEST_DIR:[.A]F.C" "" ""
$ SAY "---- 3. relative directories"
$ CALL T "3a" "[.A]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3b" "[-]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3c" "[-.B]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3d" "[--]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3e" "[---]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3f" "[]F.C" "DUA1:[X.Y]" "SYNTAX_ONLY"
$ CALL T "3g" "[.A]F.C" "" "SYNTAX_ONLY"
$ CALL T "3h" "[-]F.C" "" ""
$ CALL T "3i" "<A.B>F.C" "" "SYNTAX_ONLY"
$ CALL T "3j" "[.A]F.C" "[.B]" "SYNTAX_ONLY"
$ SAY "---- 4. empty type, versions"
$ CALL T "4a" "FOO." ".OBJ" "SYNTAX_ONLY"
$ CALL T "4b" "FOO" ".OBJ" "SYNTAX_ONLY"
$ CALL T "4c" "FOO.;" ".OBJ;5" "SYNTAX_ONLY"
$ CALL T "4d" "FOO.BAR.3" "" "SYNTAX_ONLY"
$ CALL T "4e" "FOO.BAR;3" "" "SYNTAX_ONLY"
$ CALL T "4f" "FOO" ".OBJ;5" "SYNTAX_ONLY"
$ CALL T "4g" ";7" "X.Y;5" "SYNTAX_ONLY"
$ CALL T "4h" "FOO.BAR;-1" "" "SYNTAX_ONLY"
$ SAY "---- 5. nodes, rooted logicals, odd forms"
$ CALL T "5a" "NODE::DUA0:[A]F.C" "" "SYNTAX_ONLY"
$ CALL T "5b" "NODE::F.C" "" "SYNTAX_ONLY"
$ CALL T "5c" "LONGNOD::DUA0:[A]F.C" "" "SYNTAX_ONLY"
$ CALL T "5d" "POCTEST_ROOT:[POC]F.C" "" "SYNTAX_ONLY"
$ CALL T "5e" "POCTEST_ROOT:[POC]F.C" "" ""
$ CALL T "5f" "POCTEST_ROOT:[000000]F.C" "" ""
$ CALL T "5g" "DUA1:[X]DUA0:F.C" "" "SYNTAX_ONLY"
$ CALL T "5h" "DUA1:[X][Y]F.C" "" "SYNTAX_ONLY"
$ CALL T "5i" "DUA1:[000000]" "" "SYNTAX_ONLY"
$ SAY "---- 6. limits"
$ CALL T "6a" "[A.B.C.D.E.F.G.H]F.C" "" "SYNTAX_ONLY"
$ CALL T "6b" "[A.B.C.D.E.F.G.H.I]F.C" "" "SYNTAX_ONLY"
$ CALL T "6c" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABC.C" "" "SYNTAX_ONLY"
$ CALL T "6d" "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCD.C" "" "SYNTAX_ONLY"
$ CALL T "6e" "F.ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCD" "" "SYNTAX_ONLY"
$ CALL T "6f" "VAX-DEC-VMS.C" "" "SYNTAX_ONLY"
$ CALL T "6g" "[POC.LIB.VAX-DEC-VMS]F.C" "" "SYNTAX_ONLY"
$ CALL T "6h" "A.B.C" "" "SYNTAX_ONLY"
$ CALL T "6i" "a b.c" "" "SYNTAX_ONLY"
$ CALL T "6j" "A,B.C" "" "SYNTAX_ONLY"
$ DEASSIGN/PROCESS POCTEST_DIR
$ DEASSIGN/PROCESS POCTEST_DEV
$ DEASSIGN/PROCESS POCTEST_ROOT
$ EXIT 1
$ T: SUBROUTINE
$ SET NOON
$ IF P4 .EQS. ""
$ THEN X = F$PARSE(P2,P3)
$ ELSE X = F$PARSE(P2,P3,,,P4)
$ ENDIF
$ S = $STATUS
$ WRITE SYS$OUTPUT P1, " ", P4, ": ", P2, " + ", P3, " => [", X, "] ", F$MESSAGE(S)
$ EXIT 1
$ ENDSUBROUTINE
```

## Appendix B. The second step 0 procedure

Run as `tools/vax-do -o <scratch dir> parsetst2.com` on 2026-10-10 (3.6.1,
items 8-10). `S` searches with `F$SEARCH` without wildcards, so it needs no
stream-id. `R` passes a related spec as `F$PARSE`'s third argument.

```dcl
$ SET NOON
$ SHOW DEFAULT
$ SAY = "WRITE SYS$OUTPUT"
$ SAY "---- 7. directory files"
$ CALL S "7a" "DUA1:[000000]USERS.DIR;1"
$ CALL S "7b" "DUA1:[USERS]POC.DIR;1"
$ CALL S "7c" "DUA1:[000000]000000.DIR;1"
$ CALL S "7d" "DUA1:[USERS]POC.DIR"
$ CALL S "7e" "DUA1:[USERS]poc.dir;1"
$ CALL S "7f" "DUA0:[000000]000000.DIR;1"
$ CALL T "7g" "DUA1:[USERS.POC]" "" ""
$ CALL T "7h" "DUA1:[000000.USERS.POC]" "" "SYNTAX_ONLY"
$ CALL T "7i" "DUA1:[000000.USERS.POC]" "" ""
$ CALL T "7j" "DUA1:[USERS]POC.DIR;1" "" ""
$ CALL T "7k" "DUA1:[000000]" "" ""
$ SAY "---- 8. related file spec (F$PARSE's third argument)"
$ CALL R "8a" "F" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8b" "[.A]F.C" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8c" "F.C" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8d" ".C" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8e" "F" ".OBJ" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8f" "F" "DUA1:[A]" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8g" "" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8h" "[-]F" "" "DUA0:[X.Y]Z.Q;4"
$ CALL R "8i" "DUA1:F" "" "DUA0:[X.Y]Z.Q;4"
$ SAY "---- 9. default spec, more"
$ CALL T "9a" "" "DUA0:[X.Y]Z.Q;4" "SYNTAX_ONLY"
$ CALL T "9b" "[.A]F.C" "DUA0:[X.Y]" "SYNTAX_ONLY"
$ CALL T "9c" "F.C" "[.B]" "SYNTAX_ONLY"
$ CALL T "9d" "F.C" "[-]" "SYNTAX_ONLY"
$ EXIT 1
$ T: SUBROUTINE
$ SET NOON
$ IF P4 .EQS. ""
$ THEN X = F$PARSE(P2,P3)
$ ELSE X = F$PARSE(P2,P3,,,P4)
$ ENDIF
$ WRITE SYS$OUTPUT P1, " ", P4, ": ", P2, " + ", P3, " => [", X, "]"
$ EXIT 1
$ ENDSUBROUTINE
$ R: SUBROUTINE
$ SET NOON
$ X = F$PARSE(P2,P3,P4,,"SYNTAX_ONLY")
$ WRITE SYS$OUTPUT P1, " SYNTAX_ONLY: ", P2, " + default ", P3, " + related ", P4, " => [", X, "]"
$ EXIT 1
$ ENDSUBROUTINE
$ S: SUBROUTINE
$ SET NOON
$ X = F$SEARCH(P2)
$ WRITE SYS$OUTPUT P1, " search: ", P2, " => [", X, "]"
$ EXIT 1
$ ENDSUBROUTINE
```
