# Libraries without a shared object

`poc -library` always builds a library both ways, an archive and a shared
object. pofltk showed (2026-10-31) that this is not always possible: on
systems whose FLTK is only static libraries built without `-fPIC`, the
shared object cannot be linked, so `make install` fails. This document
is what that implies, read from the source and tried on 2026-10-31, the
plan for a `-no-shared-library` option, and how pofltk decides when to
use it. Nothing here is implemented yet. Its entry in `PLAN.md` is
"Ongoing implementation enhancements", 10.

## What happens now

- `LLVMToolchainDriver.BuildLibrary` runs `ar`, then `clang -shared`. A
  failure of the second leaves a `lib<name>.a`, but `Poc.BuildLibrary`
  writes the manifest only after both, so the archive cannot be used.
- So pofltk fails at `poc -library`, before `-install-library` runs. An
  option that only limits what is installed would not help.
- `InstallLibrary` names `lib<name>.a` and the shared library to one `cp`.
  With the shared library missing, `cp` copies the other files and fails,
  and poc reports the install failed, leaving a partial install.
- A library's shared object links the libraries it needs with `-L` and
  `-l`, and so does a program under `-shared-libraries`
  (`LLVMToolchainDriver.AddLibrary`). Where the directory has no shared
  library, the linker takes `lib<name>.a` from it without a word.

Static FLTK is not itself the problem: `clang -shared` fails on objects
that are not position-independent. All four failing hosts have FLTK built
from source and installed in `/usr/local/sw/versions/fltk/1.4.5`, with
no shared libraries.

## What an archive-only library implies

1. **The manifest must say so.** A line `no-shared`, read into
   `Libraries.LibraryDesc`. No older library needs handling, because a
   library from another poc version is refused anyway.

2. **`-install-library` copies only what exists**, and deletes the shared
   library of a copy installed before.

3. **A stale shared library must go.** `BuildLibrary` deletes only the old
   archive. If a library that had a shared object is rebuilt without one,
   `-l<name>` would find the old one, with the old code. The build and the
   install must both delete it.

4. **A library with a shared object cannot need one without.** This is the
   serious case, because today nothing stops it. In the experiment, with
   `A`'s shared library deleted, `poc -library B` (`B` imports `A`)
   succeeded, and `libB.so` then defined `A.Bump` and `A.count`: it held
   its own copy of `A`. The program printed the right answer only because
   its references to `A` resolved to that one copy. poc must refuse this
   and name the library. The reverse, an archive-only library needing one
   with a shared object, is fine. pofltk's other libraries all import
   `pofltk`, so all of them need the option wherever `pofltk` does.

5. **`-shared-libraries` decides library by library.** The experiment also
   showed a static library linking beside a shared `poc-rtl` and running.
   That should be done on purpose, not through the linker's fallback:
   - name the archive by path, with no `-L`, `-l` or run-time search path;
   - apply `lib.lto & ~shared` (`LLVMBackEnd.PrepareLibraries`) per
     library, or an archive-only LTO library is linked without `-flto`;
   - warn. A program that asks for shared libraries and gets an archive
     can behave differently: pofltk's plugins need the program to share
     its modules, by `-shared-libraries` or `-link -rdynamic`, or
     `PluginAt` gives NIL. Against an archive-only pofltk only `-link
     -rdynamic` will do.

6. **Link mistakes are found later.** `clang -shared` is the only step of
   a library build that resolves `-link`'s arguments: `-link -lnosuchlib`
   fails there. Archive-only, the first program to link finds it.

7. **Nothing else changes.** Objects stay `-fPIC`, so they are the same
   either way, and module keys do not change. A library's `-g` copy has
   its own manifest and is built by its own command. `poc-rtl` keeps both
   forms.

## Why not shared-only

A library with no archive fixes no failure: `ar` does not resolve
anything, so it cannot fail the way the shared link does. It would cost
more, too: a program links archives by default, so that default would
need its own fallback, and `-static` and an `-lto` link would have to
refuse such a library. Leave it out until something needs it.

