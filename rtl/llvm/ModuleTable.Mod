MODULE ModuleTable;

  (* PLAN.md Phase 9 step 4: the registry of every module's garbage-
     collector root table - what the collector (GarbageCollectedHeap.Mod)
     walks to find the pointers held in module-level variables.

     A *root table* is a block of words the backend
     (LLVMCodeGenerator.Mod) emits as a global for each module that has
     pointer-typed module variables, and only in a program that contains
     this module at all - so a program that never imports it pays for
     nothing here:

       word 0        next   the next registered table (0 for the last;
                            written by Register, which links tables into
                            one list)
       word 1        count  N, the number of slots below
       words 2..N+1  slot   the *address of* one pointer-typed location -
                            a whole pointer variable, or a pointer inside
                            a record or array variable, flattened exactly
                            like the type descriptors' pointer-offset
                            tables (LLVMCodeGenerator.EmitPointerOffsets)

     Every word is one target word wide. The compiled program's `_init`
     for each such module calls Register with the table's address before
     running the module's own body, so a pointer a module body stores
     into a variable is already visible to a collection the body triggers.
     Registration order is the reverse of module initialization order,
     which no reader depends on.

     Everything is plain SYSTEM.ADDRESS arithmetic: this module has no
     pointer variables of its own, hence no table of its own to register,
     and can safely be registered *into* before its own body has run. *)

  IMPORT SYSTEM;

  VAR
    head: SYSTEM.ADDRESS; (* the most recently registered table, 0 if none *)
    registered: LONGINT;

  PROCEDURE Register*(table: SYSTEM.ADDRESS);
  BEGIN
    SYSTEM.PUT(table, head);
    head := table;
    INC(registered)
  END Register;

  (* The first table of the registered list, or 0 when none is. *)
  PROCEDURE First*(): SYSTEM.ADDRESS;
  BEGIN
    RETURN head
  END First;

  PROCEDURE Next*(table: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR following: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(table, following);
    RETURN following
  END Next;

  PROCEDURE SlotCount*(table: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR count: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(table + SIZE(SYSTEM.ADDRESS), count);
    RETURN count
  END SlotCount;

  (* The address of the index'th pointer location (0-based) of table. *)
  PROCEDURE Slot*(table, index: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR location: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(table + (index + 2) * SIZE(SYSTEM.ADDRESS), location);
    RETURN location
  END Slot;

  PROCEDURE TableCount*(): LONGINT;
  BEGIN
    RETURN registered
  END TableCount;

END ModuleTable.
