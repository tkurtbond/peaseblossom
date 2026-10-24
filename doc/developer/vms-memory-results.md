# poc's Memory on VAX/VMS

2026-10-23. A summary of the work in `doc/developer/vms-memory.md`,
whose Results sections hold every figure here.

## Summary

poc compiling itself on the SIMH VAX now peaks at 31,791 pages (15.5 MB)
of virtual memory, down from 212,289 pages (103.7 MB): 15% of where it
started. Its peak working set fell from 200,000 pages (97.7 MB, the
whole of its extent) to 26,924 pages (13.1 MB).

Page faults fell from about 1.8 million to 52,507, and CPU time from
about 1,510 s to 791 s. The compilation takes 13.3 minutes where it took
26. Every run reached the bootstrap's fixed point: V2 wrote the same
objects as V1.

The gains came from four changes: identifiers interned (step 4), each
procedure encoded as it is written (step 6), each module checked as it
is written (step 5), and a smaller heap growth factor (step 7, item 1).
Pages are VMS's 512 bytes, so 2,048 pages make 1 MB.

## The starting point

Before the work, poc's working set filled its whole extent of 200,000
pages, so it paged against its own limit. The figures are step 3's two
runs with `LIB$GET_VM`, the runtime's way then and now:

| measure                             | before the work                            |
|-------------------------------------|-------------------------------------------:|
| compilation, elapsed                | 25.7-26.0 min                              |
| CPU                                 | 1,506-1,520 s                              |
| page faults                         | 1.73-1.81 million                          |
| peak virtual memory                 | 212,289 pages (103.7 MB)                   |
| peak working set                    | 200,000 pages (97.7 MB), all of `WSEXTENT` |
| the guest's run, transfers included | 29 min                                     |

The heap is bounded by the process's paging file quota, so an account
with a smaller `PGFLQUOTA` could not run poc at all: `POC2`'s trapped
with `%X10000022` until its quota was raised to `POC`'s.