## Why not automatically

poc could try the shared link and carry on without it when that fails.
It cannot tell an FLTK that is not position-independent from a misspelt
`-link`, so a real error would become a library that differs from host
to host. The choice stays with the library's maker. poc can still help:
"building library X failed" should say that `-no-shared-library` exists
when the failing step is the shared link.

## How pofltk decides

poc cannot know this, because it sees only `-link -lfltk`. pofltk can, and
it can find out as it builds, so no host needs naming: what matters is
the FLTK `FLTK_CONFIG` names, not the machine. The rule is **pass the
option when FLTK's directory has no `libfltk.so*`**, the test `HAVE_GL`
already makes for `libfltk_gl`.

The test, run through `gmake` on 2026-10-31 with each host's real
`fltk-config`:

| Host | FLTK | `libfltk.so*` | Option | Shared link of a probe that uses FLTK |
|---|---|---|---|---|
| atla | Fedora's | yes | no | links |
| artos | pkgsrc's | yes | no | fails, "cannot find -lpng"; with `-lpng` filtered, only a probe using nothing from FLTK was tried, and it links |
| yishana | pkgsrc's | yes | no | fails; not rerun with `-lpng` filtered |
| cymoril | own build | no | yes | fails, `R_386_GOTOFF` |
| jherek | own build | no | yes | fails, `R_X86_64_PC32` |
| alerik | own build | no | yes | fails, `R_X86_64_32` |
| rackhir | own build | no | yes | fails, `R_AARCH64_ADR_PREL_PG_HI21` |

The test agrees with `AGENTS.md`'s list of which hosts install.

**Why not a trial link instead.** It looks more direct, but:

- A probe that uses nothing from FLTK links on all four failing hosts,
  because the linker pulls no member from an archive that nothing needs.
  It must call into FLTK.
- It needs exactly the filtered flags. With `fltk-config`'s own, the probe
  failed on artos and yishana. On artos the cause was confirmed: "cannot
  find -lpng", the pkgsrc problem pofltk filters out. That would have
  wrongly said "no shared library".
- It answers the wrong question. A static FLTK built with `-fPIC` would
  pass, and its code would go into `libpofltk.so`, with the copies
  problem of item 4 again.

**Finding `fltk-config`.** On the four hosts with their own FLTK it is in
`/usr/local/sw/versions/fltk/1.4.5/bin`, which is not on `PATH`, and today
each `make` there is given `FLTK_CONFIG=` by hand. The detection depends on
it: with no `fltk-config`, `FLTK_LIBDIR` is empty, the wildcard matches
nothing, and the test says "no shared library" for the wrong reason. In
practice `tests` would fail first, on the missing headers, but with a poor
message. So the makefile should look in that directory itself, and stop if
it finds nothing:

```make
FLTK_CONFIG ?= $(firstword $(shell command -v fltk-config 2>/dev/null) \
                 $(wildcard /usr/local/sw/versions/fltk/*/bin/fltk-config))
ifeq ($(strip $(FLTK_CONFIG)),)
  $(error no fltk-config on PATH or in /usr/local/sw/versions/fltk; give FLTK_CONFIG=...)
endif
```

`PATH` comes first, so a system's own FLTK wins, as now, and `FLTK_CONFIG=`
still overrides both. The option then follows `FLTK_LIBDIR`:

```make
# poc's shared object can't hold an FLTK of static libraries. Overridable,
# either way: POC_LIBRARY_FLAGS= tries the shared link regardless.
POC_LIBRARY_FLAGS ?= $(if $(wildcard $(FLTK_LIBDIR)libfltk.so*),,-no-shared-library)
```

The same value goes to all four `-library` commands, as item 4 requires.
`-no-shared-library` is harmless on a library that could have had a shared
object.

