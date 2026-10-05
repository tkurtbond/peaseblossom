# Collector performance

How fast the LLVM backend's collector (`rtl/llvm/GarbageCollectedHeap.Mod`)
is, what changed it, and how to measure it again. The design is in the
module's header comment; each change below has its row in
`doc/history/phase-11-inventory.md`.

## Measuring

`tools/bench/gc-compare.sh <old-tree> <new-tree>` compares the collectors of
two checkouts, each with its Stage 1 poc built (`make check` or
`tools/bootstrap/stage1`). An older commit is easiest as a worktree:

    git worktree add ../poc-old <commit>
    (cd ../poc-old && make stage1)
    tools/bench/gc-compare.sh ../poc-old .
    git worktree remove ../poc-old

It runs two workloads 7 times each (`-runs n` for more), alternating the
trees, and reports medians of wall time, user time and peak memory. Where
perf works it adds the instructions and cycles of one more run; on atla,
whose i9-13900HX has two kinds of cores, that run is pinned to a performance
core, since a process moving between the kinds is counted only in part by
each. Each workload's output must be the same for both trees.

- **gcbench**: `tools/bench/GcBench.mod`, built by each tree's poc against
  its own `rtl/llvm`. Binary trees (one node size, the live set rebuilt many
  times), then two million `NEW(b, n)` with `n` mostly 1..200 bytes and one in
  eight 256..4,255, keeping 4,096 of them live in a ring. Nearly all its time
  is allocation and collection. It needs `-OC` (its random-number constant
  does not fit `-O2`'s `LONGINT`), which the script passes.
- **poc-ir**: each tree's Stage 1 poc emitting the LLVM IR for the old tree's
  own source, the core of a Stage 1 build. About two thirds of its time was
  the collector before D14.

Run it on a quiet machine: the BSD test VMs share atla's CPUs, and a run
while they build adds noise.

## History

The Stage 1 poc emitting the IR for its own source, on atla:

| Change | Time | What changed |
|---|---|---|
| before A15 (2026-09-25) | 10.9 s | `ChunkOf` walked the chunk list for every word the marker examined (87% of the run in callgrind) |
| A15, first step | 2.7 s | `ChunkOf` binary-searches a sorted chunk table, after a range test over the whole heap |
| D13 | 1.0 s | poc built by clang at `-O2`, which inlines the collector's one-line helpers |
| D14 | 0.49 s | the heap grows geometrically: 172 collections became 14; peak memory 52 MB -> 60 MB |
| D17 | 0.59 s | nothing in the collector: field initializers made the Stage 1 poc's allocation pattern walk the first-fit free list further (`TakeFromFreeList` 20% -> 29% of cycles) |
| D15 | 0.42 s | free lists per size class |

(From D17 on the source compiled is ae4e51f's, the same for every compiler;
before it, each compiler's own.)

## D15: free lists per size class (2026-09-26)

Before D15 the collector kept one first-fit free list: an allocation walked
it from the front until a block was big enough, about 58 blocks on average
in the Stage 1 poc after D14. Now each block size up to 512 bytes (in
16-byte granules) has its own list and bigger blocks share one first-fit
list; an allocation takes the first block of its size's list, or splits one
from a larger class or the big list.

`tools/bench/gc-compare.sh` with c192cdc (before) and D15 (after), atla,
quiet, medians of 7 runs:

| Workload | Tree | Wall | User | Peak MB | Instructions | Cycles |
|---|---|---|---|---|---|---|
| gcbench | c192cdc | 1.71 s | 1.70 s | 16.2 | 11.30 G | 8.93 G |
| gcbench | D15 | 0.50 s | 0.49 s | 16.2 | 9.66 G | 2.45 G |
| poc-ir | c192cdc | 0.58 s | 0.55 s | 64.8 | 5.86 G | 2.74 G |
| poc-ir | D15 | 0.42 s | 0.40 s | 65.2 | 5.50 G | 1.92 G |

gcbench runs 3.4 times as fast, poc 1.4 times; peak memory is the same. The
instructions fall much less than the time (15% and 6%): the old walk was
bound by memory, not by work. Each step of it read the header of a free
block somewhere else in the heap, and in gcbench missed the cache 8.4 M
times against 0.6 M with D15. In gcbench's profile `TakeFromFreeList` went
from 77% of the cycles to 12%, and the rest is now spread over marking
(`MarkCandidate`, `DrainMarkStack`), sweeping (`SweepChunk`) and `Allocate`.

A run of the older ad hoc script (while the BSD VMs were building, so a
little slower throughout) had poc also compile c192cdc's own source (0.64 s
-> 0.46 s) and a copy of poc's source rewritten to give 242 record fields an
initializer (0.64 s -> 0.47 s): the same gain.

What is left in poc-ir's profile is the front end (`SymbolTable.FindLocal`
9%, `SemanticActions.FindQualified` 8%) and writing the IR (`fwrite` 9%).