On the hosts (step 1, cymoril, OpenBSD i386, the VAX's pointer size),
poc compiling all of itself peaked at 162.8 MB resident. Its census
found 97.4 MB live at the peak, in a heap grown to 196 MB. About 70 MB
of the 75.8 MB live after checking was unused identifier space: every
name was an array of 255 characters held inline in its record.

## How it was measured

On the guest, `tools/bootstrap/vax-stages -to v2` runs on a SIMH
MicroVAX 3900 under VMS 5.5-2H4. `POC.EXE` from stage V1 compiles all of
poc's source (44 modules) to objects, `-OC`, and the script logs that
process's `VIRTPEAK`, `WSPEAK` and `PAGEFLTS` and its CPU time. MB here
is pages / 2,048.

On the hosts, `tools/bench/poc-memory.sh` runs a Stage 2 poc writing VAX
objects, for all of poc and for each module alone, and reports the peak
resident size. `POC_MEMORY_CENSUS=1` makes poc report the live data by
record type at fixed points.

The guest was measured before step 4 and after steps 4, 6, 5 and 7;
steps 4a-4d were measured on the hosts only. A small change in what poc
allocates moves when the collector runs, so one module's figure can rise
by a megabyte when nothing it holds has grown.

## The steps

The steps are listed in the order they were made, which is why step 6
comes before step 5. Host figures are cymoril's peak resident size for
all of poc; guest changes are against the guest run before.

### Step 1: measure (2026-10-22)

Added `MemoryCensus` and `tools/bench/poc-memory.sh`, and took the
starting figures above. The census showed identifiers held about 90% of
the front end's data, so they came first.

### Step 4: intern the names (2026-10-22 to 10-23)

A new module, `Names`, keeps one copy of each identifier's text; records
hold a pointer to it, and names compare by pointer. Done in four parts:

- **4a**, `SymbolTable`'s objects: 162.8 to 131.6 MB.
- **4b**, the syntax tree, where `Designator` fell from 28.4 MB to 1.7
  MB: to 67.8 MB.
- **4c**, `Types`' fields, parameters, methods and records: to 45.1 MB.
- **4d**, a literal's text sized to fit instead of 256 characters: to
  40.6 MB.

**4e** measured the guest. Virtual memory fell 38%, the working set 40%,
page faults 78% and CPU time 37%. The working set no longer fills its
extent, so poc stopped paging against its own limit.

### Step 6: encode each procedure as it is written (2026-10-23)

The VAX back end turned each procedure's instruction lines into bytes at
the end of the module, so every line of the module was held at once. Now
each procedure is encoded when it is finished and its lines are let go.
Host: 40.6 to 34.3 MB, with `VaxCodeGenerator` alone down 28%. Guest:
virtual memory -43%, working set -42%, page faults -55%, CPU -12%.

### Step 5: check each module as it is written (2026-10-23)

poc checked every module before writing any, so all the syntax trees
were live together. Now it reads every module's interface first, then
parses, checks and writes one module at a time, letting its tree go.
Host: 34.3 to 17.9 MB. Guest: virtual memory -52%, working set -56%,
page faults -64%. CPU barely moved (-1%), because each module is now
parsed twice.

### Step 7, item 5: the relocation sort (2026-10-23)

`VaxImage`'s three sorts now return a list that is already in order
without sorting it. Output is unchanged. Guest CPU fell 8%. Memory rose
(virtual +11%, working set +15%), though the sort allocates nothing: the
change moved when the collector runs.

### Step 7, item 1: the growth factor (2026-10-23)

After a collection the VAX collector grew the heap to twice the live
data; now it grows it to 1.5 times (`growthDivisor` in
`rtl/vax/GarbageCollectedHeap.Mod`). The host runtime keeps 2. Host
(scratch build, item 5's tree): 18.6 to 14.8 MB. Guest, in the tree:
virtual memory -19%, working set -22%, page faults -32%, CPU +3%.

Factors 2, 1.5 and 1.25 were tried on the guest:

| factor | CPU   | page faults | peak virtual memory    | peak working set       |
|--------|------:|------------:|-----------------------:|-----------------------:|
| 2      | 765 s | 77,356      | 39,202 pages (19.1 MB) | 34,694 pages (16.9 MB) |
| 1.5    | 794 s | 49,764      | 30,560 pages (14.9 MB) | 25,727 pages (12.6 MB) |
| 1.25   | 803 s | 43,800      | 28,337 pages (13.8 MB) | 22,990 pages (11.2 MB) |

1.25 saved only 7% more virtual memory than 1.5, and leaves less room
before the next collection, so 1.5 was chosen.

## Comparison across the steps

Each of the four changes cut the peaks; only the relocation sort, which
allocates nothing, moved them up, by shifting when the collector runs.
On the guest, `vax-stages -to v2`:

| after          | peak virtual memory      | peak working set         |
|----------------|-------------------------:|-------------------------:|
| Start          | 212,289 pages (103.7 MB) | 200,000 pages (97.7 MB)  |
| Step 4         | 130,994 pages (64.0 MB)  | 119,344 pages (58.3 MB)  |
| Step 6         |  74,128 pages (36.2 MB)  |  69,566 pages (34.0 MB)  |
| Step 5         |  35,412 pages (17.3 MB)  |  30,275 pages (14.8 MB)  |
| Step 7, item 5 |  39,202 pages (19.1 MB)  |  34,694 pages (16.9 MB)  |
| Step 7, item 1 |  31,791 pages (15.5 MB)  |  26,924 pages (13.1 MB)  |

The other guest measures at the same points:

| after          | compilation, elapsed | CPU           | page faults       |
|----------------|---------------------:|--------------:|------------------:|
| Start          | 25.7-26.0 min        | 1,506-1,520 s | 1.73-1.81 million |
| Step 4         | 16.2 min             | 961 s         | 389,481           |
| Step 6         | 14.2 min             | 844 s         | 174,605           |
| Step 5         | 14.0 min             | 832 s         | 62,303            |
| Step 7, item 5 | 12.9 min             | 765 s         | 77,356            |
| Step 7, item 1 | 13.3 min             | 791 s         | 52,507            |

Against the start, poc now needs 15% of the virtual memory, 13% of the
working set, 3% of the page faults and 52% of the CPU time.

## On the hosts: cymoril and atla

poc compiling all of itself for the VAX now peaks at 14.8 MB resident on
cymoril, 9% of the 162.8 MB it started at, and at 21.0 MB on atla, 12%
of 170.5 MB. Each figure is the peak resident size in MB of a Stage 2
poc writing VAX objects, `-OC` (`tools/bench/poc-memory.sh`): all of poc
as one program, then the seven largest modules compiled alone. cymoril
is OpenBSD i386, the VAX's pointer size; atla is Fedora x86_64.

cymoril:

| run                        | start | 4a    | 4b   | 4c   | 4d   | 6    | 5    | item 5 | item 1 |
|----------------------------|------:|------:|-----:|-----:|-----:|-----:|-----:|-------:|-------:|
| all of poc, one program    | 162.8 | 131.6 | 67.8 | 45.1 | 40.6 | 34.3 | 17.9 | 18.6   | 14.8   |
| `Poc` alone                | 113.4 |  94.0 | 37.8 | 29.7 | 26.3 | 25.8 | 11.9 | 11.9   | 10.9   |
| `VaxCodeGenerator` alone   | 112.9 |  79.4 | 43.7 | 40.2 | 36.0 | 25.9 | 16.8 | 16.6   | 13.8   |
| `VaxToolchainDriver` alone |  82.1 |  68.6 | 23.5 | 17.5 | 15.8 | 16.8 | 11.5 | 11.5   |  9.8   |
| `SemanticActions` alone    |  53.2 |  46.8 | 22.1 | 19.8 | 18.6 | 14.6 |  9.4 |  9.5   |  8.7   |
| `Parser` alone             |  52.2 |  41.5 | 16.6 | 12.6 | 11.9 | 12.5 |  8.2 |  8.2   |  7.8   |
| `NestedProcedures` alone   |  44.4 |  38.9 | 14.2 | 11.0 | 10.2 | 10.6 |  8.2 |  8.2   |  7.2   |
| `ModuleInterface` alone    |  35.9 |  27.4 | 13.1 | 11.9 | 11.1 | 10.3 |  6.4 |  6.4   |  6.0   |

The item 1 column is a scratch build with `rtl/llvm`'s growth factor set
to 1.5, to stand in for the VAX's; the item 5 column is the same tree
with the factor at 2. In the tree, the hosts' runtime keeps 2, so item 1
does not change poc on the hosts.

atla:

| run                        | start | 4a    | 4b   | 4c   | 4d   | 6    | 5    |
|----------------------------|------:|------:|-----:|-----:|-----:|-----:|-----:|
| all of poc, one program    | 170.5 | 140.9 | 87.5 | 68.4 | 80.5 | 45.5 | 21.0 |
| `Poc` alone                | 104.1 |  94.6 | 46.3 | 37.5 | 34.1 | 32.9 | 13.8 |
| `VaxCodeGenerator` alone   | 100.7 |  89.9 | 54.3 | 50.1 | 49.2 | 33.0 | 19.9 |
| `VaxToolchainDriver` alone |  76.8 |  66.3 | 28.2 | 24.5 | 23.7 | 23.3 | 14.0 |
| `SemanticActions` alone    |  52.1 |  48.5 | 28.3 | 26.0 | 24.7 | 19.3 | 10.3 |
| `Parser` alone             |  49.5 |  39.6 | 19.3 | 16.3 | 15.2 | 15.7 |  8.0 |
| `NestedProcedures` alone   |  47.0 |  38.0 | 17.2 | 14.2 | 12.2 | 13.0 |  9.0 |
| `ModuleInterface` alone    |  33.3 |  29.4 | 15.0 | 13.9 | 12.7 | 12.5 |  6.8 |

What the steps did on the hosts:

- **Step 4** did the most: all of poc fell to a quarter on cymoril
  (162.8 to 40.6 MB), with 4b, the syntax tree, the largest part. Each
  module alone fell by about two thirds on cymoril and by half or more
  on atla.
- **4d on atla** is the one rise: all of poc went from 68.4 to 80.5 MB,
  and stayed there when run again, while the census showed less live
  data. It is when the collector ran; step 6 brought it to 45.5 MB.
- **Step 6** cut the modules with the most code most
  (`VaxCodeGenerator` by 28-33%); a module with little code moved by
  about a megabyte either way.
- **Step 5** halved all of poc on both hosts, and cut each module alone
  by a third to a half: `-compile` of one module no longer holds its
  source imports' trees, only their headers.
- **Item 5** changed no memory figure by as much as a megabyte,
  but on atla all of poc for the VAX took 0.37 s of user time instead of
  0.58 (three runs each).
- **Item 1** (scratch) cut cymoril's all of poc by a further 20%.

The census (`POC_MEMORY_CENSUS=1`, all of poc) shows the live data and
the heap at poc's largest point, while `VaxCodeGenerator` is written,
in MB:

| after | live | heap | host    |
|-------|-----:|-----:|---------|
| start | 97.4 | 196  | cymoril |
| 4a    | 82.8 | 165  | cymoril |
| 4b    | 41.4 | 58.7 | cymoril |
| 4c    | 35.5 | 65.3 | cymoril |
| 4d    | 33.4 | 55.2 | cymoril |
| 6     | 11.5 | 24.8 | cymoril |
| 5     | 7.76 | 19.2 | atla    |

4c's heap is larger than 4b's for the same reason as 4d's rise on atla:
when the collector ran. The heap is about twice the live data after a
collection that leaves less than half of it free, which is what item 1
changed on the VAX.

## Tried and dropped, and what remains

Two steps were experiments that are not in the tree, and three of step
7's proposals were not taken:

| idea | outcome |
|------|---------|
| Step 2: identifiers cut to 31 characters | A scratch build only. It halved poc's memory on the hosts (162.8 to 81.0 MB), which showed what interning (step 4) would be worth without limiting names. |
| Step 3: heap chunks from `$EXPREG` instead of `LIB$GET_VM` | Saved 4-8% of page faults and nothing of the peaks, but cost 63% more CPU (about 2,490 s instead of 1,510 s). Dropped. |
| The start map as bits instead of bytes | About 0.8 MB (5%) at the peak, but it slows `FindBlock`, which every pointer passes through. Held back unless more memory is needed. |
| An 8-byte granule | Saves part of 0.5 MB of rounding but doubles the start map. Dropped. |
| Mark bits in a bitmap | The sweep touches the same pages anyway, and the working set is now well inside `WSEXTENT`. Dropped. |

The main cost left is CPU: since step 5 each module is parsed and
checked twice, once for its interface and once to be written.
