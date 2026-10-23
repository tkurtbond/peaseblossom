# poc's memory on VAX/VMS

poc compiling itself on the SIMH VAX peaks at about 90 MB of virtual
memory over MACRO-32 (Phase 16, V2) and 204,483 pages (100 MB) over
objects (Phase 18, `vax-stages`), and its working set is as large as
`WSEXTENT` lets it be. Phase 16 decided (the user, 2026-10-09) that poc
should need less, then raised the guest's limits instead (2026-10-11) so
that the fixed point could be reached, leaving "making poc need less -
measuring what holds its memory, compiling module by module against
`.sym` files, leaving the LLVM backend out of the VMS image" as later
work (`doc/history/phases/phase-16.md`, "Left open"). This is that work:
what holds the memory, as read from the source on 2026-10-22, and the
plan, in order. Its entry in `PLAN.md` is "Ongoing implementation
enhancements", 8.

Already done: the VMS image has no LLVM back end (`tools/bootstrap/vax-v1`
builds it with `src/driver/no-llvm`'s `LLVMBackEnd`).

## What holds the memory (read; measured in "Results")

Phase 16 step 1 measured each module compiled alone, on 32-bit OpenBSD:
`LLVMCodeGenerator` 82 MB, `VaxCodeGenerator` 59 MB, `SemanticActions` 45
MB, `Lexer` 13 MB, about half of it live data (the collector keeps the
heap at twice the live data). These are the likely holders, largest
first; step 1 below is to measure them.

1. **Identifiers are 256-byte arrays held inline.**
   `SyntaxTree.Ident` is `ARRAY identLength + 1 OF CHAR`, `identLength =
   255`, and it is a field, not a pointer, wherever a name is kept:
   - each `DesignatorDesc` (every use of a name) has `qualifier` and
     `name`, over 512 bytes;
   - each `FieldSelectorDesc` has 256 bytes, each `LiteralExprNodeDesc`
     its `lexeme`, 256 bytes even for `0`;
   - each `SymbolTable.ObjectDesc` has `name`, `externalConvention`,
     `externalName` and `realModuleName`, over 1 KB, a constant read from
     a `.sym` (`VMSDEF`'s thousands) as much as a declared one;
   - `Types`' fields, parameters, methods and named types each hold one
     or two (`Types.Mod`, `name`, `receiverTypeName`, `moduleName`,
     `initPath`).

   A typical identifier is 5 to 15 characters.
2. **Every module's syntax tree lives until the end.** `Poc.Mod` parses
   and checks every module of a program first, then writes them all
   (`WriteVaxModules`), so all the trees are live together. A module's
   importers need its scope, not its tree.
3. **The back end holds a whole module's MACRO-32 as records.**
   `VaxInstructions` keeps a module's lines - a `LineDesc` with room for
   six specifiers, each specifier and directive item its own record, each
   name and mnemonic its own `Text` - until the module is printed or
   encoded.
4. **The collector on VMS.**
   - `POC_GET_MEMORY` (`rtl/vax/PocRtl.mar`) clears every chunk with
     `MOVC5`. New pages are demand-zero already, and `AllocateNow` clears
     each block it hands out, so the clearing only brings every page of
     the chunk into the working set and charges it to the page file at
     once; after the heap's geometric growth a chunk can be tens of MB.
     Chunks are never given back, so `$EXPREG` without clearing would do
     (tried as step 3, and dropped: it saved few page faults and cost
     much CPU; "Results").
   - The heap grows to twice the live data after a collection
     (`GrowAfterCollection`); a smaller factor trades CPU for memory.
   - Every block has two words of header (size and flags, tag) and is a
     whole number of 16-byte granules; on a 32-bit machine an 8-byte
     granule would waste less on small objects.
   - Mark bits are in the headers, so each collection writes to every
     page holding a live object; a mark bitmap would leave them clean.
5. **Outside poc.** `INSTALL /SHARED` of `POC.EXE` shares its code
   among processes, which helps the system, not one compilation.

## The plan

Each step is decided with the user before it is made, measured against
step 1's figures, and recorded here.

1. **Measure.** Without changing what poc does:
   - **a. Process peaks**, `tools/bench/poc-memory.sh`: poc compiling each
     of its own modules alone for the VAX (`-compile` against its
     imports' `.sym` files) and all of them as one program, the peak
     resident size of each (`/usr/bin/time`) on a host - cymoril, 32-bit
     like the VAX, so pointers and `SYSTEM.ADDRESS` have the VAX's size.
     On the guest, `F$GETJPI`'s `VIRTPEAK`, `WSPEAK` and `PAGEFLTS` after
     poc runs in a fresh process.
   - **b. A heap census**: `GarbageCollectedHeap.Census` (both
     collectors) collects, then reports each live block's tag and size;
     poc, with the environment variable (on VMS the logical name)
     `POC_MEMORY_CENSUS` defined, writes the census to standard error
     when the front end has checked every module and after each module
     is written, the bytes held by each record type it knows by name
     (`MemoryCensus`, which learns each type's tag from an instance), the
     rest by size.
2. **Identifiers at 31 characters, as an experiment.** `identLength = 31`
   in a scratch build, measured as in step 1, to find what item 1 is
   worth before changing ~140 declarations. Not to be committed: it
   limits identifiers.
3. **Chunks from `$EXPREG`, not cleared** (item 4, first point): small,
   all in `PocRtl.mar` and `rtl/vax/GarbageCollectedHeap.Mod`. Tried and
   dropped (2026-10-22; "Results").
4. **Identifiers interned** (item 1): `Ident` a pointer to one shared
   copy of each name, from a name table; names compared by pointer.
5. **Each module written as soon as it is checked**, its tree then
   dropped (item 2); the VAX symbol clash check (`EnterInterface`) made
   as each module is entered. And a DCL build that compiles module by
   module with `-compile`, which bounds a process by its largest module.
6. **Each routine's lines encoded and dropped** (item 3), if the object
   writer allows it (`vax-object-language.md`, the one-pass displacement
   rule).
7. **The collector's growth factor, granule and mark bits on VMS** (item
   4, the rest), as step 1's figures say they are worth it.

## Step 4's design: identifiers interned (decided, 2026-10-22)

Decided with the user, 2026-10-22: NIL for the empty name (proposal 2),
and one commit per part (proposal 6). What step 1's census says it is for: the
records that hold a `SyntaxTree.Ident` inline are about 70 MB of the 75.8
MB live once the front end has checked all of poc, and step 2 (31
characters) halved poc's peak. An identifier is typically 5 to 15
characters; interned, each use is one pointer.

1. **A new front-end module, `Names`, with the type `Name`.**
   `Name* = POINTER TO ARRAY OF CHAR`, exactly as long as the name and
   its 0X, as `Lexer.Text` and `VaxInstructions.Text` are. `Names.Intern
   (text): Name` returns the one `Name` for that text, from a hash table
   of chains (a private record per entry: the `Name`, the next entry),
   the table doubling when it holds twice as many names as chains. The
   hash is computed with `MOD` at each step, so it never overflows,
   which voc's C would not promise for Stage 0. Names are never freed:
   a program's distinct identifiers are few beside its uses of them. A `Name` comes only from `Intern` (no other module
   says `NEW` of one, which review and a `grep` check), and nothing
   writes into one, so two `Name`s are equal exactly when they are the
   same pointer.
2. **NIL is the empty name.** Records start zeroed, so a `Name` field
   nobody set is NIL, and `Intern("")` returns NIL too; `x.qualifier[0]
   = 0X` (48 places) becomes `x.qualifier = NIL`. Reading the text is
   `x.name^`, which traps (exit 4) if the name is empty, so a place that
   may hold an empty name must test first; `Names.Text(name)` is not
   proposed, since Oberon-2 cannot return an array. The alternative, a
   shared `Names.empty` that is never NIL, would need every record that
   holds a name to be set up by a procedure, and a forgotten one would
   still be NIL.
3. **Which fields become `Name`** - every record field that holds an
   identifier, the heap's share:
   - `SyntaxTree`: the designator's `qualifier` and `name`, the
     qualident type's, the field selector's `field`, the identifier
     definition's `name`, and the rest of the nodes' (`typeName`,
     `variable...`, `endName`, `alias`, `moduleName`, the external
     attribute's `externalConvention` and `externalName`);
   - `SymbolTable.ObjectDesc`: `name`, `externalConvention`,
     `externalName`, `realModuleName` (1,088 bytes each now, about 80
     with the four names interned);
   - `Types`: the field's, parameter's and method's `name`,
     `receiverTypeName`, the record type's `moduleName` and `name`,
     `messageModule`.
   Not interned: text that is not one identifier. `Types`' `initPath`
   and `LLVMCodeGenerator.DeclaredExternalDesc.name` hold qualified names
   ("Module.Name", step 2), and `LiteralExprNodeDesc.lexeme` holds a
   number's or string's text. `lexeme` (2.8 MB, 9,645 blocks) becomes a
   `Lexer.Text` sized to fit; `initPath` and the back ends' records stay
   `Ident` unless the census after 4c shows them worth changing.
4. **Lookups by pointer.** `SymbolTable.FindLocal`, `Find` and `Insert`,
   `Types.FindField`, `FindMethod`, `FindOwnMethod`, `FindOverridable`,
   `MethodSlots.MethodSlot` and the like take a `Name` and compare
   pointers. `FindLocal` walks a scope's list comparing 256-byte arrays
   now, and `VMSDEF`'s scopes have thousands of objects, so this should
   cut CPU as well as memory; and passing a `Name` copies 4 bytes where
   a value `Ident` copies 256.
5. **Where names are interned**: the parser's `ExpectIdent` (and
   `ParseQualident`, `ParseExternalAttribute`, which call it or read the
   lexeme), `ModuleInterface` as it reads a `.sym` file, and the few
   places that make a name (`SemanticActions.AppendBaseSuffix`,
   `NameRecordType`, the predeclared and `SYSTEM` scopes' set-up). The
   lexer is left alone: its `lexeme` is a scratch buffer, one per token.
   Procedures that build text from a name (file names, error messages,
   qualified names, the back ends' symbols) keep their `Ident` or
   `ARRAY OF CHAR` locals and take `name^`.
6. **In parts, each a change of type that the compiler then finds every
   use of**, each through `make check` and measured with
   `tools/bench/poc-memory.sh` and the census on cymoril:
   - **4a** `Names`, and `SymbolTable.ObjectDesc`'s four fields with the
     lookups of proposal 4 (16.4 MB);
   - **4b** `SyntaxTree`'s fields and the parser (about 45 MB:
     designators 28.3, qualident types 7.0, identifier definitions 4.7,
     field selectors 2.5);
   - **4c** `Types`' fields (parameters 4.2 MB, fields, methods, record
     types);
   - **4d** `LiteralExprNodeDesc.lexeme` as a `Lexer.Text`;
   - **4e** the guest: `vax-stages -to v2` with the step 3 logging
     (`VIRTPEAK`, `WSPEAK`, page faults, CPU), compared with step 3's
     `LIB$GET_VM` runs (1,506-1,520 s, 1.73-1.81 million faults), and
     the results recorded here.
   Each part changes no output: Stage 2's fixed point, every fixture,
   and the VAX objects for all of poc byte for byte the same as before
   (as step 2 checked), so no expected `.mar` needs review.
7. **Strictness and Stage 0.** `POINTER TO ARRAY OF CHAR`, `^` and
   pointer comparison are plain `Oberon2.pdf`, so `make check-strict`
   and `make check-o2` hold, and voc builds it.

## Results

### Step 1: measured (2026-10-22)

`tools/bench/poc-memory.sh -poc <Stage 2 poc>`, objects, `-OC`, the
working tree of 2026-10-22 (poc with `MemoryCensus`). Measure with a
Stage 2 poc: the Stage 0 one is voc's program, with voc's collector, and
its figures say nothing about poc's (128 MB for all of poc on atla).

**a. Peak resident size**, MB, the largest of the 44 runs:

| run                          | cymoril (i386) | atla (x86_64) |
|------------------------------|---------------:|--------------:|
| all of poc, one program      | 162.8          | 170.5         |
| `Poc` alone                  | 113.4          | 104.1         |
| `VaxCodeGenerator` alone     | 112.9          | 100.7         |
| `VaxToolchainDriver` alone   |  82.1          |  76.8         |
| `SemanticActions` alone      |  53.2          |  52.1         |
| `Parser` alone               |  52.2          |  49.5         |
| `NestedProcedures` alone     |  44.4          |  47.0         |
| `ModuleInterface` alone      |  35.9          |  33.3         |

32-bit and 64-bit are within 10% of each other: pointers are not what
fills the heap. A module compiled alone holds its imports' scopes and its
own tree; `Poc` and `VaxCodeGenerator` import nearly everything.

**b. Census** (`POC_MEMORY_CENSUS=1`, all of poc as one program, cymoril).
The census's own collections change when the heap grows, so the run's peak
is lower (111.0 MB); the live figures are what matter.

- When the front end has checked every module: 75.8 MB live in 252,782
  blocks, heap 108 MB. The records that hold `Ident`s inline:

  | type                        | MB   | blocks | bytes each |
  |-----------------------------|-----:|-------:|-----------:|
  | `SyntaxTree.Designator`     | 28.3 | 52,060 |  544       |
  | `SymbolTable.Object`        | 16.4 | 15,063 | 1,088      |
  | `SyntaxTree.QualidentTypeNode` | 7.0 | 13,265 | 528     |
  | `SyntaxTree.IdentDefNode`   |  4.7 | 16,365 |  288       |
  | `Types.Param`               |  4.2 | 14,494 |  288       |
  | `SyntaxTree.LiteralExprNode`|  2.8 |  9,645 |  288       |
  | `SyntaxTree.FieldSelector`  |  2.5 |  8,747 |  288       |
  | `Types.Field`, `ProcDeclNode`, `RecordType` | 4.4 | 9,048 | |

  about 70 MB of the 75.8, nearly all of it unused identifier space.
  Blocks without a tag (strings, arrays) are under 1 MB.
- Between modules, the back end leaves 76-85 MB live: the trees and the
  scopes, which the back end does not let go of (item 2).
- The peak is `VaxCodeGenerator`'s own module: 97.4 MB live in 570,835
  blocks, and the heap grows to 196 MB, twice the live data, for this one
  module. Its own part is `VaxInstructions.Specifier` 7.2 MB (89,486),
  `Line` 6.1 MB (76,021), the code generator's private records (tags
  `34E867D0`, `34E867B0`) 1.7 MB, `VaxImage`'s 2.5 MB, untagged blocks of
  up to 32 bytes 2.9 MB: about 21 MB for item 3.
- On the hosts the resident peak (163 MB) is below the heap (196 MB):
  pages of a chunk never touched are not resident. On VMS `POC_GET_MEMORY`
  clears each chunk, so all of it is touched (item 4).

What this says for the plan: item 1 (identifiers) is about 90% of what the
front end holds, so steps 2 and 4 come first; item 2 then bounds the rest;
item 3 is about a fifth of the peak; the heap's doubling turns the peak
module's 97 MB live into 196 MB of heap.

The guest's `VIRTPEAK`, `WSPEAK` and `PAGEFLTS` are in step 3's results.

### Step 2: identifiers at 31 characters (2026-10-22, not committed)

A scratch copy of the tree with `identLength = 31` in `SyntaxTree`, and
three changes it needed to build itself:

- `LiteralExprNodeDesc.lexeme` kept at 256 characters (a constant of its
  own): it holds string literals too;
- `LLVMCodeGenerator`'s `AppendStringLiteralArrayConstant` (32 characters)
  renamed;
- `LLVMCodeGenerator.DeclaredExternalDesc.name` made 256 characters: it
  holds a qualified name (`GarbageCollectedHeap.SetStackBase`), and cut
  short it lets one `declare` be written twice, which clang refuses. So
  `Ident` holds more than identifiers; step 4 must find every such use.

It then reached Stage 2's fixed point, and its objects for all of poc on
vax-dec-vms are the 255-character poc's byte for byte (all but
`BuildInfo`'s, which names its source's path). Measured as in step 1:

| figure                                  | cymoril 255 | 31    | atla 255 | 31    |
|-----------------------------------------|------------:|------:|---------:|------:|
| peak resident, all of poc (MB)          | 162.8       |  81.0 | 170.5    |  98.2 |
| peak resident, `VaxCodeGenerator` alone | 112.9       |  45.4 | 100.7    |  52.1 |
| peak resident, `Poc` alone              | 113.4       |  36.8 | 104.1    |  42.9 |
| live, every module checked (MB)         |  75.8       |  20.1 |  80.5    |  24.8 |
| live at the peak (`VaxCodeGenerator`)   |  97.4       |  41.8 | 109.7    |  54.1 |
| heap at the peak                        | 196         |  70   | 221      | 114   |

Item 1 is worth half of poc's memory, and three quarters of the front
end's. With it gone, the largest holders at the peak are the back end's
`VaxInstructions.Line` and `Specifier` (19.5 MB on atla), then
`SyntaxTree.Designator` (5.0 MB) and `SymbolTable.Object` (2.9 MB on
cymoril): item 3 comes next after item 1, ahead of item 2.

### Step 3: chunks from `$EXPREG`, tried and dropped (2026-10-22)

`POC_GET_PAGES` took a chunk's pages from `$EXPREG` (demand-zero, not
cleared) and `POC_FREE_PAGES` gave them back by `$DELTVA`, in place of
`POC_GET_MEMORY`'s `LIB$GET_VM` and `MOVC5`. `tools/bootstrap/vax-stages`
now also logs each stage's `WSPEAK` against `WSEXTENT` and its page
faults. V2 (poc built for the VAX, compiling poc on the guest, objects,
`-OC`), each way twice, all four at the fixed point:

| run                  | compile  | CPU     | page faults | `VIRTPEAK` | `WSPEAK` of `WSEXTENT` |
|----------------------|---------:|--------:|------------:|-----------:|-----------------------:|
| `LIB$GET_VM`, first  | 26.0 min | 1,520 s | 1,807,718   | 212,289    | 200,000 of 200,000     |
| `LIB$GET_VM`, second | 25.7 min | 1,506 s | 1,734,346   | 212,289    | 200,000 of 200,000     |
| `$EXPREG`, first     | 42.5 min | 2,518 s | 1,656,908   | 212,974    | 200,000 of 200,000     |
| `$EXPREG`, second    | 41.6 min | 2,466 s | 1,659,134   | 212,974    | 200,000 of 200,000     |

`$EXPREG` saved 4-8% of the page faults and nothing of the peaks, and
cost about 950 s of CPU (63%) and 16 minutes a compilation, so it was
dropped. Why it costs so much was not looked into. Either way the working
set fills its extent: what poc holds has to shrink (steps 4 onward), not
how the collector gets it.

### Step 4a: `SymbolTable`'s names interned (2026-10-22)

`Names`, and `SymbolTable.ObjectDesc`'s `name`, `externalConvention`,
`externalName` and `realModuleName` as `Names.Name`; callers that still
hold an `Ident` intern it for each lookup until 4b. `make check` on atla
and `gmake check-stage1` on cymoril, artos and alerik passed, with the
fixed point and the VAX objects unchanged.
`tools/bench/poc-memory.sh -poc <Stage 2 poc>`, objects, `-OC`, peak
resident size in MB, against step 1:

