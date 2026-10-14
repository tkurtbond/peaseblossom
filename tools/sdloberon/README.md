# tools/sdloberon

An SDL back end that writes Oberon-2 modules for poc from VMS's own
definitions, `SYS$LIBRARY:STARLETSD.TLB`
(`doc/developer/vms-sdl-interfaces.md`, part 2). It runs on the VAX/VMS
development system, built with VAX C; `tools/vax-sdl` builds it there
and runs it, and what it writes is committed in `rtl/vax/vms`.

- `sdloberon.c`: the back end, `SDL/NOPARSE/LANGUAGE=OBERON`. Each SDL
  `MODULE` node becomes one Oberon module: constants, with `$V_`, `$S_`
  and field offsets computed as SDL's MACRO back end computes them
  (`STARLET.MLB`); a record type for each aggregate poc can lay out as
  SDL does; a `["VMS"]` declaration for each entry, its parameters by
  part 1's mechanisms.
- `sdlload.c`: runs `sdloberon.c` on atla over an `SDLDUMP` dump of a
  tree (`tools/vax-sdl dump`), to try a change before the guest:
  `cc -m32 -std=gnu89 -o sdlload sdlload.c sdloberon.c`, then
  `./sdlload <MODULE>.DMP <MODULE>.OBN`, run where the output goes (SDL
  keeps 32 characters of the output's name).
- `sdldef.h`, `sdldump.c` and `readable.mar` are copies of the user's
  UNSDL (`~/Repos/myunsdl`, Version 1.0, Feb 4, 1988),
  unchanged: the tree's node layout, and `SDLDUMP`, which prints
  a tree. `sdl.opt` is UNSDL's link options file.

`SDL/NOPARSE` (SDL V3.2-12) loads a back end only from `SYS$SHARE`, so
the user copies `[USERS.POC.SDL]SDLOBERON.EXE` and `SDLDUMP.EXE` there
after each `tools/vax-sdl build`.
