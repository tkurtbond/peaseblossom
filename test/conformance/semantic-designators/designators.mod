MODULE designators;
  (* Designator/selector resolution (Oberon2.pdf §8.1, PLAN.md Phase 5):
     field, index, and dereference selectors, including auto-deref
     through a pointer for both "." and "[" ("record and array selectors
     imply dereferencing"), and inherited-field lookup through a record
     extension (Types.FindField's own base-chain walk). *)

  TYPE
    Node = RECORD
      value: INTEGER;
      children: ARRAY 4 OF INTEGER;
      next: POINTER TO Node
    END;
    CenterNode = RECORD (Node)
      weight: INTEGER
    END;

  VAR
    n: Node;
    p: POINTER TO Node;
    c: CenterNode;
    i: INTEGER;
BEGIN
  n.value := 1;
  n.children[0] := 2;
  p.value := 3;          (* auto-deref through the pointer *)
  p.children[1] := 4;    (* auto-deref, then index *)
  p.next.value := 5;     (* auto-deref through a chain of pointers *)
  i := n.children[0];
  c.value := 6;          (* inherited field, found via the base chain *)
  c.weight := 7
END designators.