| run                          | cymoril, step 1 | cymoril, 4a | atla, step 1 | atla, 4a |
|------------------------------|----------------:|------------:|-------------:|---------:|
| all of poc, one program      | 162.8           | 131.6       | 170.5        | 140.9    |
| `Poc` alone                  | 113.4           |  94.0       | 104.1        |  94.6    |
| `VaxCodeGenerator` alone     | 112.9           |  79.4       | 100.7        |  89.9    |
| `VaxToolchainDriver` alone   |  82.1           |  68.6       |  76.8        |  66.3    |
| `SemanticActions` alone      |  53.2           |  46.8       |  52.1        |  48.5    |
| `Parser` alone               |  52.2           |  41.5       |  49.5        |  39.6    |
| `NestedProcedures` alone     |  44.4           |  38.9       |  47.0        |  38.0    |
| `ModuleInterface` alone      |  35.9           |  27.4       |  33.3        |  29.4    |

The census (cymoril, all of poc): `SymbolTable.Object` is 80 bytes, 1.2
MB for 15,186 (16.4 MB before). When the front end has checked every
module, 61.1 MB live (75.8) and a heap of 92 MB (108); at
`VaxCodeGenerator`, 82.8 MB live (97.4) and a heap of 165 MB (196). The
other records are as step 1 found them: `SyntaxTree.Designator` is still
28.4 MB, for 4b.
