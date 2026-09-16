MODULE directValueCycle;
  (* A record may not directly contain itself by value (infinite size) -
     contrast with test/conformance/semantic-self-referential-types,
     where the exact same name is reachable again only through a
     POINTER TO, which is always finite size regardless of its target. *)
  TYPE
    Bad = RECORD
      x: Bad
    END;
BEGIN
END directValueCycle.
