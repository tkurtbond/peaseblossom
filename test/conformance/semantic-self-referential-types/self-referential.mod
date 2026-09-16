MODULE selfReferential;
  (* The classic Oberon-2 linked-structure idiom, in both its shapes
     (see SemanticActions.Mod's header comment on ResolveType/
     ResolveNamedType for why both need the early-registration fix):
     - a separately named pointer declared before the record it points
       to, whose own fields point back via that same pointer name
       (Tree/Node, mirroring test/conformance/parser-trees);
     - an inline pointer field naming its own enclosing record directly,
       with no separate pointer typedef at all (List);
     - a mutually-referential pair of records, each reachable from the
       other only through a pointer (Employee/Department). *)

  TYPE
    Tree = POINTER TO Node;
    Node = RECORD
      value: INTEGER;
      left, right: Tree
    END;

    List = RECORD
      value: INTEGER;
      next: POINTER TO List
    END;

    Employee = RECORD
      name: ARRAY 32 OF CHAR;
      dept: POINTER TO Department
    END;
    Department = RECORD
      title: ARRAY 32 OF CHAR;
      head: POINTER TO Employee
    END;
BEGIN
END selfReferential.