**A way that needs no poc change.** Those four FLTKs are the user's own,
so building them with CMake's `FLTK_BUILD_SHARED_LIBS` would make `make
install` work there today. It does not solve the general case, of someone
else's static FLTK, and that was the reason for this work.

## Plan

Each step is checked on atla, cymoril, artos and alerik before it is
committed.

1. **The option and the manifest** (`src/driver/Poc.Mod`,
   `src/driver/Libraries.Mod`, and `LLVMBackEnd` in both `src/driver/llvm`
   and `src/driver/no-llvm`).
   - `-no-shared-library`, valid only with `-library`. Any other command
     refuses it, and so does `-target vax-dec-vms`: a shareable image
     can be left out when a VMS library needs that.
   - `no-shared` in the manifest, read and written; the header comment of
     `Libraries.Mod`.

2. **The build** (`LLVMToolchainDriver.BuildLibrary`). With the option,
   stop after `ar` and delete any `SharedLibraryName` file in the directory.
   Without it, when the shared link fails, add the hint from "Why not
   automatically".

3. **The refusal** (`Poc.BuildLibrary`). After `PrepareLibraries`, and only
   when building a shared object, go through `Libraries.linkOrder` and
   refuse a library with `no-shared`:
   `poc: library B's shared library cannot link library A, which has
   none: build B with -no-shared-library`.

4. **Install** (`Poc.InstallLibrary`). Copy the shared library only when
   the manifest has one; delete the old copy's otherwise.

5. **Programs** (`LLVMBackEnd.PrepareLibraries`). Pass `shared &
   ~lib.noShared` to `AddLibrary`, make the `ltoLink` test per library, and
   warn once for each library `-shared-libraries` cannot honour. Only for a
   program's link; `Poc.BuildLibrary` calls `PrepareLibraries` too.

6. **Tests.** A new fixture, `llvm-library-no-shared`:
   - an archive-only library builds, installs, has no `.so` (on OpenBSD,
     no `.so.0.0`), and links a program;
   - rebuilt from a library that had one, the `.so` is gone, from the
     build and from an install over it;
   - `-shared-libraries` links it, warns, and gives a program with no
     run-time dependency on it, beside a shared `poc-rtl`;
   - a library with a shared object needing it is refused;
   - an archive-only library needing a shared one builds;
   - with `-lto`, the program links;
   - `-no-shared-library` without `-library`, and for the VAX, is refused.

   Listings go through `LC_ALL=C sort`, and the fixture's `.gitignore` is
   written with it.

7. **Documents.** `-help` (fixture `poc-usage`), `doc/poc.1`, the
   User's Guide's library section, the Reference Guide's options table,
   file list and manifest table, `llvm-toolchain.md`, and the toolchain
   section of `AGENTS.md`. The entry in `PLAN.md` marked `[done]`.

8. **Release**, as `DEVELOPER.md` section 7 says. pofltk needs a released
   poc for its hosts.

9. **pofltk**, in its own repository:
   - the `FLTK_CONFIG` default and the `POC_LIBRARY_FLAGS` line above, and
     the flags on all four `-library` commands;
   - an error when `POC_LIBRARY_FLAGS` is set and poc is older than the
     release, as the `POC_VERSION` check at the top does. Only then, so
     hosts with a shared FLTK can keep an older poc;
   - `make install` on all seven hosts, then a program built from each
     installed library on a static host, and a plugin program with `-link
     -rdynamic`;
   - the notes in `README.md` and `AGENTS.md` that say installing fails.

   Noticed in passing: `uninstall` removes `lib*.so` but not OpenBSD's
   `lib*.so.0.0`, which matters if an OpenBSD host ever has a shared FLTK.

## Not yet known

Nothing has yet linked a program against a pofltk library made only of
archives on a static host, because such a library cannot be built today.
`make test` shows the flags link there, but from objects rather than
through a manifest. Link order should suit: libraries go in `linkOrder`,
each before what it needs, then the recorded `-link` arguments, so
`-lfltk_forms` comes before `-lfltk`. Step 9 is what proves it.
