# GC frees objects whose only reference is in a callee-saved register

<!-- Copied from ~/Repos/RPG/Tools/obesm2_fmt/VOC-GC-BUG.md (2026-10-02),
     where it was found; the reproducer is GcRepro.Mod beside this file. -->

**What it means for poc** (checked 2026-10-02 on atla): poc's own
collector (`rtl/llvm/GarbageCollectedHeap.Mod`) already does what the fix
below does: `Collect` calls `llvm.eh.unwind.init`, LLVM's
`__builtin_unwind_init`, so the reproducer built by poc prints `0 of
1000000` under `-OC` and `-O2`, where voc's build prints `752 of
1000000`. Stage 0, poc as voc builds it, runs on voc's collector, and
is protected since 2026-10-02: `tools/bootstrap/stage0` links it with
`tools/bootstrap/voc-heap-gc-spill.c`, a `Heap_GC` that stores the
callee-saved registers in its own frame (`__builtin_unwind_init`) and then
calls libvoc's. The dynamic linker binds libvoc's own calls of `Heap_GC`
to it too, so this is the fix below without rebuilding voc, and it fits
whichever commit each host's voc was built from. The reproducer, linked
the same way:

| Host (voc's C compiler) | Stock, `-OC` (lengths 4/12/20/40) | With the spill |
|---|---|---|
| atla, Linux x86_64 (gcc) | 2 / 752 / 752 / 3 | 0 |
| artos, NetBSD amd64 (gcc) | 252 / 252 / 252 / 1 | 0 |
| alerik, FreeBSD amd64 (clang) | 0 | 0 |
| cymoril, OpenBSD i386 (clang) | 0 | 0 |

(Corrupted calls out of 1,000,000; the spill was called on every host.
Under `-O2`, at most 1.) clang's code for the reproducer does not keep the
arguments in callee-saved registers, but nothing promises that of other
code.

The `CFLAGS` workaround at the end of this report needs gcc: clang has no
`-ffixed-<register>` for x86. With gcc, the callee-saved registers to
keep free are `rbx` and `r12`-`r15` on x86_64 and `ebx`, `esi` and `edi`
on i386 (`-ffixed-ebx -ffixed-esi -ffixed-edi`; `ebp` is the frame
pointer without optimization), and `x19`-`x28` on aarch64.

## Summary

voc's garbage collector finds roots on the stack only. `Heap.GC` tries
to push the callee-saved registers onto the stack first, using 24
local variables to create "register pressure". But voc compiles its C
without optimization, both the runtime (`libvoc-*.so`) and user code.
At that level those 24 locals are ordinary stack slots, so the trick
does nothing. A heap pointer that lives only in `rbx` or `r12`–`r15`
at the moment of a collection is not seen, and its block is freed
while still in use.

gcc keeps pointers there when it evaluates a call whose arguments are
themselves allocating function calls. For example:

```oberon
Check(Make("aaaa"), Make("bbbb"), Make("cccc"))
```

gcc keeps the first finished argument in a callee-saved register while
it evaluates the others. If one of those later `NEW`s starts a
collection, the finished argument is freed. The callee then reads a
block that has already been reused.

`__builtin_unwind_init()` at the start of the stack-marking branch of
`Heap.GC` fixes it. A patch and test results are below.

## Environment

- voc 2.1.0 [2026/09/18], built from commit `552eade0`. `Heap.GC` and
  `Heap.MarkStack` are the same on current `master`.
- Fedora, Linux 7.2, x86-64 (i9-13900HX).
- gcc 16.2.1 20260819. voc's cc command is `gcc -fPIC -g
  -Wno-stringop-overflow -std=gnu11`, with no `-O`.
  `libvoc-OC.so`'s DWARF producer string confirms the runtime is built
  the same way: `-g -std=gnu11 -fPIC`.
- Seen with the `-OC` size model and, less often, with `-O2`.

## Reproducer

`GcRepro.Mod`:

```oberon
MODULE GcRepro; (* voc's GC frees a pointer held only in a callee-saved register *)

IMPORT Out;

TYPE String = POINTER TO ARRAY OF CHAR;

VAR bad, i: LONGINT;

PROCEDURE Make(s: ARRAY OF CHAR): String;
  VAR p: String;
BEGIN NEW(p, LEN(s)); COPY(s, p^); RETURN p
END Make;

PROCEDURE Check(a, b, c: String);
BEGIN
  IF (a^ # "aaaaaaaaaaaa") OR (b^ # "bbbbbbbbbbbb") OR (c^ # "cccccccccccc") THEN
    INC(bad);
    IF bad <= 3 THEN
      Out.String("a = "); Out.String(a^); Out.String(", b = "); Out.String(b^);
      Out.String(", c = "); Out.String(c^); Out.Ln
    END
  END
END Check;

BEGIN
  bad := 0;
  FOR i := 1 TO 1000000 DO Check(Make("aaaaaaaaaaaa"), Make("bbbbbbbbbbbb"), Make("cccccccccccc")) END;
  Out.String("calls with a corrupted argument: "); Out.Int(bad, 0); Out.String(" of 1000000"); Out.Ln
END GcRepro.
```

```console
$ voc -OC GcRepro.Mod -m && ./GcRepro
a = aaaaaaaaaaaa, b = bbbbbbbbbbbb, c = <8 bytes of garbage: F8 FF FF FF FF FF FF FF>
a = aaaaaaaaaaaa, b = bbbbbbbbbbbb, c = <the same>
a = aaaaaaaaaaaa, b = bbbbbbbbbbbb, c = <the same>
calls with a corrupted argument: 752 of 1000000
```

Every correct program should print `0 of 1000000`. The result is the
same on every run. How often it happens depends on the allocation
sizes, because they decide when a collection starts:

| String length | `-OC` | `-O2` |
|---|---|---|
| 4 | 2 | 0 |
| 12 | 752 | 0 |
| 20 | 752 | 0 |
| 40 | 3 | 1 |
| 100 | 0 | 0 |

(Corrupted calls out of 1,000,000.)

The `-O2` model generates the same code for the call (see below), so it
is exposed in the same way. Its heap layout just makes collections
land in the window less often.

## What happens

voc generates:

```c
GcRepro_Check(GcRepro_Make((CHAR*)"aaaaaaaaaaaa", 13), GcRepro_Make((CHAR*)"bbbbbbbbbbbb", 13), GcRepro_Make((CHAR*)"cccccccccccc", 13));
```

gcc evaluates the arguments right to left and keeps each result in a
callee-saved register until `Check` is called (from `objdump -d` of the
`-OC` build):

```
call  GcRepro_Make        ; "cccc..."
mov   %rax,%r12           ; c lives only in r12
call  GcRepro_Make        ; "bbbb..."  -- may run the GC
mov   %rax,%rbx           ; b lives only in rbx
call  GcRepro_Make        ; "aaaa..."  -- may run the GC
...                       ; then Check(rax, rbx, r12)
```

While `b` and `a` are being allocated, `c` is referenced only from
`r12`. A collection at that point misses it, for these reasons:

1. `Heap.MarkStack` scans from its own frame up to
   `Modules_MainStackFrame`. It never looks at registers.
2. `Heap.GC`'s register-pressure code (`i0` … `i23`) is meant to force
   the callee-saved registers into its frame. Without optimization,
   gcc gives each of those variables a stack slot and uses no
   callee-saved register for them. `Heap_GC`'s prologue in
   `libvoc-OC.so` saves only `rbp`.
3. No other function on the path from `NEW` to the stack scan saves
   `r12`–`r15`. In `libvoc-OC.so` the only `Heap_`/`SYSTEM_`
   functions that push a callee-saved register are `Heap_Sift`, which
   pushes `rbx`, and `Heap_Sift` runs after the scan, deeper in the
   stack. `main` does push `r12` and `rbx` in its prologue, but those
   are its caller's values, saved before `c` is stored in `r12`.

So the block holding `c` is unmarked and freed. The next allocations
reuse it, and `Check` reads what they wrote there.

Valgrind reports nothing, because the freed block is inside voc's own
heap chunk, not memory that valgrind tracks.

This was found in a real program: an Oberon-2 port of a YAML-to-text
formatter. About 1 table header cell in 400 came out as garbage on
inputs large enough to trigger many collections. The cell was always
the argument that gcc evaluates first in a call like
`Row3(H("LEVEL"), H("POINTS"), H("ATTRIBUTE"))`.

## Fix

Store all callee-saved registers in `GC`'s own frame before
`MarkStack` runs. `MarkStack` then scans that frame. gcc and clang both
provide `__builtin_unwind_init()` for exactly this: it makes the
function save every callee-saved register in its prologue.

```diff
--- a/src/runtime/Heap.Mod
+++ b/src/runtime/Heap.Mod
@@ -551,6 +551,10 @@
 
 
 
+  (* Stores every callee-saved register in the caller's frame, where
+     MarkStack will find any pointer held only in one. *)
+  PROCEDURE -SaveRegisters "__builtin_unwind_init()";
+
   PROCEDURE GC*(markStack: BOOLEAN);
     VAR
       m: Module;
@@ -565,6 +569,7 @@
       m := m^.next
     END;
     IF markStack THEN
+      SaveRegisters;
       (* generate register pressure to force callee saved registers to memory;
          may be simplified by inlining OS calls or processor specific instructions
       *)
```

How this was tested, without rebuilding or reinstalling voc:

1. Compiled the patched `Heap.Mod` with `voc -OC -s`.
2. Compiled the resulting `Heap.c` with voc's usual flags.
3. Linked `Heap.o` into the reproducer ahead of `-lvoc-OC`, so that its
   `Heap_*` symbols override the shared library's.

Results:

| Build | Corrupted calls |
|---|---|
| Stock runtime | 752 of 1,000,000 |
| Unpatched `Heap.c`, linked the same way (control for the method) | 752 of 1,000,000 |
| Patched `Heap.Mod` | 0 of 1,000,000 |

After the patch, `Heap_GC`'s prologue pushes `rbp`, `r15`, `r14`,
`r13`, `r12` and `rbx`.

The register-pressure loop can probably be removed once
`SaveRegisters` is in place. I haven't tested that.

`__builtin_unwind_init` exists in gcc and clang only. For a C compiler
without it, the usual portable alternative is `setjmp` into a local
`jmp_buf` in `GC` before calling `MarkStack`. glibc's x86-64 `setjmp`
stores `rbx` and `r12`–`r15` unmangled; only `rbp`, `rsp` and the
return address are mangled. I have not tested this alternative.

## Workaround for users until it's fixed

Keep gcc from using the callee-saved registers in user code. voc
appends `$CFLAGS` to its cc command, so on x86-64:

```sh
export CFLAGS="-ffixed-rbx -ffixed-r12 -ffixed-r13 -ffixed-r14 -ffixed-r15"
```

With this, the reproducer prints `0 of 1000000`, and the program where
the bug was found produces the same output as its reference on inputs
of 2,000 and 5,000 entities. Without it, 12 of 24 such runs differed.
It doesn't protect code inside `libvoc` itself, which is already
compiled.

## Possibly related

#72, "Garbage Collection - causing problems": intermittent crashes and
wrong behaviour in a large program, closed without a diagnosis in the
thread.
