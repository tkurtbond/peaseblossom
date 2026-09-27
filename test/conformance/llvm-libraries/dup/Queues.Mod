MODULE Queues;
  IMPORT Lists;
  PROCEDURE Len*(l: Lists.List): INTEGER;
    VAR n: INTEGER;
  BEGIN n := 0; WHILE l # NIL DO INC(n); l := l.next END; RETURN n
  END Len;
END Queues.
