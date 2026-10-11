# VMS interface modules from SDL (Phase 17 step 5)

`PLAN.md` Phase 17 step 5 asks whether a tool generates poc's Oberon
modules for VMS's own definitions - status codes, function codes,
control-block layouts, the `SYS$`, `LIB$` and other routines - and names
the user's UNSDL utility as the likely starting point. This is the first
look at that utility and the guest (2026-10-11), with the user's
decisions the same day. The step's design and proposals come later, when
Phase 17 begins; nothing here is built yet.

## What UNSDL is

UNSDL (`~/Repos/myunsdl`, 1988-1990, VAX C; its `aaareadme.txt` and
sources) is a set of *language back ends* for SDL, not a parser of SDL
source. VMS keeps STARLET's definitions, written in SDL, already parsed:
SDL's intermediate files (`.SDI`) are the modules of the text library
`SYS$SHARE:STARLETSD.TLB`. `SDL/NOPARSE/LANGUAGE=<x> <file>.SDI` reads one
into a tree in memory, maps in the shareable image `SDL$SHARE:SDL<x>.EXE`,
and calls its `sdl$output(outputname, module, root)`; the back end walks
the tree and writes the declarations for its language.

- `unsdl.c` is a driver with its own verb, `UNSDL` (`unsdl.cld`):
  `UNSDL <file>/LANGUAGE=<x>=<options>/OUTPUT=<file>` puts the options in
  a DCL symbol (`SDL_COMMAND_ARGS`), which `SDL/NOPARSE` has no way to
  pass, and then runs `SDL/NOPARSE/LANGUAGE=<x>=<output> <file>` itself
  through `LIB$DO_COMMAND`. It is a front end to `SDL/NOPARSE`, not a
  replacement: SDLNPARSE still reads the `.SDI` file and calls the back
  end.
- `sdlcc.c` writes C headers; `sdlscm.c` writes Scheme (constants as
  `(define ...)`, entries as `(define-foreign ...)` with each parameter's
  type, direction, mechanism and optionality; it does not render
  aggregates); `sdldump.c` dumps the tree. Each is linked `/SHARE` with
  `misc.c`, `readable.mar` (`PROBER`, to test a pointer before following
  it) and, for the options, a CLD.
- `sdldef.h` is the tree, worked out by reading it (some fields are
  marked "???"): node kinds root, comment, constant, entry, item (a field
  or aggregate), module, parameter and head (each list's head); each node
  a name, prefix and tag, an offset, a field size, low and high
  dimensions, a data type (address, byte, character, boolean, decimal, D,
  F, G and H floating, longword, octaword, quadword, bit field, word,
  structure, union, any, entry, the complex types) and flags (value,
  mask, unsigned, based, descriptor, dimension, in, out, reference, fill,
  optional, list, RTL string descriptor, and others); a constant's value
  is its `typeinfo`, a character item's length too.
- `all4.com` and `all5.com` extract about 30 of the library's modules
  with `LIBRARY/EXTRACT` and run UNSDL on each.

## What the guest has (2026-10-11, `tools/vax-do`)

- `SYS$COMMON:[SYSLIB]STARLETSD.TLB;10`, created 9-JUL-1993 (the
  5.5-2H4 kit), 65 modules: `STARLET` (the `SYS$` services);
  `STARDEFAE`, `STARDEFFL`, `STARDEFMP` and `STARDEFQZ` (the `$xxxDEF`
  definitions, alphabetically in four parts); `RMSDEF` and `RMSUSR`; the
  routines of `LIB$`, `STR$`, `SMG$`, `OTS$`, `MTH$`, `DTK$`, `PPL$`,
  `SOR$` and `NCS$`; `SSMSG` and the other `*MSG` modules of status
  codes; `SMGDEF`, `LIBCLIDEF`, `LBRUSR`, `OBJFMT`, `VAXDEF` and others.
- `SYS$COMMON:[SYSEXE]SDLNPARSE.EXE`, and the `SDL` verb in the
  system's DCL tables: `SDL/NOPARSE` works for `POC` as for any user (the
  user's session showed it first; `POC`'s `SDL/NOPARSE NLA0:` ended with
  success). `SDL$SHARE` is not defined, as `sdl.rno` expects: it is a
  logical name the user of a back end defines to point at the directory
  holding the back ends (`DEFINE SDL$SHARE DISK:[DIR]`), since SDLNPARSE
  finds one by `LIB$FIND_IMAGE_SYMBOL("SDL$SHARE:SDL<x>", "SDL$OUTPUT")`.
  UNSDL and its back ends should therefore run on the guest as they are.
- VAX C 3.2, which builds the back end.

## Decided (the user, 2026-10-11)

- **The generator runs on the VAX** and is built with **VAX C**. poc and
  its runtime still use none of the layered products (Phase 16 step 1);
  the generator is a tool run when the modules are made, and what it
  writes is committed.
- **Not on the host**: a `.SDI` file is kept in one of VMS's record
  formats inside a text library (`STARLETSD.TLB` is in DCX data-reduced
  format), and the tree is SDLNPARSE's in-memory one, which nobody has
  documented as a file; reading either away from RMS and the Librarian
  is not worth it.

## What poc needs

1. **A back end of its own, `SDLOBERON`**, written as `sdlscm.c` and
   `sdlcc.c` are, that writes one poc module for each SDL module (for
   example `SsMsg`, `IoDef`, `LibRoutines`):
   - a constant as `CONST SS$_NORMAL* = 1;`, a mask in hexadecimal; the
     names are the system's, which poc allows (`AGENTS.md`, "Underscores
     and dollar signs in identifiers");
   - an entry as `PROCEDURE ["VMS", "SYS$QIOW"] ...;`;
   - exact-width types only, `SYSTEM.INT8/16/32/64` and
     `SYSTEM.ADDRESS`, so that a module means the same under `-O2` and
     `-OC`; F_floating as `REAL` and G_floating as `LONGREAL`, which are
     poc's VAX formats; D_floating, which poc has no type for, as 8
     bytes, H_floating and an octaword as 16;
   - a banner naming the library, its version and SDL's, so that a
     module says which kit it came from.

2. **What the language and the VAX backend lack**, which is most of the
   step, since the generator can only write what poc accepts:
   - *Passing mechanisms*. A `["VMS"]` external now passes a value of 4
     bytes or less by value and a `VAR` parameter by reference
     (`vax-macro32-backend.md`, section 7); a descriptor is an error.
     SDL marks each parameter value, reference or descriptor (or RTL
     string descriptor), so a declaration needs a way to say which.
   - *Optional parameters*, which most `SYS$` services have and Oberon
     does not. One convention: an optional parameter passed by
     reference is declared `SYSTEM.ADDRESS`, and 0 omits it.
   - *Record layout*. VMS lays out a structure with no alignment (VAX
     C's rule, which VMS's languages follow), and poc aligns a field to
     its size up to 4 bytes (`vax-macro32-backend.md`, section 4,
     decided). Its records match a VMS structure only with a
     packed-record attribute, which that section left to this phase;
     without one, a structure is an array of bytes and its fields
     offset constants (`FAB$L_FNA`).
   - *Unions and bit fields*, which an Oberon record cannot express
     (`PLAN.md` says so). SDL already gives each bit field its position,
     size and mask (`$V_`, `$S_`, `$M_` constants), which a program can
     use with `SET`s and `SYSTEM`; a union's arms overlap, so one arm
     at most can be a record's fields.
   - *Item lists and descriptors* as types a program can fill, which
     the same step asks for.
