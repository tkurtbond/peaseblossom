MODULE Names;

  (* Identifiers interned (doc/developer/vms-memory.md, step 4): one copy of
     each distinct identifier's text, sized to fit, shared by every record
     that names it. A Name comes only from Intern, which returns the same
     Name for the same text, so two Names are the same identifier exactly
     when they are the same pointer - a lookup compares pointers, not text.

     NIL is the empty name (decided with the user, 2026-10-22): Intern("")
     returns NIL, so "no name" is tested as `= NIL`, and reading an empty
     name's text with `^` traps, as a missing name should.

     The table is chains of entries, hashed, doubled when it holds twice as
     many names as chains. The hash is taken MOD hashModulus at each step,
     so it never overflows: Stage 0's C would not promise that an overflow
     wraps. Names are never freed: an identifier lives as long as poc. *)

  CONST
    initialChains = 256;
    (* a prime below 2^20: hash * 31 + 255 stays below 2^31 *)
    hashModulus = 1048573;

  TYPE
    Name* = POINTER TO ARRAY OF CHAR;

    Entry = POINTER TO EntryDesc;
    EntryDesc = RECORD
      name: Name;
      hash: LONGINT;
      next: Entry
    END;

    Chains = POINTER TO ARRAY OF Entry;

  VAR
    chains: Chains;
    nameCount: LONGINT;

  PROCEDURE HashOf(text: ARRAY OF CHAR; length: LONGINT): LONGINT;
    VAR i, hash: LONGINT;
  BEGIN
    hash := 0;
    FOR i := 0 TO length - 1 DO hash := (hash * 31 + ORD(text[i])) MOD hashModulus END;
    RETURN hash
  END HashOf;

  PROCEDURE SameText(name: Name; text: ARRAY OF CHAR; length: LONGINT): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    IF LEN(name^) # length + 1 THEN RETURN FALSE END;
    i := 0;
    WHILE (i < length) & (name[i] = text[i]) DO INC(i) END;
    RETURN i = length
  END SameText;

  PROCEDURE DoubleChains;
    VAR larger: Chains; entry, following: Entry; i, chain: LONGINT;
  BEGIN
    NEW(larger, 2 * LEN(chains^));
    FOR i := 0 TO LEN(larger^) - 1 DO larger[i] := NIL END;
    FOR i := 0 TO LEN(chains^) - 1 DO
      entry := chains[i];
      WHILE entry # NIL DO
        following := entry.next;
        chain := entry.hash MOD LEN(larger^);
        entry.next := larger[chain]; larger[chain] := entry;
        entry := following
      END
    END;
    chains := larger
  END DoubleChains;

  (* The Name whose text is text up to its first 0X (all of it if it has
     none); NIL when that is empty. *)
  PROCEDURE Intern*(text: ARRAY OF CHAR): Name;
    VAR length, hash, chain, i: LONGINT; entry: Entry; name: Name;
  BEGIN
    length := 0;
    WHILE (length < LEN(text)) & (text[length] # 0X) DO INC(length) END;
    IF length = 0 THEN RETURN NIL END;
    hash := HashOf(text, length);
    chain := hash MOD LEN(chains^);
    entry := chains[chain];
    WHILE (entry # NIL) & ~((entry.hash = hash) & SameText(entry.name, text, length)) DO
      entry := entry.next
    END;
    IF entry # NIL THEN RETURN entry.name END;
    NEW(name, length + 1);
    FOR i := 0 TO length - 1 DO name[i] := text[i] END;
    name[length] := 0X;
    NEW(entry); entry.name := name; entry.hash := hash;
    entry.next := chains[chain]; chains[chain] := entry;
    INC(nameCount);
    IF nameCount > 2 * LEN(chains^) THEN DoubleChains END;
    RETURN name
  END Intern;

  (* TRUE when name's text is text up to its first 0X; NIL is "" *)
  PROCEDURE Equals*(name: Name; text: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    IF name = NIL THEN RETURN text[0] = 0X END;
    i := 0;
    WHILE (i < LEN(text)) & (text[i] # 0X) & (name[i] = text[i]) DO INC(i) END;
    RETURN ((i = LEN(text)) OR (text[i] = 0X)) & (name[i] = 0X)
  END Equals;

  (* name's text into text, cut to text's length; "" for NIL *)
  PROCEDURE GetText*(name: Name; VAR text: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    IF name # NIL THEN
      WHILE (i < LEN(text) - 1) & (name[i] # 0X) DO text[i] := name[i]; INC(i) END
    END;
    text[i] := 0X
  END GetText;

  PROCEDURE Init;
    VAR i: LONGINT;
  BEGIN
    NEW(chains, initialChains);
    FOR i := 0 TO initialChains - 1 DO chains[i] := NIL END;
    nameCount := 0
  END Init;

BEGIN
  Init
END Names.
